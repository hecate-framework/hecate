---
description: Exécuter des programmes jusqu’à leur terme ou les laisser tourner avec hecate.reactor, dialoguer avec un enfant par un tube de messages et lui passer une connexion ouverte.
hecate: "0.x"
lua: "5.5"
order: 5
source_revision: f1f3b5e
---

# Lancer des processus enfants et se passer des connexions

Ce guide montre comment lancer un autre programme depuis un processus hecate, comment lui parler,
et comment lui donner une connexion TCP ouverte. Ce sont les primitives sur lesquelles le service
multiprocessus est construit ; lisez [Service multiprocessus](../explanation/multi-process-serving.md)
pour la conception. Il est écrit pour hecate 0.x et Lua 5.5.

Dans hecate, *spawn* ([lancer](../reference/glossary.md#concurrency)) signifie démarrer un
processus du système d’exploitation. Démarrer une [coroutine](../reference/glossary.md#concurrency)
est un `fork`. La connexion entre un parent et son enfant est un
[tube de messages](../reference/glossary.md#concurrency) (*message pipe*).

## Choisir entre `run_process` et `spawn`

| | `reactor.run_process(program, args)` | `reactor.spawn(program, args, options)` |
|---|---|---|
| À utiliser pour | un programme qui s’exécute jusqu’à son terme | un enfant qui reste en vie |
| Rend la main | quand l’enfant a terminé : `{ code, signal, stdout, stderr }` | tout de suite : un `Process` |
| Sortie | capturée | héritée, ou ignorée |
| Annulation | termine l’enfant | laisse l’enfant en cours d’exécution |
| Tube de messages | non | facultatif |

Ni l’un ni l’autre ne démarre un shell. `args` liste les arguments sans le nom du programme : il
n’y a donc aucun guillemetage à rater.

## Exécuter un programme jusqu’à son terme

`reactor.run_process` suspend la coroutine jusqu’à la fin de l’enfant. Il renvoie le code de
sortie, le signal de terminaison (0 s’il n’y en a pas) et tout ce que l’enfant a écrit sur la
sortie standard et la sortie d’erreur. Si la coroutine est annulée, par exemple par une échéance,
l’enfant est terminé.

<!-- example: packages/reactor/examples/hecate.reactor.run_process.lua -->
```lua
-- Runs a program to completion and captures its output. The program is the Lua interpreter that
-- runs this file (`arg[-1]`), so the example needs nothing installed.
local reactor = require("hecate.reactor")

reactor.run(function()
  local result = reactor.run_process(arg[-1], { "-e", "io.write('hello'); os.exit(3)" })
  print(("%s, exit code %d"):format(result.stdout, result.code))
end)
-- Prints: hello, exit code 3
```

L’exemple lance l’interpréteur Lua qui exécute le fichier, trouvé dans `arg[-1]`. Dans votre
propre code, vous nommez le programme voulu. S’il ne peut pas être démarré, `run_process` lève
`IoError`.

## Laisser un enfant tourner

`reactor.spawn(program, args?, options?)` démarre l’enfant et renvoie tout de suite un `Process`.
Les options sont :

- `env` : variables ajoutées à l’environnement que l’enfant hérite.
- `cwd` : le répertoire de travail de l’enfant.
- `ipc` : `true` ouvre un tube de messages vers l’enfant.
- `stdout` et `stderr` : `"inherit"` (par défaut) ou `"ignore"`.

Le `Process` renvoyé a :

- `pid`, l’identifiant du système d’exploitation ;
- `wait()`, qui suspend jusqu’à la sortie de l’enfant et renvoie `{ code, signal }`. Plusieurs
  coroutines peuvent attendre. Annuler une attente laisse l’enfant en cours d’exécution ;
- `kill(signal?)`, qui envoie un signal, `"sigterm"` par défaut, et ne suspend pas ;
- `is_running()` ;
- `ipc`, le tube de messages, si vous en avez demandé un.

```lua
local worker = reactor.spawn("my-program", { "--port", "8080" }, { stdout = "ignore" })
-- ... later
worker:kill()        -- SIGTERM; "sigkill" cannot be caught
local status = worker:wait()
```

Vous possédez l’enfant. Attendez-le ou tuez-le, et fermez `process.ipc` quand vous avez fini.
`kill` est un signal, pas le mécanisme d’annulation : annuler la coroutine qui attend n’arrête pas
l’enfant. `kill` ne fait rien pour un enfant déjà sorti et considère comme un succès le cas d’un
enfant disparu entre-temps. Un signal invalide lève `IoError`.

Un enfant en cours d’exécution maintient le réacteur en vie : l’attendre sans rien d’autre en
attente n’est donc pas un interblocage. `reactor.run` rend la main quand sa coroutine principale
se termine, qu’un enfant tourne encore ou non. Attendez vos enfants, ou tuez-les, avant la fin de
la coroutine principale.

> [!WARNING] Chemins de recherche relatifs
> Un enfant démarré depuis un autre processus Lua trouve ses modules par `package.path`. Ce chemin
> peut contenir des entrées relatives, qui cessent de fonctionner quand vous fixez `cwd`. Rendez-les
> absolues, ou passez-les par `LUA_PATH_5_5` et `LUA_CPATH_5_5` dans `env`, comme le font les
> exemples.

## Dialoguer avec un enfant par un tube de messages

Démarrez l’enfant avec `ipc = true`. Le parent lit et écrit par `process.ipc`, un `Peer`.
L’enfant atteint son extrémité avec `reactor.ipc.parent()`, qui renvoie `nil` quand le processus
n’a pas été démarré avec un tube de messages. Il renvoie le même pair à chaque appel et ne suspend
pas.

Les deux extrémités utilisent les mêmes méthodes :

- `peer:send(message, stream?)` suspend jusqu’à ce que le message soit remis au système
  d’exploitation.
- `peer:receive()` suspend et renvoie `message, stream?`. Il renvoie `nil` quand l’autre extrémité
  a fermé le tube, ce qui permet à un enfant d’apprendre que son parent a disparu.
- `peer:close()` est idempotent et ne suspend jamais. Un pair est utilisable avec `<close>`.

Un message est une chaîne d’au plus 16 Mio. Passez `{ max_message = n }` à `reactor.Peer` ou à
`reactor.ipc.parent` pour abaisser la limite. Sérialisez vous-même les données structurées, par
exemple en JSON : `reactor` ne dépend d’aucune bibliothèque JSON.

Une seule coroutine peut recevoir à la fois. Un `receive` annulé garde le pair ouvert et ne perd
rien. Un `send` annulé ferme le pair, parce que la quantité envoyée est inconnue.

<!-- example: packages/reactor/examples/hecate.reactor.spawn.lua -->
```lua
-- A long-lived child with a message pipe. The child is a second Lua interpreter that waits for one
-- message, answers it in capitals and exits; the parent sends, receives and waits for the exit.
-- The child needs the same module paths as this process, hence the two environment variables.
local reactor = require("hecate.reactor")

local CHILD = [[
local reactor = require('hecate.reactor')
reactor.run(function()
  local parent = reactor.ipc.parent()
  parent:send(parent:receive():upper())
end)
]]

reactor.run(function()
  local process = reactor.spawn(arg[-1], { "-e", CHILD }, {
    ipc = true,
    env = { LUA_PATH_5_5 = package.path, LUA_CPATH_5_5 = package.cpath },
  })
  local peer <close> = assert(process.ipc)
  peer:send("hello")
  local answer = peer:receive()
  local status = process:wait()
  print(("%s, exit code %d"):format(answer, status.code))
end)
-- Prints: HELLO, exit code 0
```

Les messages que l’enfant a envoyés avant de sortir restent lisibles jusqu’à ce que vous fermiez
`process.ipc`.

Un processus que l’enfant démarre à son tour ne reçoit ni le tube ni la variable d’environnement
qui l’annonce. Seul l’enfant démarré avec `ipc = true` peut parler à son parent.

### Erreurs

Une trame mal formée, ou un flux qui arrive sans son annonce ou contre elle, lève
`TransportError` avec `EPROTO` et ferme le pair. Un tube qui s’arrête au milieu d’une trame lève
`EPIPE`. Un pair fermé lève `EBADF`, ou `ECANCELED` pour une coroutine qui attendait pendant la
fermeture du pair.

Les méthodes de [`Peer`](../reference/reactor/Peer.md) listent chaque erreur.

## Passer une connexion à un enfant

`peer:send(message, stream)` passe un `TcpStream` ouvert avec un message. Le `receive` de l’enfant
renvoie les deux. À partir de là, seul l’enfant possède la connexion : la copie de l’expéditeur
est fermée quand le transfert est terminé.

Seul un `TcpStream` peut être transféré, et il doit être ouvert. C’est le mécanisme par lequel un
primaire passe les connexions acceptées à ses workers.

<!-- example: packages/reactor/examples/hecate.reactor.Peer.send.lua -->
```lua
-- Hands a connection to another process. The parent accepts a TCP connection and passes it to the
-- child with the message "serve"; the child writes on the stream it received, and the connection
-- is closed in the parent by the hand-over. The parent waits for the child's acknowledgement
-- before it goes on, as a sender should (on Windows the receiver's copy of the socket depends
-- on the sender still being there).
local reactor = require("hecate.reactor")

local CHILD = [[
local reactor = require('hecate.reactor')
reactor.run(function()
  local parent = reactor.ipc.parent()
  local message, stream = parent:receive()
  stream:write('handled by the child after ' .. message .. '\n')
  stream:close()
  parent:send('done')
end)
]]

reactor.run(function()
  local listener <close> = reactor.tcp_listen("127.0.0.1", 0)
  local port = listener:local_address().port
  local client = reactor.fork(function()
    local stream <close> = reactor.tcp_connect("127.0.0.1", port)
    return stream:read()
  end)
  local process = reactor.spawn(arg[-1], { "-e", CHILD }, {
    ipc = true,
    env = { LUA_PATH_5_5 = package.path, LUA_CPATH_5_5 = package.cpath },
  })
  local peer <close> = assert(process.ipc)
  peer:send("serve", listener:accept()) -- the stream now belongs to the child
  peer:receive() -- the child's acknowledgement
  process:wait()
  print((reactor.join(client):gsub("\n$", "")))
end)
-- Prints: handled by the child after serve
```

Le flux est fermé chez l’expéditeur une fois transféré : l’utiliser ensuite lève `TransportError`
avec `EBADF`.

> [!WARNING] Windows
> Le système d’exploitation duplique le socket pour le destinataire, et le doublon n’est valide que
> tant que le socket de l’expéditeur est ouvert. L’expéditeur le ferme dès que `send` rend la main,
> ce qui peut arriver avant que le destinataire n’appelle `receive`. Faites accuser réception par le
> destinataire avec un message, et ne laissez pas l’expéditeur sortir avant l’arrivée de l’accusé.

## Partager un port entre processus

Plusieurs processus peuvent écouter sur un même port avec l’option `reuseport` de
`reactor.tcp_listen` et de `net.listen`, et le noyau équilibre les connexions. Il faut un luv qui
l’expose pour TCP, ce que luv 1.53 ne fait pas (OQ-43) : l’appel lève `TransportError` avec
`ENOTSUP`. Testez d’abord, et repliez-vous sur un processus unique qui accepte et transfère chaque
connexion, comme ci-dessus.

```lua
if reactor.supports_reuseport() then
  listener = reactor.tcp_listen("0.0.0.0", 8080, { reuseport = true }) -- every worker does this
else
  -- the primary accepts and passes each connection to a worker with peer:send(message, stream)
end
```

Là où il est pris en charge, il ne dit rien de l’équilibrage : macOS accepte l’indicateur et
n’équilibre pas. La supervision (disponibilité, redémarrages, arrêt) est à écrire vous-même pour
l’instant. La conception qui la fournira est dans
[Service multiprocessus](../explanation/multi-process-serving.md).

## Différences entre plateformes

- **Windows :** `kill` ne prend en charge que `SIGTERM`, `SIGKILL`, `SIGINT` et `0`. Tout autre
  signal échoue avec `ENOSYS`, et les trois premiers terminent le processus immédiatement, sans
  possibilité de nettoyage.
- **Windows :** un enfant terminé par `kill` rapporte `code` 1 et `signal` 0. Détectez-y un
  plantage ou un `kill` par `code`. `signal` n’a de sens que sous Unix.
- **Windows :** un programme est cherché d’abord dans le répertoire de travail, puis dans `PATH`.
  Un `program` relatif dépend donc de `cwd`.
- **Windows :** un script `.cmd` ou `.bat` ne peut pas être démarré directement, et n’est pas
  trouvé sans son extension. Lancez plutôt `cmd.exe` avec `/c` et le script.
- **Windows :** `"inherit"` exige une sortie standard et une sortie d’erreur valides dans votre
  processus. Un service qui n’en a pas doit passer `"ignore"`.
- **Windows :** les noms de variables d’environnement ne distinguent pas les majuscules des
  minuscules dans `env`.

## Voir aussi

- [Service multiprocessus](../explanation/multi-process-serving.md)
- Référence : [`reactor.spawn`](../reference/reactor/functions/spawn.md),
  [`reactor.run_process`](../reference/reactor/functions/run_process.md),
  [`Process`](../reference/reactor/Process.md), [`Peer`](../reference/reactor/Peer.md),
  [`reactor.ipc`](../reference/reactor/ipc.md)
