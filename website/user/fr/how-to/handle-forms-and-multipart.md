---
description: Lire des formulaires urlencoded et des téléversements multipart dans une action, ne jamais faire confiance au nom de fichier d’un client, et envoyer des formulaires et des messages multipart avec le client.
hecate: "0.x"
lua: "5.5"
order: 11
source_revision: 127cb3d2f023c24467492b8959dd7bc7bc0390d7
---

# Traiter les formulaires et le multipart

Ce guide montre comment lire un contenu `application/x-www-form-urlencoded` et `multipart/form-data` dans une
[action](../reference/glossary.md#object-model-and-architecture) (*action*), la fonction qui sert une requête. Il
montre aussi comment envoyer les deux avec le client. Il est écrit pour hecate 0.x et Lua 5.5, et suppose que vous
savez [servir du HTTP](serve-http.md).

Les analyseurs de formulaires sont en Lua pur. Ils n’ont besoin d’aucun module natif.

## Lire un formulaire urlencoded {#read-a-urlencoded-form}

`request:read_form(limits?)` lit le contenu et renvoie un `Form`. Un `Form` a ces méthodes, et ses noms peuvent se
répéter :

- `get(name)`, la première valeur, ou `nil` ;
- `get_all(name)`, toutes les valeurs, dans l’ordre ;
- `count()` et `pairs()`.

<!-- example: packages/http/examples/hecate.http.Request.read_form.lua -->
```lua
-- An action that reads a urlencoded form. The client sends pairs with
-- `form`; a name that repeats keeps its order.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function action(request)
  local form = request:read_form({ max_pairs = 50 })
  local tags = table.concat(form:get_all("tag"), ",")
  return http.Response(200, { content = form:get("name") .. " " .. tags })
end

reactor.run(function()
  local server = http.Server(action, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local url = "http://127.0.0.1:" .. listener:local_address().port .. "/"
  local client <close> = http.Client()
  local response = client:post(url, nil, {
    form = { { "name", "Ada Lovelace" }, { "tag", "math" }, { "tag", "code" } },
  })
  print(response:read_content())
  -- Prints: Ada Lovelace math,code
  server:shutdown()
  reactor.join(serving)
end)
```

`read_form` lève une `FormError` avec le code d’état 415 quand le `Content-Type` n’est pas urlencoded.

### Limites {#limits}

Les limites d’un formulaire sont `max_pairs` (1000) et `max_size` (1 Mio). Au-delà de l’une ou l’autre, le
formulaire est refusé par un 413.

Le `max_content` du serveur s’applique d’abord (1 Mio par défaut). Un formulaire plus grand est une `ContentError`
413 pendant sa lecture, et `limits.max_size` ne peut qu’abaisser cette borne.

### Ce que l’analyseur accepte {#what-the-parser-accepts}

L’analyseur est strict par choix. Ces entrées sont refusées par un 400 plutôt que devinées :

- une séquence de pourcentage mal formée (`%`, `%4`, `%zz`) ;
- un texte qui n’est pas de l’UTF-8 valide ;
- un octet NUL.

`+` est une espace, `%XX` est un octet, et le premier `=` sépare un nom de sa valeur. Les paires vides entre `&`
sont ignorées.

Pour construire le texte vous-même, utilisez `http.form.encode_urlencoded(pairs)`. Pour analyser une chaîne sans
requête, utilisez `http.form.parse_urlencoded(text, limits?)`.

## Lire un téléversement multipart {#read-a-multipart-upload}

`request:stream_parts(limits?)` renvoie un lecteur. `reader:next_part()` se suspend jusqu’à ce que la partie
suivante soit prête, puis renvoie une `Part`, ou `nil` après la dernière.

Une partie a :

- `name`, `filename` et `content_type` ;
- `fields`, ses propres `Fields` ;
- `read_content(limit?)` et `stream_content()` ;
- `safe_filename()`.

<!-- example: packages/http/examples/hecate.http.Request.stream_parts.lua -->
```lua
-- An action that reads a multipart upload part by part. The file is never
-- trusted with its name: the action keeps its own and only counts the bytes.
local reactor = require("hecate.reactor")
local http = require("hecate.http")

local function action(request)
  local reader = request:stream_parts({ max_part_size = 1024 * 1024 })
  local seen = {}
  while true do
    local part = reader:next_part()
    if part == nil then break end
    if part.filename ~= nil then
      local size = 0
      local stream = part:stream_content()
      while true do
        local chunk = stream:read()
        if chunk == nil then break end
        size = size + #chunk
      end
      seen[#seen + 1] = ("%s: %d bytes (client name %s)"):format(part.name, size, tostring(part:safe_filename()))
    else
      seen[#seen + 1] = part.name .. "=" .. part:read_content()
    end
  end
  return http.Response(200, { content = table.concat(seen, "; ") })
end

reactor.run(function()
  local server = http.Server(action, { port = 0 })
  local listener = server:listen()
  local serving = reactor.fork(server.serve, server, listener)
  local url = "http://127.0.0.1:" .. listener:local_address().port .. "/"
  local client <close> = http.Client()
  local response = client:post(url, nil, {
    multipart = {
      { name = "title", content = "report" },
      { name = "upload", filename = "../../etc/passwd", content_type = "text/plain", content = ("x"):rep(100) },
    },
  })
  print(response:read_content())
  -- Prints: title=report; upload: 100 bytes (client name passwd)
  server:shutdown()
  reactor.join(serving)
end)
```

Le lecteur ne tire du contenu que lorsqu’il en a besoin. Il garde un fragment, les champs d’en-tête de la partie
courante, et la queue d’un éventuel délimiteur. Une partie que vous laissez non lue est sautée, dans la limite de
`max_part_size`. Les parties arrivent dans l’ordre, et les noms en double sont aussi livrés dans l’ordre.

### Limites {#multipart-limits}

| Limite | Défaut | Quand elle est dépassée |
|---|---|---|
| `max_parts` | 100 | 413 |
| `max_part_fields_size` | 8192 octets | 413 |
| `max_part_size` | 1 Mio | 413 (`ContentError`) |
| `max_total_size` | 1 Mio | 413 |

Le `max_content` du serveur borne d’abord le message entier. Relevez les deux quand vous acceptez de plus gros
téléversements.

### Ne jamais faire confiance au nom de fichier d’un client {#never-trust-a-client-filename}

> [!WARNING] N’utilisez jamais le nom de fichier d’un client comme chemin
> `part.filename` est la valeur brute envoyée par le client. Stockez le fichier sous un nom que vous générez, et
> gardez le nom du client comme donnée. Aucun code de `hecate.http` n’ouvre un fichier d’après un nom de client.

`part:safe_filename()` réduit le nom de fichier à un nom de base prudent :

- il retire les répertoires (`/` et `\`), les caractères de contrôle et les caractères `< > : " | ? *` ;
- il retire les points de tête, et les points et espaces de queue ;
- il coupe le nom à 255 octets, jamais au milieu d’un caractère UTF-8 ;
- il renvoie `nil` pour un nom de périphérique Windows (`CON`, `PRN`, `AUX`, `NUL`, `COM1` à `COM9`, `LPT1` à
  `LPT9`, avec ou sans extension), et quand il ne reste rien.

Le résultat reste le choix du client. Il réduit le risque d’un tour de passe-passe sur les chemins ; il ne rend pas
le nom digne de confiance.

### Ce que le lecteur n’analyse pas {#what-the-reader-does-not-parse}

- Un `multipart/mixed` imbriqué n’est pas analysé : il arrive comme une seule partie, avec le message interne pour
  contenu.
- `Content-Transfer-Encoding` est ignoré.

## Refus {#refusals}

Une `FormError` porte `context.reason` et `context.status`. Dans une action, vous pouvez la laisser s’échapper : le
serveur répond par des [détails de problème](../reference/glossary.md#http) (*problem details*) qui ne reprennent
rien de l’entrée.

| Raison | Code d’état |
|---|---|
| `unsupported_media_type` | 415 |
| `bad_boundary`, `bad_part_fields`, `missing_name`, `truncated` | 400 |
| `too_many_parts`, `part_fields_too_large`, `total_too_large` | 413 |
| `bad_percent_encoding`, `invalid_utf8`, `nul_in_value` | 400 |
| `too_many_pairs`, `too_large` | 413 |

## Envoyer des formulaires et du multipart avec le client {#send-forms-and-multipart-with-the-client}

Passez `form` pour envoyer du contenu urlencoded. C’est une liste de paires `{ name, value }`.

```lua
client:post(url, nil, { form = { { "q", "lua 5.5" }, { "page", "2" } } })
```

Passez `multipart` pour envoyer du `multipart/form-data`. Chaque partie est
`{ name, filename?, content_type?, content }`, et `content` est une chaîne ou une fonction qui diffuse.

```lua
client:post(url, nil, {
  multipart = {
    { name = "title", content = "report" },
    { name = "upload", filename = "data.csv", content_type = "text/csv",
      content = function(write) write("a,b\n"); write("1,2\n") end },
  },
})
```

La frontière (*boundary*) est aléatoire. Le cadrage dépend des parties :

- Avec seulement des parties chaîne, le message est envoyé avec `Content-Length`, et il peut être rejoué.
- Avec une partie fonction, il est diffusé avec le codage par fragments.

## Voir aussi {#see-also}

- [Diffuser du contenu HTTP](stream-http-content.md)
- [Définir les limites, les délais et TLS du serveur HTTP](http-limits-timeouts-and-tls.md)
- [Le modèle HTTP](../explanation/http-model.md)
