---
description: Transformer les erreurs de votre domaine en détails de problème RFC 9457 avec hecate.problem - classes intégrées, problem.define, renvoyer ou lever un problème, la garde et errors.expose_details.
hecate: "0.x"
lua: "5.5"
order: 16
source_revision: 127cb3d2f023c24467492b8959dd7bc7bc0390d7
---

# Faire correspondre les erreurs du domaine à des détails de problème

Ce guide montre comment une application répond à ses erreurs par des
[détails de problème](../reference/glossary.md#http) (*problem details*,
[RFC 9457](https://www.rfc-editor.org/rfc/rfc9457)) : un objet JSON de type de média `application/problem+json`. Il est
écrit pour hecate 0.x et Lua 5.5, et suppose que vous avez une `Application` avec des routes (voir
[Acheminer les requêtes](route-requests.md)).

Les classes de problème vivent dans `hecate.problem` (la même table que `hecate.kernel.problem`). Un problème est une
[classe](../reference/glossary.md#object-model-and-architecture) (*class*) du modèle objet et une sous-classe de
`hecate.core.Error` : vous pouvez donc le renvoyer ou le lever.

## Utiliser une classe intégrée {#use-a-built-in-class}

`hecate.problem` a une classe par code d’état courant :

| Classe | État | Classe | État |
|---|---|---|---|
| `BadRequest` | 400 | `ContentTooLarge` | 413 |
| `Unauthorized` | 401 | `UnsupportedMediaType` | 415 |
| `Forbidden` | 403 | `UnprocessableContent` | 422 |
| `NotFound` | 404 | `TooManyRequests` | 429 |
| `MethodNotAllowed` | 405 | `InternalServerError` | 500 |
| `NotAcceptable` | 406 | `BadGateway` | 502 |
| `RequestTimeout` | 408 | `ServiceUnavailable` | 503 |
| `Conflict` | 409 | `GatewayTimeout` | 504 |
| `Gone` | 410 | | |
| `PreconditionFailed` | 412 | | |

Le titre de chaque classe est la phrase de raison de son code d’état (`Not Found`) et son `type` est `about:blank`.
Son code stable est `hecate.problem.<Name>`, par exemple `hecate.problem.NotFound`.

Construisez une occurrence avec deux champs facultatifs :

```lua
return hecate.problem.NotFound {
  detail = "No order 42.",
  extensions = { order = 42 },
}
```

- `detail` est une chaîne que vous écrivez pour le client. Ce n’est jamais un message d’erreur.
- `extensions` sont des membres supplémentaires de l’objet JSON (RFC 9457, section 3.2). Les noms `type`, `title`,
  `status`, `detail` et `instance` sont réservés et refusés par une `ArgumentError`, de même que tout champ autre que
  `detail`, `extensions` et `fields`. Une fonction, une coroutine, un userdata ou un nombre non fini est aussi refusé
  au premier niveau de `extensions`, car JSON ne peut pas le porter ; imbriqué plus profondément, il fait de la
  réponse un `500` générique, journalisé à la gravité `error`.

## Déclarer son propre problème {#declare-your-own-problem}

`hecate.problem.define(name, { status, title, type?, code? })` déclare une classe pour une erreur de votre domaine :

- `status` est un entier de 400 à 599 et `title` une chaîne non vide ;
- `type` est une référence URI qui identifie le problème (`about:blank` par défaut) ;
- `code` vaut `app.problem.<name>` par défaut. Un code de l’espace de noms `hecate.` appartient au framework et est
  refusé.

Chacune de ces erreurs lève aussitôt une `ArgumentError`, au chargement du module qui déclare la classe.

## Renvoyer ou lever un problème {#return-or-raise-a-problem}

L’exemple ci-dessous déclare `OutOfStock`, le renvoie depuis une fonction du domaine, lève `NotFound` depuis la même
fonction, et montre ce que donne une erreur qui n’est pas un problème.

<!-- example: packages/hecate/examples/hecate.problem.lua -->
```lua
-- Domain errors as problem details (RFC 9457). An action returns a problem,
-- or raises one from any depth; both answer application/problem+json. An
-- error that is not a problem answers a generic 500 that names nothing.
local schema = require("hecate.schema")
local http = require("hecate.http")
local json = require("hecate.json")
local hecate = require("hecate")

-- An application's own problem class: a status, a title and a type URI.
local OutOfStock = hecate.problem.define("OutOfStock", {
  status = 409, title = "Out of stock",
  type = "https://example.com/problems/out-of-stock",
})
print(OutOfStock.code)
-- Prints: app.problem.OutOfStock

local STOCK = { lamp = 0, desk = 3 }

local function reserve(item)
  if STOCK[item] == nil then
    -- Raised deep in the domain code: the guard of the kernel maps it.
    error(hecate.problem.NotFound { detail = "No such item." })
  end
  if STOCK[item] == 0 then
    return OutOfStock { detail = "Nothing left.", extensions = { item = item } }
  end
  if item == "desk" then error("database connection lost: 10.0.0.5") end
end

local orders = hecate.routes("orders")
orders:post("/orders/{item}", {
  name = "order.reserve",
  parameters = { path = { item = schema.string({ max_length = 20 }) } },
  responses = {
    [204] = true, [404] = hecate.problem.NotFound, [409] = OutOfStock,
  },
  action = function(request) return reserve(request.parameters.path.item) end,
})

local serve = hecate.Application({ routes = { orders } }):boot()
-- Asks the application in-process; returns the status and the decoded JSON.
local function post(target)
  local request = http.Request({
    method = "POST", target = target, fields = http.Fields(),
  })
  local response = serve(request)
  return response.status, json.decode(response.content --[[@as string]])
end

local status, body = post("/orders/lamp")
print(status, body.type)
-- Prints: 409	https://example.com/problems/out-of-stock
print(body.title, body.detail, body.item)
-- Prints: Out of stock	Nothing left.	lamp
status, body = post("/orders/chair")
print(status, body.type, body.title, body.detail)
-- Prints: 404	about:blank	Not Found	No such item.
status, body = post("/orders/desk")
print(status, body.title)
-- Prints: 500	Internal Server Error
print(body.detail)
-- Prints: The server could not process the request.
```

- **Renvoyez** un problème quand l’action décide de la réponse. Le résultat de l’action passe par la même
  sérialisation qu’une valeur, et un problème devient `application/problem+json`.
- **Levez** un problème (`error(NotFound { ... })`) depuis du code situé bien en dessous de l’action, où renvoyer est
  malcommode. La garde du noyau l’attrape et y répond de la même façon.
- **Toute autre erreur** (une erreur Lua, une `hecate.core.Error`) donne un `500` générique. Son message n’atteint
  jamais le client : ici, `database connection lost: 10.0.0.5` reste sur le serveur, dans le journal (voir plus bas).

La réponse porte `type`, `title`, `status`, le `detail` que vous avez donné et les membres d’extension. Elle n’a pas
de membre `instance`.

## Ajouter des champs à un problème {#add-header-fields-to-a-problem}

Certaines réponses ont besoin d’un champ d’en-tête ([RFC 9110](https://www.rfc-editor.org/rfc/rfc9110)) :
`WWW-Authenticate` sur un `401` (sections 11.6.1 et 15.5.2), `Allow` sur un `405` (section 15.5.6), `Retry-After` sur
un `429` ou un `503` (section 10.2.3). Donnez-les dans `fields`, un nom vers une chaîne, ou vers une liste de chaînes
pour plusieurs lignes de champ :

```lua
return hecate.problem.Unauthorized {
  fields = { ["WWW-Authenticate"] = 'Bearer realm="api"' },
}
```

Les champs vont dans la réponse, jamais dans l’objet JSON ni dans le contrat de la route ; ils s’appliquent à un
problème que vous renvoyez ou levez. Un nom qui n’est pas un jeton, ou une valeur contenant un caractère de contrôle,
lève une `ArgumentError` à la construction du problème, de même que `Content-Type`, `Content-Length`,
`Transfer-Encoding` et `Connection`, que le noyau fixe lui-même.

## Déclarer les problèmes d’une route {#declare-the-problems-of-a-route}

La table `responses` d’une route accepte une classe de problème pour un code d’état, comme le fait l’exemple avec
`[404] = hecate.problem.NotFound`. Cela inscrit la réponse dans la table de routes, la donnée à partir de laquelle le
document OpenAPI est prévu (phase 3). Cela ne change rien à l’exécution : une action peut renvoyer ou lever un
problème que sa route ne déclare pas.

## Savoir ce que fait la garde {#know-what-the-guard-does}

La garde (`problems.guard`) enveloppe chaque requête, à l’intérieur des filtres globaux. Elle transforme en réponse ce
qui échappe aux filtres et à l’action :

| Levé | Réponse |
|---|---|
| un problème | son propre code d’état, titre, type, détail et extensions |
| une erreur de `hecate.http` qui porte un code d’état client (un formulaire mal formé, un contenu au-delà de la limite) | ce code d’état |
| toute autre chose | un `500` générique |

Le `422` des entrées invalides ne vient pas de la garde : l’étape qui lit les entrées y répond avant l’exécution de
l’action. Elle journalise elle-même le refus (voir « Le 422 des entrées » plus bas). Elle liste une entrée par
[violation](../reference/glossary.md#types-and-validation) (*violation*), cent au plus : `pointer` (un JSON Pointer,
RFC 6901), `source` (`path`, `query`, `header`, `cookie` ou `content`) et `code`. Une `ValidationError` levée par votre
propre code, par `schema:check` par exemple, ne concerne pas la requête : c’est un `500`. Pour répondre un `422` depuis
une action, renvoyez ou levez `UnprocessableContent`.

Les erreurs d’annulation et d’échéance ne sont jamais attrapées : elles appartiennent à la
[portée](../reference/glossary.md#concurrency) (*scope*) qui les a levées.

> [!NOTE] Où la garde journalise
> La garde journalise un échec par le journaliseur de l’application : l’option `logger`, ou celui que le noyau
> construit à partir d’une `configuration`. Sans l’un ni l’autre, elle journalise par le journaliseur par défaut de
> `hecate.log`, sur le flux d’erreur standard : un `500` n’est donc jamais silencieux. Un problème inférieur à 500 est
> une réponse normale et n’est jamais journalisé ; un problème à partir de 500 l’est à la gravité `error`.

### Le 422 des entrées {#the-422-of-the-inputs}

L’étape des entrées journalise chaque réponse qu’elle construit (`422`, `400` et `415`) à la gravité `warning`, avec le
message `request refused`, par le même journaliseur que la garde. L’enregistrement porte `method`, `path` sans la
chaîne de requête, `status`, une `reason` (`invalid_input`, `malformed_content`, `unsupported_media_type`,
`repeated_content_type` ou `content_too_large`) et, pour un `422`, les `codes` des violations. Il ne contient jamais
une valeur, un nom de paramètre ni un JSON Pointer : une requête de recherche peut porter un identifiant secret, et une
clé peut être une donnée personnelle. Une requête dont les entrées sont conformes ne journalise rien.

### Accepter une requête sans corps {#accept-a-request-without-a-body}

Une route qui déclare `content` exige son corps : une requête sans corps est un `422`, le schéma signalant la valeur
manquante. Pour accepter une requête sans corps, ajoutez `content_optional = true` à la déclaration de la route.
L’étape des entrées laisse alors passer un corps vide, avec ou sans champ `Content-Type`, et l’action lit
`request.content` comme `nil`. Un corps qui n’est pas vide est validé comme avant : un corps non conforme reste un
`422`, un JSON mal formé un `400`, un autre type de média, ou aucun, un `415`. L’indicateur exige un `content` déclaré
et une valeur booléenne ; la déclaration est refusée sinon, avec la raison `invalid_content_optional`.

### L’enregistrement de la garde {#the-record-of-the-guard}

L’enregistrement journalisé porte le message de l’erreur, sa classe (`error_class`) et son code (`error_code`), la
méthode, le chemin sans la chaîne de requête, et la trace de pile de l’endroit où elle a été levée. Tant que
`errors.expose_details` vaut `false`, les causes de l’erreur ne sont nommées que par classe et code, jamais par leurs
messages.

## Montrer les détails en développement {#show-details-in-development}

La clé de configuration `errors.expose_details` (`false` par défaut ; l’option `expose_details` d’`Application`)
ajoute des détails internes aux réponses :

- chaque entrée d’un `422` porte aussi le `message` de sa violation ;
- un `500` générique porte un membre `debug` : `{ error = <class name>, message = <text>, traceback = <when known> }`.

Le `detail` et les extensions d’un problème sont toujours montrés, avec ou sans cette clé : vous les avez choisis.
Fixez la clé à `true` dans `config/development.lua` et `config/test.lua` seulement. Quand elle vaut `true` dans
l’environnement `production`, l’application journalise l’avertissement `expose_details_in_production` au démarrage.
Voir [Configurer une application](configure-an-application.md).

## Répondre un problème sans le noyau {#answer-a-problem-without-the-kernel}

Une action donnée directement à `hecate.http.Server` n’a pas de garde. Elle construit ses détails de problème avec
`http.problem.response(status, detail?)`, comme le montre
[Servir du HTTP](serve-http.md#answer-errors-with-problem-details).

## Voir aussi {#see-also}

- [Filtres](filters.md) : un filtre peut répondre un problème avant l’exécution de l’action.
- [Valider des valeurs avec des schémas](validate-with-schemas.md) : violations, codes et JSON Pointers.
- [Avant la mise en production](../../../../user/en/how-to/before-going-to-production/) : détails d’erreur et journalisation.
