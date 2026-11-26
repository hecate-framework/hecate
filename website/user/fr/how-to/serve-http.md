---
description: Servir du HTTP/1.1 avec hecate.http.Server, écrire une action qui renvoie des chaînes, du JSON et des détails de problème, lire la requête, poser des cookies et arrêter le serveur en douceur.
hecate: "0.x"
lua: "5.5"
order: 8
source_revision: 127cb3d2f023c24467492b8959dd7bc7bc0390d7
---

# Servir du HTTP

Ce guide montre comment démarrer un serveur HTTP/1.1 avec `hecate.http.Server`, répondre à des requêtes et arrêter
proprement le serveur. Il est écrit pour hecate 0.x et Lua 5.5, et suppose que vous savez
[vous connecter et servir en TCP](connect-and-serve-over-tcp.md). Pour les raisons de la conception, lisez
[Le modèle HTTP](../explanation/http-model.md).

`hecate.http` est une couche de protocole, sans routage. Vous donnez au serveur une seule
[action](../reference/glossary.md#object-model-and-architecture) (*action*), la fonction qui sert une requête, et le
serveur l’appelle pour chaque requête. Le routage, les filtres et la validation viennent des couches supérieures
(voir [Acheminer les requêtes](route-requests.md)).

Les appels qui attendent le réseau *suspendent* la [coroutine](../reference/glossary.md#concurrency) en cours,
l’unité d’exécution de Lua : la coroutine attend, et le réacteur exécute entre-temps d’autres coroutines. Exécutez
le serveur dans `reactor.run`, qui exécute une fonction dans une coroutine gérée par le réacteur.

> [!NOTE] Le module natif
> Le serveur, le client et l’analyseur ont besoin du module natif llhttp (`lua tools/run.lua build-native http`).
> `require("hecate.http")` fonctionne sans lui : le modèle de message, les formulaires et les cookies sont là.
> `Server`, `Client` et `Parser` valent alors nil, et `http.available()` renvoie `false` et la raison.

## Hello world {#hello-world}

Quatre lignes servent `hello` sur `127.0.0.1:8080`. Exécutez le fichier, puis interrogez-le depuis un autre
terminal avec `curl http://127.0.0.1:8080/`. Il répond `hello`.

<!-- example: packages/http/examples/hecate.http.Server.hello.lua -->
```lua
-- The smallest server: it listens on 127.0.0.1:8080 and answers every
-- request with "hello".
local http, reactor = require("hecate.http"), require("hecate.reactor")
local function action() return http.Response(200, { content = "hello\n" }) end
reactor.run(function() http.Server(action, { port = 8080 }):serve() end)
-- Answers: hello
```

Au démarrage, le serveur journalise un enregistrement d’information :
`http.Server: listening on 127.0.0.1:8080 (loopback only)`. Il part sur le flux d’erreur standard, par le
journaliseur par défaut (`log.default()`). Passez votre propre `logger` (un `hecate.log.Logger`) pour le remplacer.

## Démarrer un serveur {#start-a-server}

`http.Server(action, options?)` crée un serveur. Rien n’est encore lié.

- `server:listen()` lie l’adresse et renvoie l’écouteur.
- `server:serve(listener?)` accepte des connexions jusqu’à l’arrêt du serveur.

L’exemple ci-dessous sert trois chemins, interroge chacun avec le client, puis arrête le serveur.

<!-- example: packages/http/examples/hecate.http.Server.lua -->
```lua
-- A server on a free port. The action answers with a string, JSON text
-- (http never serialises) and a function that streams its content, then
-- the server shuts down.
local json = require("hecate.json")
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function action(request)
  if request.path == "/hello" then
    return http.Response(200, { content = "hello" })
  elseif request.path == "/user" then
    return http.Response(200, { content = json.encode({ name = "Ada" }) })
  elseif request.path == "/count" then
    return http.Response(200, {
      content = function(write)
        for i = 1, 3 do write(i .. "\n") end
      end,
    })
  end
  return http.problem.response(404)
end

reactor.run(function()
  local server = http.Server(action, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local base = "http://127.0.0.1:" .. listener:local_address().port
  local client <close> = http.Client()
  print(client:get(base .. "/hello"):read_content())
  -- Prints: hello
  print(client:get(base .. "/user"):read_content())
  -- Prints: {"name":"Ada"}
  print((client:get(base .. "/count"):read_content():gsub("\n", " "):gsub(" $", "")))
  -- Prints: 1 2 3
  print(client:get(base .. "/missing").status)
  -- Prints: 404
  server:shutdown()
  reactor.join(serving)
end)
```

`serve` ne revient qu’une fois toutes les connexions terminées. Démarrez-le avec `fork`, comme le fait l’exemple, et
attendez-le avec `join` après `shutdown`.

## Choisir l’adresse {#choose-the-address}

L’hôte par défaut est `127.0.0.1` : le serveur n’est joignable que depuis cette machine. Pour servir toutes les
interfaces, dites-le :

```lua
local server = http.Server(action, { host = "0.0.0.0", port = 8080 })
```

- Utilisez `"::"` pour IPv6.
- L’hôte doit être une adresse numérique. Un nom lève une `ArgumentError`, car un nom peut se résoudre en plusieurs
  adresses.
- Le port par défaut est 8080. Le port `0` choisit un port libre, et `listener:local_address().port` vous dit
  lequel.

> [!WARNING] La valeur par défaut est la boucle locale, volontairement
> Un serveur qui démarre par défaut sur toutes les interfaces est exposé par accident. L’ouvrir est à une option de
> distance, et c’est à vous de la fixer. Dans un conteneur, le serveur doit écouter sur `"0.0.0.0"`. Avec la valeur
> par défaut, `docker run -p 8080:8080` publie un port auquel rien ne répond. Depuis l’hôte, le symptôme est une
> connexion réinitialisée ou fermée aussitôt.

## Connaître les valeurs par défaut {#know-the-defaults}

- `host` vaut `127.0.0.1` et `port` vaut 8080 (voir plus haut).
- Le contenu d’une requête est limité à 1 Mio. Au-delà, c’est un 413, avant l’exécution de votre action quand la
  longueur est déclarée.
- `request_timeout` vaut 300 secondes pour une requête entière.
- Il n’y a aucun délai sur l’action et aucune limite sur le nombre de connexions.

Chaque limite et sa valeur par défaut figurent dans [le tableau des limites](http-limits-timeouts-and-tls.md#set-limits)
et dans `Server.DEFAULTS`.

## Écrire une action {#write-an-action}

L’action prend une `Request` et renvoie une `Response`. Le serveur l’exécute une fois par requête, dans une
coroutine et dans une [portée](../reference/glossary.md#concurrency) (*scope*) qui lui sont propres : la région de
concurrence structurée qui possède ce que l’action démarre. L’action peut se suspendre : lire le contenu, appeler
une base de données, appeler le client.

### Lire la requête {#read-the-request}

Une `Request` a ces champs et méthodes :

- `method`, par exemple `"POST"`.
- `target`, la cible brute de la requête, et ses parties `path` et `query` (`nil` sans requête de recherche).
- `fields`, un objet `Fields` insensible à la casse : `request.fields:get("Content-Type")`.
- `peer_address()`, `cookies()` et `media_type()`.
- `read_content(limit?)`, `stream_content()`, `read_form()` et `stream_parts()`. Voir
  [Diffuser du contenu HTTP](stream-http-content.md) et
  [Traiter les formulaires et le multipart](handle-forms-and-multipart.md).

`path` et `query` sont bruts : tels que reçus, sans décodage des pourcentages et sans normalisation. `%2F` reste
`%2F`, et les [segments point](../reference/glossary.md#http) (`.` et `..`) restent.

### Construire la réponse {#build-the-response}

`http.Response(status, options?)` crée une réponse. Les options sont `fields` (un objet `Fields`), `content` et
`reason`. Le contenu est l’un de :

| Contenu | Envoyé comme |
|---|---|
| `nil` | aucun contenu |
| une chaîne | les octets, avec `Content-Length` |
| une fonction `content(write, flush)` | un flux (voir [Diffuser du contenu HTTP](stream-http-content.md)) |

`http` ne traite que des octets et ne sérialise jamais. `http.Response` lève une `ArgumentError` pour un contenu qui
n’est ni nil, ni une chaîne, ni une fonction, table comprise. Encodez la table vous-même (`json.encode`) et fixez
`Content-Type`, comme le fait l’exemple.

Une table peut tout de même atteindre le serveur dans un objet réponse qui a contourné le constructeur. Le serveur
la traite comme une erreur : le client reçoit la réponse générique de détails de problème 500, et le serveur
journalise l’échec.

Construisez les champs à partir d’une table, ou d’un objet `Fields` :

```lua
local fields = http.Fields({ ["Content-Type"] = "text/plain" })
fields:add("Cache-Control", "no-store")
return http.Response(200, { fields = fields, content = "ready" })
```

`Fields` lève une `hecate.core.ArgumentError` pour un nom qui n’est pas un jeton. Elle en lève une aussi pour une
valeur contenant CR, LF, NUL ou un autre caractère de contrôle ; HTAB est autorisé. Une réponse invalide devient un
500 : un code d’état hors de 100 à 599, ou un contenu d’un autre type.

### Savoir ce que le serveur fixe {#know-what-the-server-sets}

Le serveur n’envoie jamais de contenu pour HEAD, 1xx, 204, 205 et 304. Un 205 part avec `Content-Length: 0`.

Le serveur fixe lui-même `Content-Length`, `Transfer-Encoding` et `Connection`, et remplace les vôtres. Il y a deux
exceptions :

- Pour un contenu diffusé, un `Content-Length` que vous fixez est la longueur que vous promettez. Quand la fonction
  écrit un autre nombre d’octets, le serveur coupe le contenu et ferme la connexion.
- Un 304 garde un `Content-Length` que vous fixez, et n’envoie aucun contenu.

Le serveur ajoute un champ `Date` quand la réponse n’en a pas. Un `Date` que vous fixez est conservé.

## Répondre aux erreurs avec des détails de problème {#answer-errors-with-problem-details}

Une réponse d’erreur est composée de [détails de problème](../reference/glossary.md#http) (*problem details*) : un
objet JSON de la [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457), avec le type de média
`application/problem+json`.

`http.problem.response(status, detail?)` en construit un. Son `type` est `about:blank` et son `title` la phrase de
raison du code d’état. Le code d’état doit être de 400 à 599.

```lua
return http.problem.response(409, "The name is already taken.")
```

Quand l’action lève une erreur, le serveur répond avec des détails de problème génériques, choisis d’après la classe
de l’erreur. Le texte de l’erreur n’atteint jamais le client : ni message, ni adresse, ni numéro d’erreur.

- Une erreur de `hecate.http` qui porte un code d’état client le garde. Un contenu au-delà de la limite est un 413,
  un formulaire mal formé est un 400, et un formulaire d’un autre type de média est un 415.
- Toute autre erreur est un 500.

Le serveur journalise aussi l’erreur à la gravité `error`, par le journaliseur par défaut ou votre `logger`. Puis il
passe l’erreur à `on_error`, que vous pouvez utiliser pour prendre la main :

```lua
local server = http.Server(action, {
  on_error = function(err) io.stderr:write(tostring(err), "\n") end,
})
```

Une application de `hecate.kernel` fait correspondre pour vous les erreurs de son domaine à des détails de
problème : voir
[Faire correspondre les erreurs du domaine à des détails de problème](../../../../user/en/how-to/map-domain-errors-to-problem-details/).

## Poser des cookies {#set-cookies}

`request:cookies()` renvoie une table du nom vers la valeur. Pour poser un cookie, formatez un champ `Set-Cookie`
avec `http.SetCookie`, et ajoutez-le avec `response:set_cookie(cookie)`. Chaque cookie est envoyé dans son propre
champ `Set-Cookie`.

```lua
local session = request:cookies().session
local response = http.Response(200, { content = "welcome" })
response:set_cookie(http.SetCookie({
  name = "session", value = "abc123", path = "/", http_only = true, secure = true, same_site = "Lax",
}))
return response
```

## Arrêter le serveur {#stop-the-server}

`server:shutdown(grace_timeout?)` arrête le serveur et revient une fois que `serve` est revenu. Il procède dans
l’ordre :

1. Il cesse d’accepter des connexions.
2. Il ferme les connexions inactives : celles qui ont servi une requête et attendent la suivante, sans aucun octet
   de celle-ci.
3. Il laisse chaque requête en cours se terminer, y compris une dont la tête est arrivée en partie. Leurs réponses
   portent `Connection: close`.
4. À l’expiration de la [période de grâce](../reference/glossary.md#http) (*grace period*) (`grace_timeout`,
   30 secondes par défaut), il annule les requêtes restantes.

Une connexion acceptée juste avant l’arrêt, qui n’a envoyé aucun octet, n’est pas fermée immédiatement. Elle dispose
de 1 seconde, ou de la période de grâce quand elle est plus courte, pour commencer sa requête. Elle est fermée si
aucune requête ne commence.

Il n’y a pas de forme `<close>` pour un serveur. `shutdown` se suspend pendant qu’il attend les requêtes, et une
portée `<close>` ne peut pas se suspendre.

Un programme arrête son serveur sur `SIGINT` ou `SIGTERM`. Un calcul attend le signal, et `select` revient quand il
arrive :

<!-- example: packages/http/examples/hecate.http.Server.shutdown.lua -->
```lua
-- Stop a server on SIGINT or SIGTERM: one computation waits for the signal,
-- another serves, and the shutdown gives the requests in flight ten seconds.
-- A `<close>` scope cannot stop a server, because `shutdown` suspends while
-- it waits for them. Here a request stands in for the signal.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function action() return http.Response(200, { content = "hello" }) end

reactor.run(function()
  local server = http.Server(action, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local signalled = reactor.fork(reactor.wait_signal, "sigint", "sigterm")
  -- In a program, only the signal ends the wait.
  local finished = reactor.fork(function()
    local client <close> = http.Client()
    print(client:get("http://127.0.0.1:" .. listener:local_address().port .. "/"):read_content())
    -- Prints: hello
  end)
  reactor.select(signalled, finished)
  server:shutdown(10)
  reactor.join(serving)
end)
```

## Ce que le serveur fait pour vous {#what-the-server-does-for-you}

- Il garde ouvertes des [connexions persistantes](../reference/glossary.md#http) (*persistent connections*,
  keep-alive) pour plusieurs requêtes.
- Il répond aux requêtes [envoyées en pipeline](../reference/glossary.md#http) (*pipelined*) dans l’ordre des
  requêtes.
- Il répond à `Expect: 100-continue` quand l’action lit le contenu pour la première fois. Toute autre attente d’une
  requête HTTP/1.1 est un 417.
- Il répond par un 400 à une requête HTTP/1.1 sans exactement un champ `Host`, et à toute requête avec plusieurs
  lignes `Host`.
- Il répond par un 400 à une cible de requête avec un fragment (`/a#x`), et à la cible `*` avec une méthode autre
  que `OPTIONS`.
- Il répond par un 501 à une requête `Upgrade` ou `CONNECT`.

## Borner l’action vous-même {#bound-the-action-yourself}

Le serveur n’impose aucun délai à l’action. Une action qui ne revient jamais retient sa connexion. Bornez-la
vous-même avec `reactor.deadline` dans l’action : voir
[Définir les limites, les délais et TLS du serveur HTTP](http-limits-timeouts-and-tls.md#deadline-for-an-action) et
[Échéances et annulation sur les flux](deadlines-and-cancellation.md).

## Voir aussi {#see-also}

- [Diffuser du contenu HTTP](stream-http-content.md)
- [Traiter les formulaires et le multipart](handle-forms-and-multipart.md)
- [Définir les limites, les délais et TLS du serveur HTTP](http-limits-timeouts-and-tls.md)
- [Utiliser le client HTTP](use-the-http-client.md)
- [Le modèle HTTP](../explanation/http-model.md)
