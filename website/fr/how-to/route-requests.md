---
description: Déclarer des routes comme des données, les compiler avec hecate.router, apparier des requêtes avec des segments statiques, paramétrés et génériques, répondre 404 et 405 avec Allow, et construire des URL à partir des noms de routes.
hecate: "0.x"
lua: "5.5"
order: 13
source_revision: 0bf486ed5727dbeec306797d6c62f024f343b16d
---

# Acheminer les requêtes

`hecate.router` transforme une table de routes en arbre radix compilé et répond à une seule question : quelle route
sert cette méthode et ce chemin ? Il n’appelle pas l’action, ne valide pas les paramètres et ne construit pas de
réponses ; le noyau le fait à partir de la réponse du routeur.

Le routeur ne dépend que de `hecate.core`. Il n’a besoin d’aucun module natif.

## Déclarer et apparier

Une route est une table avec une `method` (ou une liste de méthodes), un [gabarit de chemin](../reference/glossary.md#http) (*path template*) dans `path`, un
`name` facultatif, et toutes les métadonnées que vous voulez récupérer. Le routeur conserve la table que vous lui
donnez ; la liste des routes est la [table de routes](../reference/glossary.md#http) (*route table*).

<!-- example: packages/router/examples/hecate.router.Router.lua -->
```lua
-- Declare routes as data, compile them once, match requests and build URLs from route names.
local router = require("hecate.router")

local routes = router.Router({
  { method = "GET", path = "/users", name = "users.list" },
  { method = "GET", path = "/users/{id}", name = "users.show" },
  { method = "DELETE", path = "/users/{id}", name = "users.delete" },
  { method = "GET", path = "/users/me", name = "users.me" },
  { method = "GET", path = "/static/{path...}", name = "static" },
})

local function show(method, path)
  local match = routes:match(method, path)
  if match.status == 200 then
    print(method, path, match.route.name, match.parameters.id or match.parameters.path or "-")
  else
    print(method, path, match.status, match.allow_field or "-")
  end
end

show("GET", "/users/42")
show("GET", "/users/me")
show("DELETE", "/users/me")
show("POST", "/users/42")
show("GET", "/static/css/site.css")
show("GET", "/nothing")
print(routes:url_for("users.show", { id = "Ada Lovelace" }))
-- Prints: GET	/users/42	users.show	42
-- GET	/users/me	users.me	-
-- DELETE	/users/me	users.delete	me
-- POST	/users/42	405	DELETE, GET, HEAD, OPTIONS
-- GET	/static/css/site.css	static	css/site.css
-- GET	/nothing	404	-
-- /users/Ada%20Lovelace
```

`match` renvoie toujours un `Match`. Son `status` dit quoi faire :

| Statut | Signification | Autres champs |
|---|---|---|
| 200 | une route sert la requête | `route`, `parameters` |
| 204 | `OPTIONS` automatique | `allow`, `allow_field` |
| 400 | le chemin est illisible | `reason` |
| 404 | aucune route n’a ce chemin | aucun |
| 405 | le chemin existe, mais pas pour cette méthode | `allow`, `allow_field` (le champ `Allow`, RFC 9110 section 10.2.1) |

## Gabarits de chemin

Les gabarits sont un sous-ensemble du niveau 1 de la RFC 6570 :

- `/users` est un chemin littéral. Les segments littéraux distinguent les majuscules des minuscules et peuvent
  contenir des octets encodés en pourcentage.
- `{id}` est un segment entier qui lie une valeur non vide. `/users/{id}.json` est refusé : un paramètre est un
  segment entier.
- `{path...}` en dernier segment lie le reste du chemin (au moins un segment) sous la forme d’une seule chaîne dont
  les `/` séparent les segments. La notation `...` est propre au routeur, elle ne vient pas de la RFC 6570.

Quand plusieurs routes pourraient servir un chemin, un segment statique l’emporte sur un paramètre, et un paramètre
sur un segment générique, segment par segment, avec un retour vers une branche de moindre précédence quand la branche
préférée n’a pas de route pour la méthode. L’appariement coûte quelques accès de table par segment, quel que soit le
nombre de routes.

## Le chemin de la requête

`http.Request.path` est brut. Le routeur décode chaque segment séparément et résout les segments point (*dot
segments*), dans cet ordre (RFC 3986 sections 2.1 et 5.2.4) :

<!-- example: packages/router/examples/hecate.router.path.lua -->
```lua
-- The router reads the raw path of a request: each segment is decoded on its own and dot segments are resolved first.
local router = require("hecate.router")

local routes = router.Router({
  { method = "GET", path = "/files/{name}", name = "file" },
  { method = "GET", path = "/docs/{topic}/index", name = "index" },
})

-- An encoded slash is data: it does not split the segment.
print(routes:match("GET", "/files/reports%2F2026.pdf").parameters.name)
-- Dot segments never climb above the root and are resolved before matching.
print(routes:match("GET", "/docs/x/../y/./index").parameters.topic)
print(routes:match("GET", "/../../files/a").parameters.name)
-- A path that cannot be read is a 400, not a 404.
local bad = routes:match("GET", "/files/%zz")
print(bad.status, bad.reason)
-- Prints: reports/2026.pdf
-- y
-- a
-- 400	malformed_percent_encoding
```

- `%2F` reste à l’intérieur de son segment. Un segment générique refuse un segment dont le texte décodé contient un
  `/`, de sorte que `..%2F..%2Fsecret` n’atteint jamais une action sous la forme `../../secret`.
- `%2E` est un point, comme le dit la RFC 3986 section 6.2.2.2. Un `.` ou `..` décodé est un segment point ;
  `%252e` est le texte `%2e`.
- Les segments vides sont conservés : `/a//b` ne correspond pas à `/a/{x}/b`.
- Une séquence de pourcentage mal formée et un octet NUL encodé donnent le statut 400.

## Barre oblique finale, HEAD et OPTIONS

Par défaut, `/users` et `/users/` sont deux chemins différents (`trailing_slash = "strict"`). Avec
`trailing_slash = "ignore"`, ils sont le même chemin, et deux routes qui ne diffèrent que par la barre oblique sont
ambiguës. Le routeur ne redirige jamais.

`HEAD` est servi par la route `GET` sauf si vous déclarez une route `HEAD` (`automatic_head = false` désactive ce
comportement). `OPTIONS` répond par le statut 204 avec `Allow` sauf si vous déclarez une route `OPTIONS`
(`automatic_options = false` le désactive, et la réponse est alors 405). Le `Allow` d’un 405 énumère aussi ces
méthodes automatiques.

## Erreurs détectées au démarrage

`router.Router(routes, options)` compile une seule fois et ne change plus jamais. Il lève `router.RouteTableError`,
une `ConfigurationError`, avec un `context.reason` stable, la position de la route (`context.index`) et, pour les
conflits, l’autre route (`context.other_index`) :

| Raison | Cause |
|---|---|
| `invalid_route` | pas une table, ni `method` ni `path`, un `name` incorrect |
| `invalid_method` | pas un jeton, une liste vide, une méthode répétée |
| `invalid_template` | un gabarit que la grammaire refuse (`context.template_reason` dit pourquoi) |
| `duplicate_name` | deux routes avec le même nom |
| `ambiguous_route` | deux routes qui servent la même méthode pour les mêmes chemins, par exemple `/users/{id}` et `/users/{user}` |

`/users/me` et `/users/{id}` ne sont pas ambiguës : la route statique a la précédence.

## Routage inverse et introspection

`routes:url_for(name, parameters)` construit le chemin d’une route nommée. Les valeurs sont des chaînes ou des
entiers et sont encodées en pourcentage ; la valeur d’un segment générique conserve ses `/`. Elle lève
`ArgumentError` pour un nom inconnu, un paramètre manquant ou inconnu, et une valeur qu’aucun chemin de requête ne
pourrait porter (vide, `.`, `..`, un octet NUL). `routes:routes()` énumère les routes déclarées dans l’ordre et
`routes:route(name)` en trouve une par son nom, pour la génération OpenAPI et la documentation.

Pour les raisons de cette conception, voir « Le modèle HTTP » (`explanation/http-model`, page encore non traduite) et la référence de code de
[`hecate.router`](../reference/router/index.md).
