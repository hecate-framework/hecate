---
description: Envelopper des actions avec des filtres, la chaîne de responsabilité de hecate.kernel - les quatre niveaux et leur ordre, les court-circuits, l’authentification et CORS écrits comme des filtres, et ce qui n’existe pas encore.
hecate: "0.x"
lua: "5.5"
order: 17
source_revision: 127cb3d2f023c24467492b8959dd7bc7bc0390d7
---

# Filtres

Un [filtre](../reference/glossary.md#object-model-and-architecture) (*filter*) enveloppe l’
[action](../reference/glossary.md#object-model-and-architecture) (*action*) d’une route. Les filtres d’une requête
forment une [chaîne de responsabilité](../reference/glossary.md#object-model-and-architecture) (*chain of
responsibility*) : chacun voit la requête à l’aller et le résultat au retour, et peut arrêter la requête avant
l’action. Ce guide est écrit pour hecate 0.x et Lua 5.5, et suppose que vous savez déclarer des routes avec
`hecate.routes` ou un [contrôleur](../reference/glossary.md#object-model-and-architecture) (*controller*).

## Écrire un filtre {#write-a-filter}

Un filtre est toute table dotée d’une fonction `handle(self, request, next)` : une table simple ou une instance de
classe.

```lua
local pass_through = {
  handle = function(self, request, next)
    local result = next(request)  -- the rest of the chain, then the action
    return result
  end,
}
```

Dans `handle`, un filtre peut :

- **transmettre** la requête, `return next(request)`, éventuellement après l’avoir modifiée ;
- **court-circuiter** : renvoyer un résultat sans appeler `next`, de sorte que l’action ne s’exécute jamais ;
- **post-traiter** : modifier ce que `next` a renvoyé avant de le renvoyer.

Une erreur levée par un filtre est traitée comme une erreur de l’action : la garde la transforme en
[détails de problème](map-domain-errors-to-problem-details.md). La chaîne est composée une fois, au démarrage : un
filtre ne coûte donc aucune allocation par requête. Rien n’empêche un filtre d’appeler `next` deux fois ; ne le faites
que volontairement.

## Attacher des filtres à quatre niveaux {#attach-filters-at-four-layers}

| Niveau | Où | S’applique à |
|---|---|---|
| global | option `filters` d’`Application` | toute requête, y compris celles qui ne correspondent à aucune route |
| module fonctionnel | champ `filters` de la table du module | les routes de ce module |
| contrôleur | champ de classe `filters` du contrôleur | les routes de ce contrôleur |
| route | champ `filters` de la déclaration de la route | cette route |

L’ordre est global, module, contrôleur, puis route, le plus externe en premier. Dans une liste, le premier filtre est
le plus externe. L’exemple suit un filtre de chaque niveau :

<!-- example: packages/hecate/examples/hecate.Application.filters.lua -->
```lua
-- The order of the filter chain: the filters of the application, of the
-- feature module, of the controller, then of the route, outermost first.
-- Each filter sees the request on the way in and the result on the way out.
local core = require("hecate.core")
local http = require("hecate.http")
local hecate = require("hecate")

-- A filter is any table with a `handle(self, request, next)` function.
local trail = {}
local function trace(name)
  return {
    handle = function(_, request, next)
      trail[#trail + 1] = name
      local result = next(request)
      trail[#trail + 1] = "/" .. name
      return result
    end,
  }
end

local Reports = core.class("Reports", hecate.Controller)
Reports.prefix = "/reports"
Reports.filters = { trace("controller") }
hecate.Controller.route(Reports, {
  method = "GET", path = "/daily", name = "report.daily", action = "daily",
  filters = { trace("route") },
})
function Reports:daily()
  trail[#trail + 1] = "action"
  return { total = 42 }
end
core.finalise(Reports)

local app = hecate.Application({
  filters = { trace("global") },
  modules = {
    { name = "reporting", routes = { Reports }, filters = { trace("module") } },
  },
})
local serve = app:boot()

local function get(target)
  trail = {}
  local request = http.Request({
    method = "GET", target = target, fields = http.Fields(),
  })
  return serve(request).status
end

print(get("/reports/daily"))
-- Prints: 200
print(table.concat(trail, " ", 1, 5))
-- Prints: global module controller route action
print(table.concat(trail, " ", 6))
-- Prints: /route /controller /module /global

-- Only the global filters see a request that matches no route.
print(get("/nothing"))
-- Prints: 404
print(table.concat(trail, " "))
-- Prints: global /global
```

Un module de routes n’a pas de niveau propre. L’option `filters` de `hecate.routes(name, { filters = ... })` donne les
filtres *par défaut* de ses routes : une route qui déclare `filters` les remplace, et `filters = {}` les supprime. Les
filtres d’un contrôleur, eux, s’exécutent toujours, avant ceux de la route.

## Savoir ce que voit chaque niveau {#know-what-each-layer-sees}

Les filtres globaux enveloppent l’étape de routage. Ils voient toute requête : les réponses de problème `404`, `405`
et `400` et la réponse automatique à `OPTIONS` passent par eux. Quand ils s’exécutent, la route n’est pas encore
connue : `request.parameters.path` est vide et `request.services` n’est pas fixé.

Les autres niveaux s’exécutent après le routage. Là :

- `request.services` est la [portée de service](../reference/glossary.md#object-model-and-architecture) (*service
  scope*) de la requête, quand l’application a un conteneur ;
- `request.parameters.path` contient les paramètres de chemin sous forme de chaînes brutes ;
- les entrées ne sont pas encore validées. Le noyau convertit et valide le chemin, la requête de recherche, les champs
  d’en-tête, les cookies et le contenu après le dernier filtre, juste avant l’action. Une requête refusée par un filtre
  ne coûte aucune lecture de son contenu.

Ce que `next` renvoie diffère aussi :

- pour un filtre **global**, `next` renvoie une `hecate.http.Response` : le résultat est déjà sérialisé, et une erreur
  est déjà une réponse de problème ;
- pour un filtre de **module, de contrôleur ou de route**, `next` renvoie ce que l’action a renvoyé : une valeur, une
  `Response` ou un problème. La sérialisation a lieu après la chaîne. Un filtre qui fixe des champs de réponse est donc
  un filtre global, ou il doit traiter chaque sorte de résultat.

Une réponse dont le contenu est une fonction est écrite une fois la chaîne revenue. Un filtre peut fixer ses champs,
pas lire ni modifier son contenu.

## S’authentifier avec un filtre {#authenticate-with-a-filter}

L’authentification est un filtre des routes qui en ont besoin. L’exemple ci-dessous refuse une requête sans jeton
porteur connu par un `401` avec son champ `WWW-Authenticate`, et transmet l’utilisateur à l’action. Il contient aussi
le filtre CORS de la section suivante.

<!-- example: packages/hecate/examples/hecate.filter.authentication_and_cors.lua -->
```lua
-- Two filters written with the kernel of today: authentication, which
-- refuses a request before the action runs, and CORS, which answers the
-- preflight request and marks every response of an allowed origin.
local http = require("hecate.http")
local hecate = require("hecate")

-- Authentication: a filter of the routes that need it. It short-circuits
-- with a 401 (RFC 9110 asks for WWW-Authenticate) or passes the principal.
---@class app.Request : hecate.kernel.Request
---@field principal string?  set by the authentication filter

local TOKENS = { ["s3cret"] = "ada" }
local authenticate = {
  handle = function(_, request, next)
    local token = (request.fields:get("Authorization") or "")
      :match("^Bearer (%S+)$")
    local user = token and TOKENS[token]
    if user == nil then
      local refused = http.problem.response(401, "A bearer token is needed.")
      refused.fields:set("WWW-Authenticate", 'Bearer realm="accounts"')
      return refused
    end
    request.principal = user
    return next(request)
  end,
}

-- CORS: a global filter, because the preflight OPTIONS request matches no
-- declared route and only the global filters see it.
local ALLOWED = "https://app.example.com"
local cors = {
  handle = function(_, request, next)
    local origin = request.fields:get("Origin")
    if origin ~= ALLOWED then return next(request) end
    local response
    if request.method == "OPTIONS"
      and request.fields:get("Access-Control-Request-Method") then
      response = http.Response(204)
      response.fields:set("Access-Control-Allow-Methods", "GET, POST")
      response.fields:set("Access-Control-Allow-Headers", "Authorization")
      response.fields:set("Access-Control-Max-Age", "600")
    else
      -- Global filters receive a Response: the result is serialised.
      response = next(request)
    end
    response.fields:set("Access-Control-Allow-Origin", origin)
    response.fields:add("Vary", "Origin")
    return response
  end,
}

-- The filters of a route module are the default filters of its routes.
local accounts = hecate.routes("accounts", { filters = { authenticate } })
accounts:get("/me", {
  name = "account.me",
  ---@param request app.Request
  action = function(request) return { user = request.principal } end,
})

local serve = hecate.Application({ routes = { accounts }, filters = { cors } })
  :boot()
local function ask(method, fields)
  return serve(http.Request({
    method = method, target = "/me", fields = http.Fields(fields),
  }))
end

local response = ask("GET", { Authorization = "Bearer s3cret" })
print(response.status, response.content)
-- Prints: 200	{"user":"ada"}
response = ask("GET", {})
print(response.status, response.fields:get("WWW-Authenticate"))
-- Prints: 401	Bearer realm="accounts"
response = ask("OPTIONS", {
  Origin = ALLOWED, ["Access-Control-Request-Method"] = "GET",
})
print(response.status, response.fields:get("Access-Control-Allow-Methods"))
-- Prints: 204	GET, POST
response = ask("GET", { Origin = ALLOWED })
print(response.status, response.fields:get("Access-Control-Allow-Origin"))
-- Prints: 401	https://app.example.com
```

Le filtre range l’utilisateur dans la requête (`request.principal`). C’est un champ ordinaire qui vous appartient : le
paquet `security`, qui fournira des filtres d’authentification, n’existe pas encore. Dans une vraie application,
comparez les jetons d’un magasin en temps constant ; la recherche dans une table ci-dessus n’est qu’une illustration.

Pour refuser avec un corps seulement, sans champ d’en-tête, un filtre peut aussi renvoyer un problème tel que
`hecate.problem.Forbidden { detail = "..." }` : la sérialisation après la chaîne y répond.

## Répondre à CORS avec un filtre {#answer-cors-with-a-filter}

Le filtre `cors` de l’exemple est global, pour deux raisons. La requête de contrôle préalable (*preflight* : `OPTIONS`
avec `Access-Control-Request-Method`) ne correspond à aucune route déclarée, et seuls les filtres globaux la voient.
Et un filtre global reçoit une `Response` : il peut donc fixer le champ `Access-Control-Allow-Origin` sur chaque
réponse, y compris un `401` venu d’un filtre interne. Ajoutez `Vary: Origin` pour qu’un cache garde une réponse par
origine.

### Utiliser le filtre CORS livré {#use-the-shipped-cors-filter}

Quand la politique est une liste d’origines, vous n’avez pas à écrire le filtre : `hecate.kernel` en livre un,
piloté par des clés, de sorte qu’un conteneur puisse le régler depuis son environnement. Il est désactivé tant que
vous ne l’activez pas, et n’autorise aucune origine par défaut.

```text
HECATE_CORS__ENABLED=true
HECATE_CORS__ALLOWED_ORIGINS=https://app.example.com,https://admin.example.com
HECATE_CORS__ALLOWED_HEADERS=Authorization,Content-Type
HECATE_CORS__ALLOW_CREDENTIALS=true
```

Les mêmes clés vont dans `config/default.lua` (sous `cors`) ou dans l’option `cors` d’`Application`, qui l’emporte
clé par clé. Le filtre est le filtre global le plus externe. Il répond lui-même à une requête de contrôle préalable,
par `204`, et ajoute `Access-Control-Allow-Origin` aux réponses d’une origine autorisée. Par défaut, seuls `GET`,
`HEAD` et `POST` sont autorisés et `max_age` vaut 600 : listez `allowed_methods` quand vous avez besoin de `PUT` ou de
`DELETE`, faute de quoi leur contrôle préalable est refusé en silence. Les origines sont comparées exactement, telles
que le navigateur les écrit (`scheme://host[:port]`, en minuscules). Un contrôle préalable qui demande une méthode ou
un champ d’en-tête que vous n’avez pas autorisé n’obtient aucune permission : le navigateur bloque l’appel. `*` est
accepté seul, et jamais avec des identifiants : le démarrage échoue avec une `ArgumentError` qui nomme la clé. Voir
« The CORS keys » dans la spécification de la configuration pour chaque clé et son défaut.

## Ce qui n’existe pas encore {#what-does-not-exist-yet}

- **Compression.** hecate n’a pas de codec de compression. Un filtre pourrait remplacer le contenu d’une réponse par
  un contenu compressé, mais le codec serait une dépendance tierce, qui demande d’abord une décision d’architecture.
  Ce guide n’en montre aucun.
- **Identifiants de requête.** Lier un identifiant de requête dans le
  [contexte ambiant](../reference/glossary.md#concurrency) (*ambient context*), pour que chaque enregistrement de
  journal d’une requête le porte, est conçu (ADR 0025) et différé : le noyau ne le fait pas encore. Un filtre global
  peut lire ou créer un champ `X-Request-Id` et le fixer sur la réponse, et `log.bind({ request_id = id }, next,
  request)` le lie pour les enregistrements écrits pendant l’exécution du reste de la chaîne (voir
  [Journaliser des enregistrements structurés](log-structured-records.md)).
- **Filtres intégrés.** Aucun filtre de journal d’accès, de limitation de débit ou d’authentification n’est livré
  avec le noyau. Le journal d’accès est le crochet `on_response` du serveur (voir `examples/hello`).

## Voir aussi {#see-also}

- [Faire correspondre les erreurs du domaine à des détails de problème](map-domain-errors-to-problem-details.md)
- [Utiliser le conteneur](use-the-container.md) : services résolus dans `request.services`.
- [Journaliser des enregistrements structurés](log-structured-records.md)
