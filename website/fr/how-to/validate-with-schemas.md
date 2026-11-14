---
description: Déclarer des schémas avec hecate.schema, valider et convertir des valeurs avec des chemins d’erreur JSON Pointer, construire des instances de vos classes et émettre du JSON Schema 2020-12.
hecate: "0.x"
lua: "5.5"
order: 7
source_revision: 73912587a7b3ba66207e40b62b745ba832ae80f8
---

# Valider des valeurs avec des schémas

Ce guide montre comment déclarer un [schéma](../reference/glossary.md#types-and-validation) (*schema*), valider une valeur
contre lui, convertir les textes d’une requête, construire des instances de vos classes et émettre le document JSON
Schema correspondant avec `hecate.schema`. Il est écrit pour hecate 0.x et Lua 5.5. Pour comprendre pourquoi les
schémas fonctionnent ainsi, lisez [Schémas et contrats](../explanation/schemas-and-contracts.md).

## Déclarer et valider

Un schéma est une valeur immuable construite à partir de constructeurs (`string`, `integer`, `object`, `array`,
`optional`, `union`, ...) avec des raffinements comme options. `validate` collecte toutes les
[violations](../reference/glossary.md#types-and-validation) (*violations*) ; le `path` de chacune est un JSON Pointer
de la RFC 6901.

<!-- example: packages/schema/examples/hecate.schema.validate.lua -->
```lua
-- Declare a schema once, then validate a value: every violation is collected,
-- each with the JSON Pointer of the offending value.
local schema = require("hecate.schema")

local user = schema.object({
  name = schema.string({ min_length = 1 }),
  age = schema.integer({ minimum = 0 }),
})

local ok, violations = user:validate({ name = "", age = -1 })
assert(violations)
print(("%s %d %s %s"):format(tostring(ok), #violations, violations[1].path, violations[2].path))
-- Prints: false 2 /age /name
```

Les propriétés non déclarées d’un `object` sont refusées (violation `additional_properties`), sauf si l’option
`additional_properties = true` dit le contraire. Les codes de violation sont stables ; la liste est dans la
[spécification](https://github.com/hecate-framework/hecate/blob/main/docs/architecture/schemas-and-contracts.md#violation-codes).

`check(value)` est la forme qui lève de `validate` : elle renvoie la valeur quand elle est conforme, et lève sinon une
`ValidationError` dont `context.violations` contient la même liste. `coerce` et `build` ne lèvent pas d’erreur : elles
renvoient deux valeurs, `true` et le résultat, ou `false` et la liste des violations.

### Rapporter les violations à un client

Un client a besoin du JSON Pointer de chaque valeur fautive, d’un code stable et d’un message, pas d’une erreur Lua.
`check` lève une `ValidationError` ; transformez `context.violations` en la table simple d’une réponse de détails de
problème (RFC 9457) avec une entrée par violation. Le `message` d’une violation ne contient jamais la valeur envoyée par
le client ; le noyau (*kernel*) ne l’ajoute pourtant que si `errors.expose_details` vaut `true`. Le noyau fait cette
conversion pour vous ; l’exemple montre le `422` qu’il envoie.

<!-- example: packages/schema/examples/hecate.schema.Schema.check.lua -->
```lua
-- Report violations to a client: `check` raises a `ValidationError`, and its
-- violations become the `errors` of a problem details response (RFC 9457).
-- The kernel builds this 422 for you from the inputs of a request.
local core = require("hecate.core")
local schema = require("hecate.schema")

local user = schema.object({
  name = schema.string({ min_length = 1 }),
  age = schema.integer({ minimum = 0 }),
})

local ok, err = pcall(user.check, user, { name = "", age = -1 })
print(ok, core.is_instance_of(err, core.ValidationError))
-- Prints: false	true

-- The 422 of the kernel: one entry per violation, with the JSON Pointer of the
-- value and the stable code (the kernel adds the `source` of an input).
local problem = {
  type = "about:blank",
  title = "Unprocessable Content",
  status = 422,
  detail = "The request content does not conform to the contract.",
  errors = {},
}
for _, violation in ipairs(err.context.violations) do
  local entry = { pointer = violation.path, code = violation.code }
  problem.errors[#problem.errors + 1] = entry
end
for _, entry in ipairs(problem.errors) do
  print(entry.pointer, entry.code)
end
-- Prints: /age	minimum
-- /name	min_length

-- Each violation also has a message, with no client value in it. The kernel
-- adds it to the entries only when `errors.expose_details` is true.
print(err.context.violations[1].message)
-- Prints: the value is less than 0

-- A conforming value is returned as it is.
print(user:check({ name = "Ada", age = 36 }).name)
-- Prints: Ada
```

## Donner son schéma à une classe

Une classe possède le nom de son schéma. Déclarez une fonction de niveau classe `schema()` qui renvoie le schéma, et
utilisez `schema.of(Class)` partout où la classe est une partie d’un autre schéma. Pour rendre la règle vérifiable,
déclarez l’interface `schema.Representable`, qui exige `schema` : `finalise` lève alors une `ConformanceError` pour une
classe qui la déclare sans fonction `schema`. La déclarer est obligatoire : `schema.of` refuse une classe qui ne la
déclare pas, même si elle a `schema()`, avec une `ArgumentError` qui nomme la classe et l’interface. Le refus a lieu à la
déclaration pour une classe déjà finalisée, sinon au premier emploi. L’émission place la définition une seule fois dans le `$defs` racine sous le nom de la classe et utilise un `$ref` à
chaque emploi. Les classes peuvent se référencer mutuellement ou elles-mêmes.

<!-- example: packages/schema/examples/hecate.schema.of.lua -->
```lua
-- A class owns the schema of its instances: the interface
-- `schema.Representable` requires a class-level `schema()`, and
-- `schema.of(Class)` uses the class wherever it is a part of another schema.
local core = require("hecate.core")
local schema = require("hecate.schema")

local Representable = schema.Representable

local Address = core.class("Address", nil, { implements = { Representable } })
function Address.schema()
  return schema.object({ street = schema.string(), city = schema.string() })
end
core.finalise(Address)

local User = core.class("User", nil, { implements = { Representable } })
function User.schema()
  return schema.object({ name = schema.string(), address = schema.of(Address) })
end
core.finalise(User)

-- A class that declares the interface without `schema()` cannot be finalised.
local Incomplete = core.class("Incomplete", nil, { implements = { Representable } })
print((pcall(core.finalise, Incomplete)))
-- Prints: false

-- `schema.of` refuses a class that does not declare the interface, even when
-- it has a `schema` function.
local Plain = core.class("Plain")
function Plain.schema() return schema.object({}) end
core.finalise(Plain)
print((pcall(schema.of, Plain)))
-- Prints: false

local ok, user = schema.of(User):build({ name = "Ada", address = { street = "1 Main St", city = "Paris" } })
print(ok, core.is_instance_of(user, User), core.is_instance_of(user.address, Address))
-- Prints: true	true	true

-- The emission names each class once, in `$defs`, and refers to it.
local document = schema.of(User):to_json_schema()
print(document["$ref"], document["$defs"].User.properties.address["$ref"])
-- Prints: #/$defs/User	#/$defs/Address
```

## Construire des instances

`build(content, { method })` valide un contenu JSON décodé et renvoie `true` et la valeur, ou `false` et les
violations. Une partie déclarée avec `schema.of(Class)` devient une instance de sa classe, dans les propriétés, les
tableaux, les tables associatives et les unions. L’`init` de la classe n’est pas appelé. Un attribut absent, ou un
`null` explicite, vaut `nil` dans l’instance. Quand une classe est une `value_class`, ses instances sont construites
figées.

`method` vaut `"POST"` ou `"PUT"` (strict, par défaut) ou `"PATCH"`. La règle d’un PATCH est dans les sections
suivantes.

### Construire à partir de textes de chemin, de requête et de champs d’en-tête

Les valeurs de requête, de chemin et de champs d’en-tête sont des textes. Passez `coerce = true` pour les convertir avec les
règles de `coerce` et construire les instances en un seul appel. Un texte qui ne peut pas être converti donne la même
violation `coercion`, au même chemin, que `coerce`. Les valeurs par défaut s’appliquent une seule fois, dans la
conversion, et jamais pour un PATCH. `schema.sent` n’enregistre que les attributs fournis par le client. `coerce` doit
être un booléen.

<!-- example: packages/schema/examples/hecate.schema.Schema.build.lua -->
```lua
-- Build an instance of a class from the texts of a query string: convert,
-- validate, apply defaults.
local core = require("hecate.core")
local schema = require("hecate.schema")

local Filter = core.class("Filter", nil, { implements = { schema.Representable } })
function Filter.schema()
  return schema.object({
    status = schema.default(schema.string(), "open"),
    limit = schema.default(schema.integer({ minimum = 1, maximum = 100 }), 20),
    tags = schema.optional(schema.array(schema.string())),
    archived = schema.optional(schema.boolean()),
  })
end
core.finalise(Filter)

local filters = schema.of(Filter)

-- Every value of a query string is a text: `coerce = true` converts it
-- before building.
local _, filter = filters:build({ limit = "5", tags = "a,b", archived = "true" }, { coerce = true })
print(core.is_instance_of(filter, Filter), filter.status, filter.limit, #filter.tags, filter.archived)
-- Prints: true	open	5	2	true
print(schema.sent(filter, "limit"), schema.sent(filter, "status"))
-- Prints: true	false

-- A text that cannot be converted is a violation with the path of the
-- parameter.
local ok, violations = filters:build({ limit = "many" }, { coerce = true })
print(ok, violations[1].path, violations[1].code)
-- Prints: false	/limit	coercion
```

### Remplir les propriétés absentes avec des valeurs par défaut

`schema.default(inner, value)` rend une propriété facultative. `coerce` (textes) et `build` (contenu JSON) donnent à
une propriété absente une copie profonde neuve de la valeur par défaut, de sorte qu’aucune table n’est partagée entre
des requêtes et que le contenu que vous avez passé n’est jamais modifié. La valeur par défaut doit se conformer à
`inner`, ce qui est vérifié à la déclaration. Un `null` explicite reste `null` et ne prend jamais la valeur par
défaut. `validate` ne fournit jamais de valeur.

<!-- example: packages/schema/examples/hecate.schema.default.lua -->
```lua
-- A default makes a property optional. A POST or PUT receives a fresh copy of
-- it; a PATCH never does, because an absent attribute of a PATCH means
-- unchanged.
local core = require("hecate.core")
local schema = require("hecate.schema")

local Article = core.class("Article", nil, { implements = { schema.Representable } })
function Article.schema()
  return schema.object({
    title = schema.string(),
    tags = schema.default(schema.array(schema.string()), { "draft" }),
  })
end
core.finalise(Article)

local articles = schema.of(Article)

local _, created = articles:build({ title = "Hello" })
print(#created.tags, created.tags[1], schema.sent(created, "tags"))
-- Prints: 1	draft	false

-- The default is copied: changing it on one instance changes nothing else.
created.tags[1] = "changed"
local _, other = articles:build({ title = "Again" })
print(other.tags[1])
-- Prints: draft

local _, patched = articles:build({ title = "Renamed" }, { method = "PATCH" })
print(patched.tags, schema.sent(patched, "tags"))
-- Prints: nil	false

-- `validate` never supplies a value; it only checks.
print((schema.object({ tags = schema.default(schema.string(), "x") }):validate({})))
-- Prints: true
```

### Distinguer inchangé et effacé dans un PATCH

Dans un PATCH, un attribut absent signifie inchangé et un `null` explicite signifie effacé. Les deux laissent
l’attribut à `nil` dans l’instance, donc `schema.sent(instance, name)` les distingue. Elle vaut vrai quand l’attribut
était dans le contenu, `null` compris, et faux pour un attribut rempli par une valeur par défaut. Un PATCH n’assouplit
que les propriétés requises de l’objet de premier niveau. Les objets imbriqués restent stricts, et un `null` échoue
sauf si la propriété est `nullable`. Une valeur que `build` n’a pas faite n’a rien envoyé, et `sent` renvoie faux sans
lever d’erreur.

<!-- example: packages/schema/examples/hecate.schema.sent.lua -->
```lua
-- For a PATCH, `schema.sent` tells an attribute left unchanged from one that
-- was cleared.
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")

local Profile = core.class("Profile", nil, { implements = { schema.Representable } })
function Profile.schema()
  return schema.object({
    name = schema.string(),
    bio = schema.optional(schema.nullable(schema.string())),
  })
end
core.finalise(Profile)

local profiles = schema.of(Profile)

-- The attribute is absent: unchanged.
local _, unchanged = profiles:build({ name = "Ada" }, { method = "PATCH" })
print(unchanged.bio, schema.sent(unchanged, "bio"))
-- Prints: nil	false

-- The attribute is an explicit null: cleared. Both leave `bio` nil.
local _, cleared = profiles:build({ bio = json.null }, { method = "PATCH" })
print(cleared.bio, schema.sent(cleared, "bio"), schema.sent(cleared, "name"))
-- Prints: nil	true	false

-- A PATCH relaxes the required properties of the top-level object only.
print((profiles:build({}, { method = "POST" })))
-- Prints: false
print((profiles:build({}, { method = "PATCH" })))
-- Prints: true

-- A value that `build` did not make has sent nothing, and `sent` does not
-- raise.
print(schema.sent({ name = "Ada" }, "name"))
-- Prints: false
```

## Représenter une instance dans une réponse

`represent(value)` est l’autre sens de `build` : elle transforme une instance en valeurs simples que `json.encode` peut
écrire, sa [représentation](../reference/glossary.md#types-and-validation) (*representation*). `hecate.json` ne sait
rien des classes, c’est donc le schéma qui fait la conversion. Une partie liée à une classe devient une table simple
des attributs que son schéma déclare, et seulement ceux-là : un attribut que le schéma ne déclare pas, comme un
`password`, n’apparaît jamais, même si l’instance l’a. Un membre d’une énumération de `core` devient son nom. Les
parties imbriquées, les tableaux, les tables associatives, les unions et les unions étiquetées se convertissent
récursivement, et un tableau vide s’encode toujours en `[]` et une table associative vide en `{}`.

`represent` ne valide pas : elle fait confiance à la valeur, parce qu’une réponse non conforme est un bogue du serveur
(appelez `validate` là où vous voulez la vérifier). Un attribut absent est omis, `json.null` reste null, et une valeur
par défaut n’est jamais appliquée. L’entrée n’est pas modifiée et le résultat ne partage aucune table avec elle. Une
union utilise l’alternative qui accepte la valeur, et lève `ValidationError` quand aucune ne l’accepte. La garde
d’imbrication et le [budget de travail](../reference/glossary.md#types-and-validation) (*work budget*) s’appliquent
comme pour `validate` : un cycle dans le graphe d’objets lève une `ValidationError` dont la violation a le code
`depth_limit` et le JSON Pointer où elle s’est arrêtée.

<!-- example: packages/schema/examples/hecate.schema.Schema.represent.lua -->
```lua
-- Represent an instance for a response: declared attributes only, enumeration
-- members as names, then encode.
local core = require("hecate.core")
local json = require("hecate.json")
local schema = require("hecate.schema")

local Status = core.enumeration("AccountStatus", { "active", "disabled" })

local Account = core.class("Account", nil, { implements = { schema.Representable } })
function Account.schema()
  return schema.object({
    name = schema.string(),
    status = schema.enumeration(Status),
    tags = schema.array(schema.string()),
  })
end
core.finalise(Account)

local accounts = schema.of(Account)
local _, account = accounts:build({ name = "Ada", status = "active", tags = {} })
-- Not declared by the schema: it never reaches the response.
account.password = "secret"

local plain = accounts:represent(account)
print(plain.status, plain.password, core.is_instance_of(plain, Account))
-- Prints: active	nil	false
print(json.encode(plain.tags), json.encode(plain.name))
-- Prints: []	"Ada"

-- A cycle in the object graph ends with an error that names the limit,
-- instead of a hang.
local Node = core.class("Node", nil, { implements = { schema.Representable } })
function Node.schema() return schema.object({ next = schema.optional(schema.of(Node)) }) end
core.finalise(Node)

local node = core.allocate(Node)
node.next = node
local ok, err = pcall(schema.of(Node).represent, schema.of(Node), node)
print(ok, err.context.violations[1].code)
-- Prints: false	depth_limit
```

## Émettre du JSON Schema

`to_json_schema()` renvoie un document JSON Schema 2020-12 sous forme de valeurs simples.

<!-- example: packages/schema/examples/hecate.schema.to_json_schema.lua -->
```lua
-- The same schema emits a JSON Schema 2020-12 document, here to list its
-- required properties.
local schema = require("hecate.schema")

local user = schema.object({
  name = schema.string(),
  nickname = schema.optional(schema.string()),
})

local document = user:to_json_schema()
print(("%s %d"):format(document.type, #document.required))
-- Prints: object 1
```

Les choix faits de façon conservatrice (par exemple, `integer` refuse `1.0`) sont énumérés dans le README du paquet et
dans les questions ouvertes.

## Cas limites

Les sections suivantes couvrent les options et les constructions qui se comportent d’une façon qui peut surprendre.

### Contraindre les chaînes

`format` vérifie un format courant : `uuid`, `date`, `date-time`, `email`, `ipv4` ou `uri`. `pattern` est un motif Lua,
pas une expression régulière. La validation l’utilise tel qu’il est écrit. L’émission le traduit en expression
régulière ECMA-262 pour le contrat.

<!-- example: packages/schema/examples/hecate.schema.string.lua -->
```lua
-- `format` checks well-known string formats. `pattern` is a Lua pattern,
-- translated to an ECMA-262 regular expression when the schema is emitted.
local schema = require("hecate.schema")

print((schema.string({ format = "email" }):validate("ada@example.org")))
-- Prints: true

local sku = schema.string({ pattern = "^%u%u%-%d+$" })
print((sku:validate("AB-42")), (sku:validate("ab-42")))
-- Prints: true	false
print(sku:to_json_schema().pattern)
-- Prints: ^[A-Z][A-Z]-[0-9]+$

-- A pattern that cannot be translated exactly is refused when emitting, never
-- approximated: `%b` and `%f`, and any non-ASCII byte.
for _, pattern in ipairs({ "%bxy", "%f[%w]", "caf\u{e9}" }) do
  local refused = schema.string({ pattern = pattern })
  print((pcall(refused.to_json_schema, refused)))
end
-- Prints: false
-- false
-- false

-- A `logger` reports the pattern at declaration instead.
schema.string({ pattern = "%bxy", logger = { warning = function(_, message) print(message) end } })
-- Prints: schema: pattern "%bxy" cannot be emitted: %b has no exact translation
```

La traduction est exacte pour un sous-ensemble défini et refuse le reste. Les constructions refusées sont `%b`, `%f`,
la capture de position `()` et tout octet non ASCII dans le motif. Un schéma qui a un tel motif valide quand même en Lua,
mais `to_json_schema()` lève une `ArgumentError` qui le dit et indique comment réécrire le motif : utilisez des
ensembles, des classes, `format`, `min_length` ou `enum`. Passez un `logger` (tout objet doté d’une méthode
`warning(message, fields)`) pour être prévenu à la déclaration : le texte de l’avertissement contient le motif et la
raison, et `fields` aussi. Le sous-ensemble est décrit dans
[la spécification](https://github.com/hecate-framework/hecate/blob/main/docs/architecture/schemas-and-contracts.md#the-pattern-option).

### Limiter les nombres et les décimales

`integer` n’accepte que des entiers Lua, donc `1.0` est refusé. `multiple_of` prend un diviseur entier strictement
positif. Un diviseur fractionnaire comme `0.01` est refusé à la déclaration, parce que les flottants binaires ne savent
pas exprimer un pas décimal : `19.99` serait rejeté pour `0.01`, alors qu’un validateur à arithmétique décimale
l’accepte, et le contrat et le validateur ne seraient pas d’accord. Pour limiter le nombre de décimales, choisissez
l’une de ces deux solutions.

- Utilisez un entier en unités mineures, par exemple des centimes, ce qui est le bon modèle pour l’argent.
- Utilisez une chaîne avec un `pattern`, par exemple exactement deux décimales. JSON Schema n’a pas d’autre mot-clé
  pour un nombre de décimales.

<!-- example: packages/schema/examples/hecate.schema.integer.lua -->
```lua
-- `multiple_of` takes a whole-number divisor. For decimal places, use minor
-- units or a string.
local schema = require("hecate.schema")

local lots = schema.integer({ multiple_of = 5 })
print((lots:validate(15)), (lots:validate(16)))
-- Prints: true	false

-- A fractional divisor is refused at declaration: binary floats cannot
-- express a decimal step.
local declared, err = pcall(schema.number, { multiple_of = 0.01 })
print(declared, tostring(err):match("ArgumentError: ([^;]+)"))
-- Prints: false	schema: number: option multiple_of must be a whole number

-- First alternative: an integer in minor units, here cents (1999 is 19.99).
local cents = schema.integer({ minimum = 0 })
print((cents:validate(1999)))
-- Prints: true

-- Second alternative: a string with exactly two decimals.
local price = schema.string({ pattern = "^%d+%.%d%d$" })
print((price:validate("19.99")), (price:validate("19.9")))
-- Prints: true	false
```

### Déclarer des tables associatives et des énumérations

Un `map` a des clés de type chaîne qui ne sont pas connues à l’avance et un seul schéma pour toutes les valeurs. Il ne
prend pas de schéma de clés, parce que les clés d’un objet JSON sont toujours des chaînes. `min_properties` et
`max_properties` bornent sa taille.

<!-- example: packages/schema/examples/hecate.schema.map.lua -->
```lua
-- A map has string keys that are not declared in advance, and one schema for
-- every value.
local schema = require("hecate.schema")

local stock = schema.map(schema.integer({ minimum = 0 }), { max_properties = 2 })

print((stock:validate({ apples = 3, pears = 0 })))
-- Prints: true

local _, violations = stock:validate({ apples = -1 })
local violation = assert(violations)[1]
print(violation.path, violation.code)
-- Prints: /apples	minimum

_, violations = stock:validate({ apples = 1, pears = 2, plums = 3 })
violation = assert(violations)[1]
print(violation.path == "", violation.code)
-- Prints: true	max_properties

-- The emission is an object whose `additionalProperties` is the schema of the
-- values.
print(stock:to_json_schema().additionalProperties.type)
-- Prints: integer
```

`schema.enumeration` accepte aussi une énumération de `hecate.core`. La forme JSON d’un membre est son nom, donc
`validate` et `coerce` acceptent exactement les noms et jamais un objet membre. `build` remplace un nom par le membre,
y compris dans les objets, les tableaux et les tables associatives. Une valeur par défaut se donne sous forme de nom.

<!-- example: packages/schema/examples/hecate.schema.enumeration.lua -->
```lua
-- An enumeration of `core` is represented in JSON by the name of its members.
local core = require("hecate.core")
local schema = require("hecate.schema")

local Status = core.enumeration("Status", { "active", "disabled", "pending" })
local account = schema.object({ status = schema.enumeration(Status) })

print((account:validate({ status = "active" })))
-- Prints: true

-- Only the names are accepted, never the member itself.
local _, violations = account:validate({ status = "Active" })
local violation = assert(violations)[1]
print(violation.path, violation.code, table.concat(assert(violation.context).values, " "))
-- Prints: /status	enum	active disabled pending

-- `build` replaces the name by the member.
local _, built = account:build({ status = "disabled" })
print(built.status == Status.disabled)
-- Prints: true

local emitted = account:to_json_schema().properties.status
print(emitted.type, #emitted.enum)
-- Prints: string	3
```

### Choisir entre `union` et `tagged_union`

Quand les alternatives d’une somme se distinguent par une propriété qui contient une constante (un champ `type` ou
`kind`), déclarez une `tagged_union` : le validateur lit l’étiquette une fois et ne valide que la variante choisie,
sans revalidation. Une violation à l’intérieur de la variante garde son propre chemin. Une étiquette absente est une
violation `required` à la propriété d’étiquette, et une étiquette inconnue ou qui n’est pas une chaîne est une
violation `tagged_union` qui énumère les variantes dans `context.values`.

<!-- example: packages/schema/examples/hecate.schema.tagged_union.lua -->
```lua
-- A tagged union reads the tag once and validates only the selected variant.
local schema = require("hecate.schema")

local shape = schema.tagged_union("kind", {
  circle = schema.object({ radius = schema.number({ exclusive_minimum = 0 }) }),
  rectangle = schema.object({ width = schema.number(), height = schema.number() }),
})

print((shape:validate({ kind = "circle", radius = 2 })))
-- Prints: true

-- The violations are those of the selected variant, at the path of the
-- offending value.
local _, violations = shape:validate({ kind = "circle", radius = -1 })
local violation = assert(violations)[1]
print(violation.path, violation.code)
-- Prints: /radius	exclusive_minimum

-- An unknown tag lists the variants; a missing tag is a missing property.
_, violations = shape:validate({ kind = "triangle" })
violation = assert(violations)[1]
print(violation.path, violation.code, table.concat(assert(violation.context).values, " "))
-- Prints: /kind	tagged_union	circle rectangle
_, violations = shape:validate({ radius = 2 })
violation = assert(violations)[1]
print(violation.path, violation.code)
-- Prints: /kind	required

-- The emission is a `oneOf` of the variants, each with the tag as a constant.
print(#shape:to_json_schema().oneOf)
-- Prints: 2
```

Une union n’accepte jamais null d’elle-même : `nullable` est le seul moyen pour une propriété d’accepter
`json.null`. `schema.union` refuse à la déclaration (une `ArgumentError`) toute alternative qui accepte null :
`schema.null()`, un schéma `nullable`, `schema.literal(json.null)` ou une énumération contenant `json.null`, y compris
sous `named`, `optional` ou `default`. Enveloppez plutôt l’union, sous la forme
`nullable(union(...))` :

<!-- example: packages/schema/examples/hecate.schema.union.lua -->
```lua
-- A union never accepts null on its own: `nullable` is the only way for a
-- property to accept null.
local json = require("hecate.json")
local schema = require("hecate.schema")

local plain = schema.union({ schema.string(), schema.integer() })
print((plain:validate(json.null)))
-- Prints: false

-- A `null` or `nullable` alternative is refused at declaration, with a hint.
local ok, err = pcall(schema.union, { schema.string(), schema.null() })
print(ok, (err --[[@as table]]).code)
-- Prints: false	hecate.core.ArgumentError

-- Wrap the union instead.
local identifier = schema.nullable(plain)
print((identifier:validate(json.null)), (identifier:validate("a1")), (identifier:validate(true)))
-- Prints: true	true	false

-- `any` is different: it accepts every value, null included, by an explicit
-- choice.
print((schema.union({ schema.string(), schema.any() }):validate(json.null)))
-- Prints: true
```

`schema.any()` n’est pas refusé : il accepte toutes les valeurs, null compris, par un choix explicite et différent.

Une `union` décide chaque alternative à tour de rôle (en s’arrêtant à la première violation, propriétés littérales
d’abord) et mémorise sa réponse pour chaque table du contenu pendant un appel, de sorte que le travail est
proportionnel au nombre de tables multiplié par le nombre d’unions. En dernier recours, un appel qui demande plus de
1 000 000 d’étapes se termine par une violation `complexity_limit` au chemin où il s’est arrêté. Une `union` en échec
ne rapporte les violations de ses alternatives dans `context.alternatives` que pour l’union la plus externe.

### Nommer un schéma sans classe

Un schéma qui n’a ni classe ni appel à `named` est mis en ligne et ne reçoit jamais de nom.

Pour un schéma en ligne (*inline schema*) qui n’a pas de classe, `schema.named("User", definition)` est le choix
explicite : il valide et convertit comme `definition`, et l’émission le nomme de la même façon. Un nom est composé
de lettres, de chiffres, de `_`, de `.` et de `-`.

Deux définitions différentes sous un même nom dans une même émission lèvent une `ArgumentError` qui nomme le nom en conflit et
dit d’où vient chacun : une classe ou `named`. Cela couvre un nom en ligne égal au nom d’une classe. Des définitions égales
partagent une seule définition.
