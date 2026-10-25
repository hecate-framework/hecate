---
description: Borner les connexions, lectures, écritures et acceptations avec reactor.deadline, et savoir ce que laisse chaque opération annulée.
hecate: "0.x"
lua: "5.5"
order: 3
source_revision: f1f3b5e
---

# Échéances et annulation sur les flux

Ce guide montre comment borner une opération réseau dans le temps, et dans quel état se trouve un
flux après l’annulation d’une opération. Il est écrit pour hecate 0.x et Lua 5.5.

Aucune opération de `hecate.net` ne prend d’argument de délai. Vous bornez n’importe laquelle en
l’enveloppant dans `reactor.deadline(seconds, fn, ...)`. Elle exécute `fn` et, quand
l’[échéance](../reference/glossary.md#concurrency) (*deadline*) est passée, elle
[annule](../reference/glossary.md#concurrency) `fn` et lève `DeadlineExceededError`.

Une annulation venue d’ailleurs, par exemple d’un `reactor.scope` englobant, lève plutôt
`CancellationError`. Les deux sont des classes sœurs sous `Error` : `DeadlineExceededError`
n’est pas une `CancellationError`. L’état dans lequel un flux est laissé est le même pour les
deux.

## Borner une connexion

`reactor.deadline` borne aussi la résolution de noms, parce que `net.connect` résout dans
l’appel.

```lua
local stream <close> = reactor.deadline(5, net.connect, "example.org", 80)
```

Une annulation arrête `connect` immédiatement. Il n’essaie pas l’adresse suivante. La connexion
à moitié ouverte est fermée : rien ne fuit.

`connect_tls` a deux bornes. Le `reactor.deadline` que vous placez autour couvre la résolution et
la connexion TCP. L’option `handshake_deadline` (10 secondes par défaut) couvre uniquement la
poignée de main TLS :

```lua
local stream <close> = reactor.deadline(5, net.connect_tls, host, 443, { handshake_deadline = 5 })
```

## Borner une lecture

Une lecture annulée ne perd rien. Le flux et le lecteur restent utilisables, et les octets déjà
arrivés restent dans le lecteur. Vous pouvez lire de nouveau plus tard.

<!-- example: packages/net/examples/hecate.net.TcpStream.read.lua -->
```lua
-- A deadline around a read. The server stays silent, so the read is cancelled
-- when the deadline passes. Nothing is lost: the stream and the reader are
-- intact, and the next read gets the answer when it comes. (A write cancelled
-- by a deadline would have closed the stream.)
local core = require("hecate.core")
local reactor = require("hecate.reactor")
local net = require("hecate.net")

reactor.run(function()
  local listener <close> = net.listen("127.0.0.1", 0)
  local release = reactor.Channel()
  reactor.fork(function()
    local peer <close> = listener:accept()
    release:receive() -- stay silent until told to answer
    peer:write("late\n")
  end)
  local client <close> = net.connect("127.0.0.1", listener:local_address().port)
  local reader = client:reader()
  local ok, err = pcall(reactor.deadline, 0.05, function() return reader:read_line() end)
  local late = not ok and core.is_instance_of(err, core.DeadlineExceededError)
  release:send(true)
  print(("deadline exceeded: %s; then read: %s"):format(tostring(late), reader:read_line()))
end)
-- Prints: deadline exceeded: true; then read: late
```

C’est l’idiome du délai d’inactivité : exécutez la lecture dans une échéance et, sur
`DeadlineExceededError`, décidez d’attendre encore ou de fermer le flux.

## Borner une acceptation

```lua
local ok, stream = pcall(reactor.deadline, 30, function() return listener:accept() end)
```

Un `accept` annulé garde l’écouteur ouvert et les connexions déjà en file d’attente. Il en va de
même pour un écouteur de tube. C’est ainsi qu’un serveur arrête sa boucle d’acceptation : il
annule la coroutine qui l’exécute, puis ferme l’écouteur.

## Ce que laisse une opération annulée

Certaines opérations ne peuvent plus être retirées une fois commencées : le système d’exploitation
a pris les octets, et personne ne sait combien ont été envoyés. Elles ferment l’objet plutôt que
de le laisser dans un état inconnu.

| Opération | Après une annulation |
|---|---|
| `read`, `read_line`, `read_until`, `read_exact`, `read_some` | Le flux et le lecteur sont intacts. Rien n’est perdu. |
| `TcpListener:accept`, `PipeListener:accept` | L’écouteur et ses connexions en file sont conservés. |
| `UdpSocket:receive_from` | Le socket est intact. Aucun datagramme n’est perdu. |
| `write` | Le flux est fermé. |
| `shutdown` | Le flux est fermé, sauf si l’opération était terminée. |
| `net.connect`, `net.connect_pipe` | La connexion à moitié ouverte est fermée. Aucune autre adresse n’est essayée. |
| `UdpSocket:send_to` | Le socket est fermé. |
| `writer:flush`, et un `writer:write` qui vide le tampon | L’écrivain est empoisonné et le flux est fermé. |
| Poignée de main TLS qui dépasse `handshake_deadline` | Le flux est fermé. |

## Connaître l’écrivain empoisonné

Un `BufferedWriter` dont le vidage a échoué, ou dont le vidage a été annulé, ne peut pas dire
quelle part de son tampon est partie. Envoyer le reste serait une erreur. L’écrivain est donc
*empoisonné* : chaque appel suivant lève une `NetworkError` dont la `cause` est l’échec d’origine.

```lua
local ok, err = pcall(reactor.deadline, 2, function() writer:flush() end)
if not ok then
  -- The stream is closed and the writer is poisoned: open a new connection.
end
```

Lire sur le même flux n’est pas non plus une option, puisque l’écriture annulée l’a fermé.
Considérez une écriture annulée comme la fin de la connexion.

## Ne comptez pas sur `close` pour attendre

`close` ne suspend jamais : il peut donc s’exécuter dans un bloc `<close>` pendant que la
coroutine est annulée. Il n’attend pas les données en tampon. Pour terminer proprement une
conversation, appelez `flush` sur l’écrivain puis `shutdown` avant la fin du bloc. Voir
[Le modèle de transport](../explanation/transport-model.md).

## Voir aussi

- [Se connecter et servir en TCP](connect-and-serve-over-tcp.md)
- [`reactor.deadline`](../reference/reactor/functions/deadline.md),
  [`BufferedWriter`](../reference/net/BufferedWriter.md)
