---
description: Lire le contenu d’une requête fragment par fragment, diffuser une réponse avec une fonction, et savoir comment le serveur cadre, borne et purge le contenu.
hecate: "0.x"
lua: "5.5"
order: 9
source_revision: 127cb3d2f023c24467492b8959dd7bc7bc0390d7
---

# Diffuser du contenu HTTP

Ce guide montre comment lire le contenu d’une requête, et écrire le contenu d’une réponse, sans tout garder en
mémoire. Il est écrit pour hecate 0.x et Lua 5.5, et suppose que vous savez [servir du HTTP](serve-http.md).

La diffusion repose sur la [contre-pression](../reference/glossary.md#concurrency) (*back-pressure*) : un producteur
se suspend tant que son consommateur est plus lent, au lieu de tamponner sans borne. Sur le serveur, elle joue dans
les deux sens :

- Un client qui envoie plus vite que votre action ne lit attend dans les tampons du noyau.
- Un client qui lit plus lentement que votre action n’écrit suspend l’écriture.

## Lire le contenu d’une requête {#read-the-content-of-a-request}

Le serveur ne lit le contenu d’une requête que lorsque l’action le demande. Il y a deux façons de le demander.

`request:read_content(limit?)` renvoie tout le contenu sous forme de chaîne :

```lua
local body = request:read_content(64 * 1024)
```

Le contenu est borné par l’option `max_content` du serveur (1 Mio par défaut), et par `limit` quand elle est plus
basse. Un contenu au-delà de la borne lève une `ContentError` avec le code d’état 413. Quand la requête déclare un
`Content-Length` supérieur à `max_content`, l’action ne s’exécute même pas.

`request:stream_content()` renvoie un `ContentStream`, que vous lisez fragment par fragment. Son `read()` renvoie le
fragment suivant, et `nil` après le dernier :

```lua
local stream = request:stream_content()
local size = 0
while true do
  local chunk = stream:read()
  if chunk == nil then break end
  size = size + #chunk
end
```

Un `ContentStream` a aussi `read_all(limit?)`, qui collecte le reste, et `is_finished()`, qui dit si la fin a été
atteinte. Le flux d’une requête est lui aussi borné par `max_content`.

### Ce qu’il advient du contenu que l’action ne lit pas {#what-happens-to-content-the-action-does-not-read}

Ce que l’action laisse non lu est purgé après la réponse, afin que la requête suivante de la connexion puisse être
analysée. La purge lit jusqu’à `max_content`, dans les limites de `drain_timeout` (5 secondes).

Un client peut envoyer `Expect: 100-continue` et attendre avant d’envoyer le contenu. Le serveur répond
`100 Continue` quand l’action lit pour la première fois. Si l’action répond sans lire, le contenu n’a jamais été
demandé. Le serveur ferme alors la connexion après sa réponse, et le client doit en ouvrir une nouvelle.

## Diffuser une réponse {#stream-a-response}

Donnez une fonction à `content`. Elle reçoit deux fonctions, `write` et `flush` :

- chaque `write(data)` envoie un fragment ;
- `flush()` pousse aussitôt vers le client ce qui a été écrit.

<!-- example: packages/http/examples/hecate.http.Response.stream.lua -->
```lua
-- Streaming a response. The content is a function: each `write` is sent as
-- it is called and `flush` pushes it to the client at once. The client
-- reads it chunk by chunk.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function action()
  return http.Response(200, {
    fields = http.Fields({ ["Content-Type"] = "text/plain" }),
    content = function(write, flush)
      for i = 1, 3 do
        write(("line %d\n"):format(i))
        flush()
        reactor.sleep(0.01)
      end
    end,
  })
end

reactor.run(function()
  local server = http.Server(action, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local client <close> = http.Client()
  local response <close> = client:get("http://127.0.0.1:" .. listener:local_address().port .. "/")
  print(response.fields:get("Transfer-Encoding"))
  -- Prints: chunked
  local stream, text = response:stream_content(), {}
  while true do
    local chunk = stream:read()
    if chunk == nil then break end
    text[#text + 1] = chunk:gsub("\n", "|")
  end
  print(table.concat(text))
  -- Prints: line 1|line 2|line 3|
  server:shutdown()
  reactor.join(serving)
end)
```

Le cadrage du contenu dépend de ce que vous avez déclaré :

| Vous avez déclaré | Le serveur envoie |
|---|---|
| pas de `Content-Length` | le contenu avec le codage de transfert par fragments |
| un champ `Content-Length` | les octets bruts ; vous devez en écrire exactement ce nombre |
| rien, à un client HTTP/1.0 | le contenu, qui se termine à la fermeture de la connexion |

### Un lecteur lent {#a-slow-reader}

La fonction s’exécute dans la [portée](../reference/glossary.md#concurrency) (*scope*) de la requête. L’appel
`write` se suspend tant que le client est lent.

`write_timeout` (60 secondes) borne une écriture. Il ferme la connexion d’un lecteur qui ne lit jamais, et l’action
qui écrit reçoit alors une `DeadlineExceededError`.

> [!WARNING] Un client déconnecté n’est pas encore détecté
> Tant que votre action s’exécute, rien ne lit la connexion. Un client parti n’est remarqué qu’à l’écriture
> suivante, qui échoue. Un long calcul continue de s’exécuter jusque-là (OQ-70).

## Voir aussi {#see-also}

- [Traiter les formulaires et le multipart](handle-forms-and-multipart.md)
- [Définir les limites, les délais et TLS du serveur HTTP](http-limits-timeouts-and-tls.md)
- [Le modèle HTTP](../explanation/http-model.md)
