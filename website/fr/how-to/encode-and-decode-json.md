---
description: Encoder et décoder du JSON avec hecate.json, distinguer entiers et flottants, écrire null et les tableaux vides, et lire les erreurs de décodage.
hecate: "0.x"
lua: "5.5"
order: 6
source_revision: 791f634
---

# Encoder et décoder du JSON

Ce guide montre comment lire et écrire du texte JSON (RFC 8259) avec `hecate.json`. Il est écrit
pour hecate 0.x et Lua 5.5.

## Décoder un texte

`json.decode(text, options?)` renvoie une valeur Lua. Un littéral entier devient un entier Lua,
tout autre nombre un flottant, et un `[]` ou `{}` vide conserve sa nature grâce à un marqueur : il
se ré-encode donc vers le même texte.

<!-- example: packages/json/examples/hecate.json.decode.lua -->
```lua
-- Decoding returns Lua integers for integer literals and floats otherwise; `[]`
-- and `{}` keep their kind through markers, so an empty array round-trips.
local json = require("hecate.json")

local value = json.decode('{"count":3,"ratio":0.5,"items":[]}')
print(("%s %s %s %s"):format(math.type(value.count), math.type(value.ratio), json.is_array(value.items), json.encode(value.items)))
-- Prints: integer float true []
```

`max_depth` et `max_size` bornent une entrée hostile. Ne les relevez que pour un texte de
confiance.

## Encoder une valeur

`json.encode(value, options?)` écrit un texte compact ; `pretty` et `indent` le mettent en forme.
Un flottant est toujours écrit avec un point ou un exposant, si bien que `2.0` reste un flottant.
Utilisez `json.null` pour un `null` JSON (un `nil` ne se voit pas en fin de table Lua), et
`json.array` ou `json.object` pour marquer une table vide. `canonical = true` ordonne les membres
par unités de code UTF-16 (RFC 8785).

<!-- example: packages/json/examples/hecate.json.encode.lua -->
```lua
-- Encoding keeps the difference between integers and floats, writes `json.null`
-- explicitly, and orders members with `canonical` so that the text is stable.
local json = require("hecate.json")

print(json.encode({ b = 1, a = 2.0, c = json.null }, { canonical = true }))
-- Prints: {"a":2.0,"b":1,"c":null}
```

Pour signer ou calculer une empreinte, `canonical = "rfc8785"` écrit le schéma complet de
canonicalisation JSON (JCS).

## Lire une erreur de décodage

`decode` rejette certains textes que la RFC 8259 permet, parce que les analyseurs ne s’accordent
pas sur eux : noms de membres dupliqués, demi-paires de substitution isolées, marque d’ordre des
octets et nombres hors de l’intervalle des doubles. La `DecodeError` dit pourquoi et où :
`context.reason`, et la position sous la forme `offset`, `line` et `column`. Un nom de membre
dupliqué n’a pas de position : l’analyseur (yyjson) n’en conserve pas.

<!-- example: packages/json/examples/hecate.json.DecodeError.lua -->
```lua
-- A rejected text raises a `DecodeError` whose context names the reason and the
-- position.
local json = require("hecate.json")

local ok, err = pcall(json.decode, "[1, 2")
print(("%s %s %d %d"):format(ok, err.context.reason, err.context.line, err.context.column))
-- Prints: false syntax 1 6
```

Le tableau des raisons et la conduite à tenir pour chacune se trouvent dans le
[README du paquet](https://github.com/hecate-framework/hecate/blob/main/packages/json/README.md).

Référence : [`hecate.json`](../reference/json/index.md), [`DecodeError`](../reference/json/DecodeError.md).
