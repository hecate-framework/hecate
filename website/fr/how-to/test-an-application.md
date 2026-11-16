---
description: Tester une application avec hecate.test, écrire des cas de test, démarrer l’application avec des fakes, envoyer des requêtes sans socket, voir quelles routes un test n’a jamais atteintes et vérifier des propriétés sur des valeurs générées.
hecate: "0.x"
lua: "5.5"
order: 21
source_revision: aa39cc772601fb1823b18a3fd678e98a08fda700
---

# Tester une application

Ce guide montre comment tester une application avec `hecate.test`. Il est écrit pour hecate 0.x et Lua 5.5, et le
paquet est en **alpha** : les parties listées à la fin ne sont pas encore disponibles.

`hecate.test` exécute chaque test dans un réacteur qui lui est propre, si bien qu’un test peut suspendre, démarrer des
coroutines avec `fork` et attendre comme le code de production. Un test qui laisse des coroutines en cours échoue, et
elles sont annulées : un test ne perturbe donc jamais le suivant.

## Écrire un cas de test

Un cas de test est une classe créée avec `test.Case`. Chaque méthode dont le nom commence par `test_` est un test. Les
hooks `set_up` et `tear_down` s’exécutent autour de chaque test, `set_up_case` et `tear_down_case` autour du cas
entier. Les assertions sont des méthodes du cas : `assert_equal` compare des tables structurellement et liste chaque
différence par son chemin, et `assert_error` vérifie la classe et le code d’une erreur levée.

```lua
local test = require("hecate.test")
local T = test.Case("GreetingTest")

function T:test_greeting_is_polite()
  self:assert_match("^Hello", "Hello, Ada")
end

return require("hecate.core").finalise(T)
```

Un fichier de test se termine par le cas finalisé. `test.discover(directory)` trouve les fichiers `*_test.lua` d’un
répertoire, `test.load(path)` en charge un, et `test.Runner` exécute les cas et envoie des événements à un reporter : le
reporter de console dessine une ligne par suite, et `TapReporter`, `JUnitReporter` et `JsonLinesReporter` écrivent les
formats que leur nom indique. Un résumé d’exécution porte `exit_code`, qui vaut 0 quand tous les tests ont réussi.

On peut cibler les tests. Les options du runner `filter` (un motif Lua sur le nom complet du test), `cases` (noms de
cas), `tags` et `exclude_tags` sélectionnent des tests, et `test.parse_arguments(args)` transforme les arguments d’une
ligne de commande (`--filter`, `--case`, `--tag`, `--exclude-tag` et des chemins) en ces options. Un cas déclare des
étiquettes avec `tags`, et un test isolé avec `test_tags`.

## Démarrer l’application

`test.boot(options, overrides)` démarre une application `hecate.kernel` et renvoie un client, l’application et une
couverture de routes. Les `options` sont celles de `kernel.Application`. Chaque surcharge remplace un service **après**
que tous les modules ont enregistré les leurs : un fake prend donc la place du vrai service, quel que soit le module qui
l’a enregistré. Une surcharge est `{ key, value }` pour un objet existant, ou `{ key, definition, options }` pour une
classe ou une fabrique. Une clé qui n’est pas enregistrée lève `hecate.container.MissingBindingError`.

Le client envoie des requêtes à l’application sans socket, par le chemin de code du serveur. `get`, `post`, `put`,
`patch`, `delete`, `head` et `request` renvoient la réponse et, quand l’action a levé une erreur, l’échec que le serveur
aurait journalisé. L’option `json` encode une valeur et fixe le type de contenu.

<!-- example: packages/test/examples/hecate.test.boot.lua -->
```lua
-- Boot an application for a test: replace a service by a fake, send requests
-- without a socket, and see which routes the test never reached.
local reactor = require("hecate.reactor")
local kernel = require("hecate.kernel")
local test = require("hecate.test")

local routes = kernel.routes("greetings")
routes:get("/greeting", {
  name = "show_greeting",
  action = function(request)
    return { text = request.services:resolve("greeter") }
  end,
})
routes:delete("/greeting", {
  name = "delete_greeting",
  action = function() return { deleted = true } end,
})

local options = {
  routes = { routes },
  modules = { {
    name = "greetings",
    services = function(c)
      c:bind("greeter", function() return "hello" end,
        { lifetime = "singleton" })
    end,
  } },
}

reactor.run(function()
  -- The override is applied after every module has bound its services.
  local client, _, coverage = test.boot(options, {
    { key = "greeter", value = "fake" },
  })
  local response = client:get("/greeting")
  print(response.status, response:read_content())
  -- Prints: 200	{"text":"fake"}
  print(client:get("/nowhere").status)
  -- Prints: 404
  print(coverage:report())
  -- Prints: 1 of 2 routes exercised
  -- not exercised: delete_greeting
end)
```

Les réponses sont validées contre les schémas que déclarent les routes : une réponse qui rompt le contrat répond `500`
dans le test. Passez `validate_responses = false` dans les options pour le désactiver. La couverture liste les routes
nommées qui ont servi une requête, `exercised()` et `missed()`, et `report()` affiche les deux. Un `404`, un `405` et
une réponse automatique à `OPTIONS` n’exercent aucune route.

## Vérifier des propriétés

