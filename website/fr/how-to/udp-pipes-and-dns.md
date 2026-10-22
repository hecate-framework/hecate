---
description: Échanger des datagrammes UDP, écouter sur des sockets Unix et des tubes nommés Windows, et résoudre des noms d’hôte avec hecate.net.
hecate: "0.x"
lua: "5.5"
order: 4
source_revision: cba7be6
---

# UDP, sockets Unix, tubes nommés et DNS

Ce guide couvre les transports de `hecate.net` autres que TCP : datagrammes, sockets locaux et
résolution de noms. Il est écrit pour hecate 0.x et Lua 5.5. Tous les appels suspendent la
[coroutine](../reference/glossary.md#concurrency) en cours : exécutez-les dans `reactor.run`.

## Échanger des datagrammes

`net.bind_udp(host, port, options?)` lie un `UdpSocket` à la première adresse que `host` résout.
Le port `0` choisit un port libre. La seule option est `family`.

Chaque `send_to` envoie un datagramme, et chaque `receive_from` renvoie un datagramme avec
l’adresse de son expéditeur, sous la forme `{ ip, port, family }`. La charge utile peut être
vide. Un datagramme n’est jamais coupé ni fusionné, contrairement aux octets d’un flux.

<!-- example: packages/net/examples/hecate.net.bind_udp.lua -->
```lua
-- A datagram exchange over the loopback interface: two sockets on free ports,
-- one datagram each way. `send_to` takes a numeric address (resolve a name
-- first with `net.resolve`), and each `receive_from` returns exactly one
-- datagram with the sender's address.
local reactor = require("hecate.reactor")
local net = require("hecate.net")

reactor.run(function()
  local server <close> = net.bind_udp("127.0.0.1", 0)
  local client <close> = net.bind_udp("127.0.0.1", 0)
  reactor.fork(function()
    local payload, from = server:receive_from()
    server:send_to(from.ip, from.port, payload:upper())
  end)
  client:send_to("127.0.0.1", server:local_address().port, "ping")
  local reply = client:receive_from()
  print(reply)
end)
-- Prints: PING
```

À savoir :

- `send_to(host, port, data)` place la destination en premier, comme `net.connect`.
- Un socket UDP ne sert qu’un `receive_from` à la fois. Un deuxième appel concurrent lève une
  erreur.
- Un `receive_from` annulé ne perd aucun datagramme. Un `send_to` annulé ferme le socket. Voir
  [Échéances et annulation sur les flux](deadlines-and-cancellation.md).
- La troncature et la perte de datagrammes ne sont ni spécifiées ni testées pour l’instant :
  dimensionnez vos datagrammes en dessous de la MTU du chemin et ne supposez pas la livraison.
- `::` est à double pile sur Linux et macOS, et IPv6 seulement sur Windows par défaut. Aucune
  option ne permet de le changer.

## Résoudre un nom avant d’envoyer

`send_to` n’accepte qu’une adresse numérique. Un nom d’hôte lève `ArgumentError`, qui renvoie à
`net.resolve`. Un datagramme n’a pas de connexion : il n’y a donc pas de seconde adresse à essayer.

`net.resolve(host, options?)` renvoie les adresses numériques dans l’ordre du résolveur, sous la
forme d’une liste de `{ ip, family }`. `family` (`"inet"` ou `"inet6"`) n’en garde qu’un type.

<!-- example: packages/net/examples/hecate.net.resolve.lua -->
```lua
-- Name resolution. `resolve` returns the numeric addresses of a host in the
-- resolver's order; `family` keeps one kind. `UdpSocket:send_to` takes a
-- numeric address only, so a datagram to a name goes through `resolve` first.
local reactor = require("hecate.reactor")
local net = require("hecate.net")

reactor.run(function()
  local addresses = net.resolve("localhost", { family = "inet" })
  local socket <close> = net.bind_udp("127.0.0.1", 0)
  socket:send_to(addresses[1].ip, socket:local_address().port, "hello")
  local payload = socket:receive_from()
  print(addresses[1].ip .. " " .. payload)
end)
-- Prints: 127.0.0.1 hello
```

Quand un nom ne se résout pas, `resolve` lève une `reactor.TransportError`. Son message et
`context.host` portent le nom, et `context.errno` est le code du résolveur, par exemple
`EAI_NONAME`. Une résolution annulée rend la main immédiatement et son résultat tardif est jeté.

La résolution s’exécute sur le pool de threads de libuv (quatre threads par défaut) et n’est pas
mise en cache. Bornez-la avec `reactor.deadline` comme n’importe quel autre appel.

## Écouter sur un socket Unix ou un tube nommé

`net.listen_pipe(path, options?)` écoute sur un socket de domaine Unix. Sous Windows, le même
appel écoute sur un tube nommé, dont le chemin a la forme `\\.\pipe\name`. Les flux sont des
objets `PipeStream` qui ont la même API que `TcpStream` : `reader`, `writer`, `shutdown`,
`close`, etc., plus `path()`.

<!-- example: packages/net/examples/hecate.net.listen_pipe.lua -->
```lua
-- A Unix-domain socket (a named pipe on Windows) in place of TCP: the stream
-- and the buffered API are the same. The path must not exist; `mode` says who
-- may connect (default: the owner).
local reactor = require("hecate.reactor")
local net = require("hecate.net")

local WINDOWS = package.config:sub(1, 1) == "\\"
local name = ("hecate-example-%x-%d"):format(os.time(), math.random(0, 1 << 30))
local path = WINDOWS and ("\\\\.\\pipe\\" .. name) or ((os.getenv("TMPDIR") or "/tmp") .. "/" .. name .. ".sock")

reactor.run(function()
  local listener <close> = net.listen_pipe(path, { mode = "owner" })
  reactor.fork(function()
    local peer <close> = listener:accept()
    local reader, writer = peer:reader(), peer:writer()
    writer:write(reader:read_line():upper() .. "\n")
    writer:flush()
  end)
  local client <close> = net.connect_pipe(path)
  local reader, writer = client:reader(), client:writer()
  writer:write("hello\n")
  writer:flush()
  print(reader:read_line())
end)
-- Prints: HELLO
```

`listen_pipe` ne suspend pas. `net.connect_pipe(path)` suspend et renvoie le `PipeStream`.

### Options et limites

- `backlog` est un entier positif, 128 par défaut. Il est ignoré sous Windows.
- `mode` dit qui peut se connecter : `"owner"` (par défaut), `"readable"`, `"writable"` ou
  `"readwrite"`. Il est sans effet sous Windows. Sous Unix, le socket est réservé à son
  propriétaire juste après le `bind`. Pendant un très court instant, il a les permissions de
  l’umask.
- Le chemin ne doit pas exister. Lier un chemin existant échoue avec `EADDRINUSE`. L’écouteur
  supprime son fichier socket à sa fermeture. Après un plantage, un fichier orphelin reste :
  supprimez-le avant d’écouter de nouveau.
- Un nom de tube Windows fait au plus 256 caractères. Un chemin de socket Unix fait au plus 104
  octets sous macOS et 108 sous Linux, NUL final compris. Un chemin plus long lève
  `ArgumentError`.

### Différences sous Windows

| | Unix | Windows |
|---|---|---|
| Chemin | un chemin de fichier | `\\.\pipe\name` |
| `mode` | appliqué | sans effet |
| `backlog` | appliqué | ignoré |
| Chemin orphelin après un plantage | le fichier reste | le tube disparaît avec le processus |

## Voir aussi

- [Se connecter et servir en TCP](connect-and-serve-over-tcp.md)
- Référence : [`net.bind_udp`](../reference/net/functions/bind_udp.md), [`UdpSocket`](../reference/net/UdpSocket.md),
  [`net.resolve`](../reference/net/functions/resolve.md),
  [`net.listen_pipe`](../reference/net/functions/listen_pipe.md),
  [`net.connect_pipe`](../reference/net/functions/connect_pipe.md)
