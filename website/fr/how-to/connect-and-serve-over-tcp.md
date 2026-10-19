---
description: Se connecter à un serveur TCP, accepter des connexions, lire et écrire des lignes, fermer une seule direction d’une connexion et résoudre des noms d’hôte avec hecate.net.
hecate: "0.x"
lua: "5.5"
order: 1
source_revision: f1f3b5e
---

# Se connecter et servir en TCP

Ce guide montre comment ouvrir une connexion TCP, comment accepter des connexions dans un
serveur, et comment les lire, les écrire et les fermer. Il est écrit pour hecate 0.x et Lua 5.5.

Chaque appel qui attend le réseau *suspend* la [coroutine](../reference/glossary.md#concurrency)
en cours et laisse les autres s’exécuter. Appelez-les depuis une coroutine gérée par le
[réacteur](../reference/glossary.md#concurrency) (*reactor*), par exemple dans `reactor.run`. En
dehors, ils lèvent `NonYieldableContextError`. Pour le modèle sous-jacent, lisez
[Le modèle de transport](../explanation/transport-model.md).

## Se connecter

`net.connect(host, port, options?)` renvoie un `TcpStream`. L’hôte peut être un nom ou une
adresse numérique. Un nom est d’abord résolu, puis chaque adresse est essayée dans l’ordre donné
par le résolveur jusqu’à ce qu’une connexion aboutisse.

L’exemple ci-dessous démarre un écouteur sur un port libre et s’y connecte. Le client envoie une
ligne et en lit une en retour.

<!-- example: packages/net/examples/hecate.net.connect.lua -->
```lua
-- An echo exchange over the loopback interface: a listener on a free port, a client that
-- connects to it, one line each way.
local reactor = require("hecate.reactor")
local net = require("hecate.net")

reactor.run(function()
  local listener <close> = net.listen("127.0.0.1", 0)
  reactor.fork(function()
    local peer <close> = listener:accept()
    local reader, writer = peer:reader(), peer:writer()
    writer:write(reader:read_line() .. "!\n")
    writer:flush()
  end)
  local client <close> = net.connect("127.0.0.1", listener:local_address().port)
  local reader, writer = client:reader(), client:writer()
  writer:write("hello\n")
  writer:flush()
  print(reader:read_line())
end)
-- Prints: hello!
```

Les options sont `nodelay` (`true` par défaut), `keepalive` (`false` par défaut),
`keepalive_delay` et `family` (`"inet"` ou `"inet6"`). Une option inconnue lève `ArgumentError`
avant toute résolution.

Quand aucune adresse n’aboutit, `connect` lève une `reactor.TransportError`. Son message nomme
l’hôte et les adresses essayées. `context.errno` est le nom libuv du dernier échec, par exemple
`ECONNREFUSED`, et `context.attempts` liste chaque tentative. Voir
[`net.connect`](../reference/net/functions/connect.md).

## Lire et écrire

Un [flux](../reference/glossary.md#concurrency) (*stream*) lit et écrit des octets. En pratique,
on l’enveloppe dans un lecteur tamponné et un écrivain tamponné :

```lua
local reader, writer = stream:reader(), stream:writer()
```

- `reader:read_line()` renvoie une ligne sans sa fin de ligne. Il renvoie `nil` quand le flux
  s’est terminé proprement avant le premier octet d’une nouvelle ligne.
- `reader:read_until(delimiter)` renvoie les octets qui précèdent un délimiteur.
- `reader:read_exact(count, limit)` renvoie exactement `count` octets, ou lève
  `EndOfStreamError` si le flux se termine avant. Les octets reçus restent dans le lecteur
  (`context.buffered`). Passez `limit` quand `count` vient du pair, afin qu’un pair hostile ne
  puisse pas vous faire mettre en tampon sans borne.
- `writer:write(data)` ajoute à un tampon. Rien ne quitte forcément le processus avant que
  `writer:flush()` ne rende la main.

Les lignes et les enregistrements sont limités à 65536 octets par défaut. Une ligne plus longue
lève `ProtocolError`. Passez `{ limit = n }` à `stream:reader()` pour changer cette limite.

::: tip Un lecteur par flux
`stream:reader()` crée un nouveau lecteur à chaque appel. Deux lecteurs sur un même flux se
partageraient ses octets. Créez un seul lecteur par flux et conservez-le.
:::

Vous pouvez aussi appeler directement `stream:read(max)` et `stream:write(data)`. `write`
accepte la totalité de `data` ou lève une erreur. Il ne renvoie jamais un compte partiel.

## Fermer avec `<close>`

Les flux, les écouteurs, les lecteurs et les écrivains implémentent le protocole `<close>` de
Lua 5.5. Déclarez-les avec `local stream <close> = ...` et ils sont fermés à la fin du bloc, même
en cas d’erreur ou d’annulation.

`close` est idempotent et ne suspend jamais. Fermer un lecteur ou un écrivain ne ferme pas le
flux qu’il enveloppe. Fermer un écrivain jette ce qu’il a encore en tampon : appelez donc
`flush` d’abord.

Après `close`, tout usage lève `reactor.TransportError` avec `context.errno` valant `EBADF`.

## Servir

`net.listen(host, port, options?)` lie une adresse et renvoie un `TcpListener`. Le port `0`
choisit un port libre ; `listener:local_address().port` vous dit lequel. Les options sont celles
de `connect`, plus `backlog` (128 par défaut) et `reuseport`.

::: warning `reuseport` n’est pas encore utilisable
`reuseport = true` permet à plusieurs processus d’écouter sur un même port. Aujourd’hui, il lève
`TransportError` avec `ENOTSUP`, parce que luv 1.53 ne l’expose pas pour TCP (OQ-43). Testez
d’abord `reactor.supports_reuseport()`. Voir
[Service multiprocessus](../explanation/multi-process-serving.md#reuseport-does-not-work-yet).
:::

::: warning Nommez votre adresse
`net.listen("localhost", port)` ne lie que la première adresse listée par le résolveur, qui peut
être `127.0.0.1` ou `::1`. Passez une adresse numérique, ou `family`, quand l’adresse compte.
:::

`listener:accept()` suspend jusqu’à ce qu’un client se connecte et renvoie un `TcpStream`. Un
serveur boucle sur `accept` et démarre une coroutine par connexion avec `fork`, pour qu’un client
lent ne retarde jamais les autres.

<!-- example: packages/net/examples/hecate.net.listen.lua -->
```lua
-- An accept loop that forks one coroutine per connection, so that a slow client never delays the
-- others. Two clients are served at the same time; the loop is cancelled when they are done.
local reactor = require("hecate.reactor")
local net = require("hecate.net")

local function serve(connection)
  local peer <close> = connection
  local reader, writer = peer:reader(), peer:writer()
  while true do
    local line = reader:read_line()
    if line == nil then return end -- the client closed its end
    writer:write(line:upper() .. "\n")
    writer:flush()
  end
end

reactor.run(function()
  local listener <close> = net.listen("127.0.0.1", 0)
  local port = listener:local_address().port
  local acceptor = reactor.fork(function()
    while true do
      reactor.fork(serve, listener:accept())
    end
  end)
  local function ask(word)
    local client <close> = net.connect("127.0.0.1", port)
    local reader, writer = client:reader(), client:writer()
    writer:write(word .. "\n")
    writer:flush()
    return reader:read_line()
  end
  local first, second = reactor.join(reactor.fork(ask, "alpha"), reactor.fork(ask, "beta"))
  print(first .. " " .. second)
  acceptor:cancel()
end)
-- Prints: ALPHA BETA
```

Annuler un `accept` conserve l’écouteur et les connexions déjà en file d’attente. C’est ainsi que
l’exemple arrête sa boucle : il annule la future de la boucle d’acceptation.

## Fermer une seule direction d’une connexion

Un client qui a envoyé toute sa requête peut le signaler avec `stream:shutdown()`. Le pair lit
alors jusqu’à la fin du flux, tandis que le client reste capable de lire la réponse. C’est une
[fermeture partielle](../reference/glossary.md#concurrency) (*half-close*). `shutdown` suspend.
Après lui, le flux reste lisible.

<!-- example: packages/net/examples/hecate.net.TcpStream.shutdown.lua -->
```lua
-- A half-close. The client sends its request, then calls `shutdown` to say that nothing more
-- follows; it can still read. The server reads until the end of the stream, then answers.
local reactor = require("hecate.reactor")
local net = require("hecate.net")

reactor.run(function()
  local listener <close> = net.listen("127.0.0.1", 0)
  reactor.fork(function()
    local peer <close> = listener:accept()
    local reader, writer = peer:reader(), peer:writer()
    local size = 0
    while true do
      local chunk = reader:read_some(4096)
      if chunk == nil then break end -- the client's half-close
      size = size + #chunk
    end
    writer:write(("received %d bytes\n"):format(size))
    writer:flush()
  end)
  local client <close> = net.connect("127.0.0.1", listener:local_address().port)
  client:write(("x"):rep(1000))
  client:shutdown() -- no more data from this side; the stream stays readable
  print(client:reader():read_line())
end)
-- Prints: received 1000 bytes
```

## Résoudre un nom

`net.resolve(host, options?)` renvoie les adresses numériques d’un hôte, dans l’ordre du
résolveur. Utilisez `family` pour ne garder que l’IPv4 ou que l’IPv6.

```lua
local addresses = net.resolve("localhost", { family = "inet" })
print(addresses[1].ip) --> 127.0.0.1
```

La résolution de noms s’exécute sur le pool de threads de libuv, qui compte quatre threads par
défaut. De nombreuses résolutions lentes peuvent s’empiler les unes derrière les autres, et il
n’y a pas de cache.

## Étapes suivantes

- [Échéances et annulation sur les flux](deadlines-and-cancellation.md)
- [Client et serveur TLS](tls-client-and-server.md)
- [UDP, sockets Unix, tubes nommés et DNS](udp-pipes-and-dns.md)
- Référence : [`hecate.net`](../reference/net/index.md), [`TcpStream`](../reference/net/TcpStream.md),
  [`TcpListener`](../reference/net/TcpListener.md)