Un test par l’exemple vérifie les valeurs auxquelles vous avez pensé. Une propriété se vérifie sur des valeurs
générées à partir d’un schéma, et couvre donc celles auxquelles vous n’avez pas pensé. `test.generate(schema, seed)`
renvoie une valeur valide, et `test.Generator` donne une suite reproductible avec `next()`. La même graine (*seed*)
donne les mêmes valeurs sur toutes les plateformes. `check_property` exécute une propriété, qui échoue en renvoyant
`false` ou en levant une erreur, et réduit (*shrink*) le premier contre-exemple : les entiers se rapprochent de zéro, les
chaînes et les tableaux raccourcissent, les objets perdent des propriétés, et un candidat n’est gardé que si le schéma
l’accepte encore. `Case:assert_property` fait de même dans un test et nomme la graine et le contre-exemple dans
l’échec.

<!-- example: packages/test/examples/hecate.test.check_property.lua -->
```lua
-- Check a property over values generated from a schema. A failing property
-- is shrunk to a small counterexample that still conforms to the schema.
local schema = require("hecate.schema")
local test = require("hecate.test")

local age = schema.integer({ minimum = 0, maximum = 120 })

-- A property fails by returning false (or by raising).
local ok = test.check_property(age, function(n) return n >= 0 end)
print(ok.ok, ok.runs)
-- Prints: true	100

-- The seed makes the run reproducible; the counterexample is the smallest
-- failing value the shrinking reached.
local result = test.check_property(age, function(n) return n < 18 end,
  { seed = 7 })
print(result.ok, result.counterexample)
-- Prints: false	18

-- Values that break the schema in exactly one place, with the violation.
local value, expected = test.generate_invalid(age, 1)
print(age:validate(value), expected.code)
-- Prints: false	maximum
```

`generate_invalid` va dans l’autre sens. Il casse une valeur valide en un seul endroit et renvoie la violation que la
validation signale, avec son `path` JSON Pointer et son `code` : c’est le moyen de tester qu’une route refuse ce
qu’elle doit refuser.

## Exécuter des fichiers en parallèle

`test.run_parallel(paths, options)` exécute chaque fichier de test dans un processus worker qui lui est propre, avec son
propre réacteur, et renvoie le même résumé que `Runner:run`. Il suspend, donc appelez-le dans `reactor.run`. L’option
`jobs` est le nombre de workers actifs en même temps (2 par défaut), `runner` contient les options du runner que reçoit
chaque worker (`filter`, `cases`, `tags`, `exclude_tags`, `clock`), `reporter` reçoit les événements, et `lua` nomme
l’interpréteur qui exécute un worker (par défaut, celui qui a lancé le script).

Le primaire, le processus qui appelle `run_parallel`, demande d’abord son plan au worker de chaque fichier, de sorte que
`run_started` annonce le total de toute l’exécution. Il exécute ensuite les fichiers `jobs` à la fois. Les événements du
premier fichier non terminé parviennent au reporter au fur et à mesure, ceux des fichiers suivants attendent leur tour :
le flux a donc la forme d’une exécution séquentielle et une console montre la progression pendant que les fichiers
s’exécutent. Un worker qui ne peut pas démarrer, qui meurt ou qui envoie quelque chose d’illisible devient une suite en
erreur ; il n’arrête jamais l’exécution.

```lua
local reactor = require("hecate.reactor")
local test = require("hecate.test")

reactor.run(function()
  local paths = test.discover("tests")
  local summary = test.run_parallel(paths, { jobs = 4 })
  print(summary.exit_code)
end)
```

Deux limites : chaque fichier est chargé deux fois, une fois pour planifier et une fois pour exécuter, et ce qu’un test
écrit sur sa sortie standard est perdu (sa sortie d’erreur parvient à celle du primaire). Les tests qui utilisent un
port fixe ou une base de données partagée ne devraient pas s’exécuter en parallèle tant que la règle qui les concerne
n’est pas écrite.

## Mesurer la couverture de lignes

`test.LineCoverage` enregistre quelles lignes de vos sources s’exécutent. Passez-en une au runner, ou à
`run_parallel`, dont les workers renvoient leurs lignes, puis lisez les chiffres.

```lua
local coverage = test.LineCoverage({ include = "/src/" })
test.Runner({ coverage = coverage }):run(cases)
print(coverage:report().percent)
print(coverage:percent("/src/users/"))
local file = io.open("lcov.info", "w")
file:write(coverage:lcov())
file:close()
```

`include` est un motif Lua (ou un prédicat) comparé au chemin de chaque source, avec des séparateurs `/` ; `exclude`
retire des sources à nouveau. Seules les lignes qui portent du code comptent : les commentaires et les lignes faites de
délimiteurs de bloc ne comptent pas. Une région entre les commentaires `-- coverage: off` et `-- coverage: on` est
exclue : servez-vous-en pour le code qui s’exécute dans un autre état Lua, comme un thread du pool, que le hook de
lignes ne peut pas voir. Le rapport est du LCOV simple, que lisent `genhtml` et la plupart des services de couverture.
L’enregistrement ralentit l’exécution : ne l’activez que pour une exécution de couverture.

## Limites

- Un `pattern` est généré à partir du sous-ensemble que `hecate.schema` accepte, en ASCII uniquement. Un schéma de
  chaîne qui a aussi un `format`, ou dont les `min_length` et `max_length` ne conviennent à aucune chaîne du motif,
  lève `ArgumentError`.
- Les entiers se réduisent vers zéro, un pas à la fois près d’une borne éloignée.
- Pas encore disponible : les fixtures de base de données avec une transaction annulée à chaque test (elles viennent
  avec le paquet `sql`).
- La couverture compte des lignes, pas des branches, et elle ne voit que le code qui s’exécute dans l’état Lua du test.
