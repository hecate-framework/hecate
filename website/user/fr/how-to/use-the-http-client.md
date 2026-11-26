---
description: Envoyer des requêtes avec hecate.http.Client, lire ou diffuser les réponses, réutiliser des connexions du pool, suivre les redirections, fixer des délais et traiter les échecs.
hecate: "0.x"
lua: "5.5"
order: 10
source_revision: 127cb3d2f023c24467492b8959dd7bc7bc0390d7
---

# Utiliser le client HTTP

Ce guide montre comment appeler un serveur HTTP avec `http.Client`. Il est écrit pour hecate 0.x et Lua 5.5.

Exécutez les appels dans `reactor.run`. Chaque appel *suspend* la [coroutine](../reference/glossary.md#concurrency)
en cours, l’unité d’exécution de Lua, pendant qu’il attend le réseau : le réacteur exécute entre-temps d’autres
coroutines. Comme le serveur, le client a besoin du module natif llhttp (`lua tools/run.lua build-native http`).

## Appeler une API JSON {#call-a-json-api}

Cinq lignes font tout le travail : créer le client, appeler, décoder, utiliser. Contre une vraie API, seule l’URL
change, par exemple `client:get("https://api.example.org/users/42")`. L’exemple ci-dessous s’exécute contre un
serveur local afin d’être testable.

<!-- example: packages/http/examples/hecate.http.Client.json.lua -->
```lua
-- Call a JSON API and decode the answer. The API is a local server here;
-- with a real one only the URL changes.
local reactor = require("hecate.reactor")
local json = require("hecate.json")
local http = require("hecate.http")

local function action(request)
  -- http never serialises: the action encodes the table and names its
  -- media type
  return http.Response(200, {
    content = json.encode({ id = 42, name = "Ada" }),
    fields = http.Fields({ { "Content-Type", "application/json" } }),
  })
end

reactor.run(function()
  local server = http.Server(action, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local client <close> = http.Client()
  local response = client:get("http://127.0.0.1:" .. listener:local_address().port .. "/users/42")
  local user = response:read_json()
  print(response.status .. " " .. user.name)
  -- Prints: 200 Ada
  server:shutdown()
  reactor.join(serving)
end)
```

`response:read_json(limit?)` lit le contenu, borné comme `read_content`, et le décode. Un contenu qui n’est pas du
JSON lève une `core.ProtocolError` dont `context.reason` vaut `invalid_json`. Le message de l’erreur ne contient
jamais le contenu.

`response:media_type()` renvoie le `Content-Type` analysé, ou `nil` quand il est absent ou mal formé. Utilisez-le
pour vérifier le type de média avant de décoder.

## Envoyer des requêtes {#send-requests}

`http.Client(options?)` crée un client avec son propre pool de connexions. Fermez-le avec `<close>` quand vous avez
fini.

L’exemple démarre un petit serveur, envoie une requête JSON, puis lit une seconde réponse fragment par fragment.

<!-- example: packages/http/examples/hecate.http.Client.lua -->
```lua
-- A client with its pool. The server echoes what it receives; the client
-- sends JSON, then reads a response chunk by chunk and releases its
-- connection.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function action(request)
  local content = request:read_content()
  return http.Response(200, { content = request.method .. " " .. request.path .. " " .. #content })
end

reactor.run(function()
  local server = http.Server(action, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local base = "http://127.0.0.1:" .. listener:local_address().port
  local client <close> = http.Client({ request_timeout = 10 })

  local created = client:post(base .. "/items", { name = "pen" })
  print(created.status .. " " .. created:read_content())
  -- Prints: 200 POST /items 14

  local response <close> = client:get(base .. "/items/7")
  local stream = response:stream_content()
  while true do
    local chunk = stream:read()
    if chunk == nil then break end
    print(chunk)
  end
  -- Prints: GET /items/7 0

  server:shutdown()
  reactor.join(serving)
end)
```

La méthode de l’appel nomme la méthode HTTP :

| Appel | Méthodes |
|---|---|
| `client:request(method, url, options?)` | n’importe quelle méthode |
| `client:get(url, options?)` | aussi `head`, `delete` et `options` |
| `client:post(url, content?, options?)` | aussi `put` et `patch` |

L’URL doit être absolue, `http` ou `https`, et sans informations d’utilisateur. Tout le reste lève une
`ArgumentError` qui dit pourquoi, par exemple :

```text
http.Client:request: invalid URL: userinfo in a URL is refused (RFC 9110 section 4.2.4)
```

Le client envoie le champ `Host` tiré de l’URL. Il fixe lui-même `Content-Length` ou `Transfer-Encoding`.

## Envoyer du contenu {#send-content}

Le contenu d’une requête est l’un de :

- une chaîne, envoyée avec `Content-Length` ;
- une table, envoyée en JSON avec `Content-Type: application/json` ;
- une fonction `content(write)`, diffusée avec le codage par fragments, et jamais rejouée.

```lua
local response = client:put(base .. "/items/7", { name = "pencil" }, {
  fields = { Authorization = "Bearer " .. token },
  request_timeout = 5,
})
```

Les `options` d’une requête sont :

- `fields` (une table ou un objet `Fields`) ;
- `content`, `form` et `multipart`, qui s’excluent mutuellement ;
- `redirects`, `cross_origin_redirects` et `expect_continue` ;
- `request_timeout`, `head_timeout` et `content_timeout` ;
- `max_content` et `max_redirects`.

Toute autre clé lève une `ArgumentError`, qui suggère le nom valide le plus proche quand il y en a un. `strip_on_redirect`
et les autres réglages appartiennent au client (voir [`ClientOptions`](../reference/http/ClientOptions.md)). Les
formulaires sont dans [Traiter les formulaires et le multipart](handle-forms-and-multipart.md).

## Lire la réponse {#read-the-response}

Un appel revient quand la [tête](../reference/glossary.md#http) (*head*) de la réponse est arrivée : sa ligne
d’état et ses champs. `response.status` et `response.fields` sont fixés aussitôt.

Un 404 ou un 500 est un retour normal, pas une erreur. Testez `response:is_successful()` (un 2xx) ou le code
d’état. Seul un échec de l’échange lève une erreur.

Le contenu est lu paresseusement :

- `response:read_content(limit?)` renvoie tout le contenu. La borne par défaut est 10 Mio (`max_content`). Au-delà,
  elle lève `http.ContentError` avec `context.reason = "too_large"`.
- `response:stream_content()` renvoie un `ContentStream`. Rien n’est tamponné au-delà d’une lecture.

### Rendre la connexion {#give-the-connection-back}

Une réponse dont le contenu n’est pas lu retient sa connexion, et sa place dans le pool. Elle les retient jusqu’à ce
que le contenu soit lu jusqu’au bout, ou que `response:close()` soit appelé. `close` abandonne la connexion.

Déclarez la réponse avec `<close>` quand vous la diffusez, comme le fait l’exemple. Les réponses à HEAD, 204, 304 et
à un contenu de longueur nulle rendent aussitôt leur connexion.

## Le pool {#the-pool}

Le client garde des connexions par [origine](../reference/glossary.md#http) (*origin*) : le schéma, l’hôte et le
port d’une URL.

| Borne | Défaut | Option |
|---|---|---|
| connexions par origine, en service ou inactives ; la requête suivante attend | 8 | `max_connections_per_origin` |
| connexions inactives au total | 64 | `max_idle_connections` |
| durée de vie d’une connexion inactive | 30 s | `idle_timeout` |

La durée de vie à l’inactivité est plus courte que les 75 secondes du serveur, si bien que le client ferme en
premier.

Une connexion réutilisée peut se révéler morte avant qu’aucun octet de la réponse n’arrive. La requête est alors
retentée une fois, sur une nouvelle connexion. Cela ne vaut que pour les méthodes idempotentes avec un contenu
rejouable : un POST n’est jamais répété.

`client:pool_stats()` rapporte `idle` et `origins`. `client:close()` ferme les connexions inactives et refuse les
requêtes suivantes : une requête sur un client fermé lève `core.StateError`.

## Redirections {#redirects}

Le client suit 301, 302, 303, 307 et 308 quand ils portent un `Location`, jusqu’à 10 fois (`max_redirects`).
Passez `redirects = false` pour recevoir la réponse de redirection elle-même.

- 301 et 302 transforment un POST en GET. 303 transforme tout sauf GET et HEAD en GET.
- `Authorization`, `Cookie`, `Proxy-Authorization`, `X-Api-Key` et `X-Auth-Token` sont retirés quand l’origine
  change. Ajoutez d’autres noms avec `strip_on_redirect`.
- Un 307 ou 308 qui enverrait le contenu à une autre origine n’est pas suivi : la réponse est renvoyée. Fixez
  `cross_origin_redirects = true` pour le suivre.
- Une redirection de https vers http est refusée, sauf si vous fixez `allow_downgrade = true`.

Une redirection qui échoue lève une `ProtocolError`. Son `context.reason` dit pourquoi :

| Échec | `context.reason` |
|---|---|
| une boucle | `redirect_loop` |
| une chaîne trop longue | `too_many_redirects` |
| un abaissement de https vers http | `downgrade` |
| un mauvais `Location` | `bad_location` |

## Échéances {#deadlines}

Chaque [délai](../reference/glossary.md#concurrency) (*timeout*), une durée relative en secondes, borne une partie
de l’échange :

| Option | Défaut | Borne |
|---|---|---|
| `connect_timeout` | 10 s | la connexion et la poignée de main TLS |
| `head_timeout` | 30 s | de la fin de la requête à la fin de la tête de la réponse |
| `content_timeout` | 60 s | l’attente entre deux lectures de contenu |
| `write_timeout` | 60 s | une écriture vers le serveur |
| `request_timeout` | 300 s | toute la requête, redirections et contenu compris |

Un contenu de réponse qui reste bloqué plus longtemps que `content_timeout` lève `http.ContentError` avec
`context.reason = "timeout"`, comme le fait le serveur pour un contenu de requête. Les autres délais lèvent
`core.DeadlineExceededError`. Cela inclut `request_timeout` quand il expire pendant le contenu.

`request_timeout` peut être fixé pour une seule requête, dans ses options. Un téléchargement diffusé qui dure
légitimement plus de cinq minutes demande une valeur plus grande. Une requête annulée ou échouée abandonne sa
connexion.

## Traiter les échecs {#handle-failures}

Les erreurs sont des objets d’erreur de `core`. Voici celles que vous attraperez :

- `reactor.TransportError` : la connexion a échoué. Son message et `context.attempts` peuvent lister les adresses
  en lesquelles un nom s’est résolu. Ne les transmettez pas à un [pair](../reference/glossary.md#concurrency)
  (*peer*).
- `core.DeadlineExceededError` : un délai a expiré (tous sauf `content_timeout`).
- `net.EndOfStreamError` : le serveur a fermé avant ou pendant la réponse.
- `net.TlsError` : la poignée de main TLS ou la vérification a échoué.
- `http.ParseError` : la réponse est mal formée, ou dépasse une limite de `parser`.
- `http.ContentError` : le contenu dépasse `max_content` (`context.reason` vaut `too_large`), ou est resté bloqué
  plus longtemps que `content_timeout` (`timeout`).
- `core.ProtocolError` : un problème de redirection, ou une réponse refusée (101 et les mises à niveau sont
  refusés).

```lua
local ok, err = pcall(function() return client:get(url):read_json() end)
if not ok then
  if core.is_instance_of(err, core.DeadlineExceededError) then
    -- trop lent
  elseif core.is_instance_of(err, http.ContentError) then
    -- trop volumineux ou bloqué : err.context.reason dit lequel
  elseif core.is_instance_of(err, http.ParseError) or core.is_instance_of(err, core.ProtocolError) then
    -- le serveur a répondu quelque chose d’invalide, ou une redirection a
    -- mal tourné : err.context.reason dit lequel
  else
    error(err, 0) -- un échec de transport ou de TLS, ou un bogue
  end
end
```

La `ContentError` du client ne porte pas de `context.status` : un code d’état revient au serveur. Si elle s’échappe
d’une action, le serveur y répond par un 500.

> [!WARNING] Le client ne filtre pas les adresses
> Un programme qui récupère des URL choisies par quelqu’un d’autre (webhooks, aperçus de liens) doit refuser
> lui-même les adresses privées, de boucle locale et de lien local. Une redirection peut y mener. Passez
> `redirects = false` et validez chaque `Location`. Le client n’a pas encore de crochet `connect` (OQ-74).

## HTTPS {#https}

Pour https, le client fait confiance au magasin du système, et on ne peut pas lui dire de sauter la vérification.
Les options TLS du client sont dans
[Définir les limites, les délais et TLS du serveur HTTP](http-limits-timeouts-and-tls.md#tls).

## Ce qui n’existe pas encore {#what-does-not-exist-yet}

- les proxys HTTP ;
- la compression ;
- un pot de cookies ;
- HTTP/2 ;
- `Retry-After`, et vos propres reprises. Seule une requête sur une connexion du pool morte est répétée une fois,
  comme décrit dans [Le pool](#the-pool).

## Voir aussi {#see-also}

- [Traiter les formulaires et le multipart](handle-forms-and-multipart.md)
- [Définir les limites, les délais et TLS du serveur HTTP](http-limits-timeouts-and-tls.md)
- [Le modèle HTTP](../explanation/http-model.md)
