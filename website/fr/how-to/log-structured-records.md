---
description: Journaliser des enregistrements structurés avec hecate.log, attacher un contexte à un journaliseur, masquer les secrets et limiter le volume.
hecate: "0.x"
lua: "5.5"
order: 7
source_revision: ac925c3
---

# Journaliser des enregistrements structurés

Ce guide montre comment écrire des enregistrements structurés avec `hecate.log`. Il est écrit pour
hecate 0.x et Lua 5.5.

## Créer un journaliseur et écrire des enregistrements

Un `Logger` a un niveau (`informational` par défaut), des puits (*sinks*) et un contexte
facultatif. Un appel sous le niveau ne construit aucun enregistrement. Un puits qui lève une erreur
ne fait jamais échouer l’appelant.

<!-- example: packages/log/examples/hecate.log.Logger.lua -->
```lua
-- A logger drops what is below its level, adds its context to every record and hands the rest to
-- its sinks.
local log = require("hecate.log")

local sink = log.MemorySink()
local logger = log.Logger({ level = "informational", sinks = { sink } }):with_context({ request = "r-1" })

logger:debug("not recorded")
logger:warning("slow query", { millis = 120 })
local record = sink:records()[1]
print(("%d %s %s %s"):format(#sink:records(), record.message, record.context.request, record.fields.millis))
-- Prints: 1 slow query r-1 120
```

Les sévérités sont les huit de la RFC 5424, de `emergency` à `debug`. `with_context(fields)`
renvoie un journaliseur enfant dont le contexte est figé. Pour étiqueter chaque enregistrement
d’une requête, y compris ceux des calculs qu’elle démarre avec `fork` ou détache, enveloppez le
travail dans `log.bind({ request_id = "r-1" }, fn)` : un journaliseur sans `context_provider`
ajoute les champs liés à ses enregistrements.

## Choisir un puits

- `ConsoleSink({ output = ... })` : une ligne lisible par enregistrement, caractères de contrôle
  échappés.
- `JsonLinesSink({ output = ... })` : un objet JSON par ligne.
- `FileSink({ path = ... })` : ajoute des lignes JSON à un fichier, de façon synchrone ; appelez
  `close()` à la fin.
- `MemorySink({ capacity = ... })` : conserve les enregistrements, pour les tests.

Un puits est un objet doté d’une méthode `write(record)` qui ne suspend pas. Un journaliseur
transmet chaque enregistrement à tous ses puits ; `logger:failures()` compte les puits qui ont
levé une erreur.

## Masquer les secrets

Enveloppez une valeur dans `log.Secret` : aucun puits ne la rend (elle apparaît comme
`[redacted]`), à n’importe quelle profondeur d’un enregistrement. La valeur reste accessible par
`reveal()`. Pour protéger plutôt des champs par leur nom, donnez au journaliseur
`redact = { "password", "token" }` : les valeurs des champs portant ces noms (sans tenir compte de
la casse, à toute profondeur, dans les champs et dans le contexte) sont enveloppées dans un
`Secret` avant qu’un puits ne les voie.

<!-- example: packages/log/examples/hecate.log.Secret.lua -->
```lua
-- A secret is never rendered by a sink, whatever the depth of the field that holds it.
local log = require("hecate.log")

local lines = {}
local logger = log.Logger({ sinks = { log.JsonLinesSink({ output = function(line) lines[#lines + 1] = line end }) } })

logger:error("login failed", { user = "ada", password = log.Secret("hunter2") })
print(("%s %s"):format(lines[1]:find("hunter2", 1, true) == nil, lines[1]:find("[redacted]", 1, true) ~= nil))
-- Prints: true true
```

## Limiter le volume

Enveloppez un puits dans `log.LimitedSink({ sink = ..., sample = 0.1, rate = 100 })` pour ne
garder qu’une fraction des enregistrements et au plus `rate` par seconde (seau à jetons, capacité
`burst`). Les enregistrements au moins aussi urgents que `exempt` (`warning` par défaut) passent
toujours. `dropped()` compte ce qui a été écarté.

## Garder les puits lents hors du chemin de la requête

Enveloppez un puits dans `log.AsyncSink({ sink = ..., capacity = 1024 })`. `write` ne fait que
mettre l’enregistrement en file, donc ne suspend jamais ; une coroutine détachée écrit vers la
cible. Quand la file est pleine, l’enregistrement est abandonné et compté (`dropped()`) : la
contre-pression est une perte, jamais une attente. `flush()` suspend jusqu’à ce que ce qui est en
file ait été écrit, et `close()` vide la file et arrête la coroutine. Appelez `close()` avant la
fin du calcul principal : une coroutine de vidage qui attend encore des enregistrements est un
interblocage pour le réacteur.

<!-- example: packages/log/examples/hecate.log.AsyncSink.lua -->
```lua
-- An asynchronous sink queues records and writes them from a detached coroutine: logging never waits
-- for the target. `close` flushes what is queued and stops the coroutine.
local reactor = require("hecate.reactor")
local log = require("hecate.log")

reactor.run(function()
  local memory = log.MemorySink()
  local async = log.AsyncSink({ sink = memory, capacity = 128 })
  local logger = log.Logger({ sinks = { async } })

  logger:informational("first")
  logger:informational("second")
  local waiting = async:pending()
  async:close()
  print(("%d %d %d"):format(waiting, #memory:records(), async:dropped()))
end)
-- Prints: 2 2 0
```
