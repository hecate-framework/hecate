---
description: Configurer une application avec hecate.config - couches, variables d’environnement, secrets, validation au démarrage et clés du framework pour la journalisation, la profondeur et l’arrêt.
hecate: "0.x"
lua: "5.5"
order: 8
source_revision: 127cb3d2f023c24467492b8959dd7bc7bc0390d7
---

# Configurer une application

Ce guide montre comment charger la configuration d’un processus avec `hecate.config`. Il est écrit pour hecate 0.x et
Lua 5.5.

La [configuration](../../../../user/en/reference/glossary/#configuration) (*configuration*) est l’arbre clé-valeur
immuable et validé avec lequel un processus démarre. Elle est lue une fois au démarrage, validée par un schéma, puis
figée. La spécification est
[configuration.md](https://github.com/hecate-framework/hecate/blob/main/docs/architecture/configuration.md).

## Déclarer les clés et charger {#declare-the-keys-and-load}

Déclarez les clés de votre application comme des schémas, puis appelez `config.load`. Voici une section de base de
données lue depuis deux fichiers et une variable d’environnement :

<!-- example: packages/config/examples/hecate.config.load.lua -->
```lua
-- Layers in increasing precedence: the schema default, config/default.lua,
-- config/production.lua, an environment variable. The password is a secret:
-- it is wrapped and never printed. The file system and the environment are
-- replaced by tables here; by default `load` reads the real ones.
local config = require("hecate.config")
local schema = require("hecate.schema")

local files = {
  ["config/default.lua"] = "return { database = { host = 'localhost', port = 5433 } }",
  ["config/production.lua"] = "return { database = { host = 'db.internal' } }",
}
local environment = { HECATE_ENV = "production", HECATE_DATABASE__PASSWORD = "s3cr3t" }

local configuration = config.load({
  properties = {
    database = schema.object({
      host = schema.string(),
      port = schema.default(schema.integer({ minimum = 1, maximum = 65535 }), 5432),
      password = schema.string(),
    }),
  },
  secrets = { "database.password" },
  getenv = function(name) return environment[name] end,
  read_file = function(path)
    if files[path] then return files[path] end
    return nil, "no such file", true
  end,
})

print(configuration:get("database.host"), configuration:source("database.host"))
-- Prints: db.internal	config/production.lua
print(configuration:get("database.port"), configuration:source("database.port"))
-- Prints: 5433	config/default.lua
print(tostring(configuration:get("database.password")), configuration:get("database.password"):reveal() == "s3cr3t")
-- Prints: [redacted]	true
local database = configuration:get("database")
print(tostring(select(2, pcall(function() database.port = 1 end))):match("immutable"))
-- Prints: immutable
```

La configuration est fusionnée à partir de
[couches de configuration](../../../../user/en/reference/glossary/#configuration) (*configuration layers*), les
sources de la fusion. De la plus faible à la plus forte :

1. les valeurs par défaut du schéma ;
2. `config/default.lua` ;
3. `config/<environment>.lua` ;
4. les variables d’environnement ;
5. les fichiers de secrets.

L’[environnement](../../../../user/en/reference/glossary/#configuration) (*environment*) est le nom du profil de
déploiement, tel que `development`, `test` ou `production`. Il sélectionne le fichier de la couche 3. Il est lu dans
`HECATE_ENV`, et vaut `production` par défaut.

## Écrire un fichier de configuration {#write-a-configuration-file}

Un fichier sous `config/` renvoie une table. Il est évalué dans une table `_ENV` vide : il n’a donc ni `require` ni
`os`.

Les couches fusionnent les tables clé par clé. Un tableau n’est pas fusionné : le tableau d’une couche plus tardive
remplace le précédent.

## Fixer une clé depuis une variable d’environnement {#set-a-key-from-an-environment-variable}

Le nom d’une [variable d’environnement](../../../../user/en/reference/glossary/#configuration) (*environment
variable*) est dérivé du chemin de sa clé : le préfixe (`HECATE`, option `env_prefix`), puis le chemin en majuscules
joint par deux tirets bas. `config.variable_name` le calcule :

```lua
local config = require("hecate.config")

print(config.variable_name("HECATE", { "database", "port" }))
-- Prints: HECATE_DATABASE__PORT
print(config.variable_name("HECATE", { "limits", "max_depth" }))
-- Prints: HECATE_LIMITS__MAX_DEPTH
```

Le texte de la variable est converti par le schéma de la clé :

- `"8080"` est un entier ;
- `"true"` est un booléen ;
- `"a,b"` est un tableau.

Un texte qui ne se convertit pas est signalé avec le nom de sa variable.

Les membres d’une table associative ne se configurent que par des fichiers.

## Garder les secrets hors de la sortie {#keep-secrets-out-of-the-output}

Listez les clés qui portent des secrets dans l’option `secrets`. Leurs valeurs sont enveloppées dans un
[objet secret](../../../../user/en/reference/glossary/#configuration) (*secret object*) :

- `tostring` donne `[redacted]` ;
- `reveal()` donne la valeur.

`configuration:describe()`, les messages d’erreur et les journaux ne les montrent jamais.

Un secret peut venir d’un [fichier de secret](../../../../user/en/reference/glossary/#configuration) (*secret file*),
un fichier qui contient la valeur d’une seule clé secrète. Il y a deux façons de le nommer :

- la variable `HECATE_DATABASE__PASSWORD_FILE` nomme le fichier de la clé `database.password` ;
- l’option `secrets_directory` nomme le répertoire où votre plateforme monte les secrets.

Passez `wrap_secret = log.Secret` pour que les destinations de journalisation reconnaissent l’enveloppe.

## Lire et diagnostiquer {#read-and-diagnose}

`configuration:get("database.port")` renvoie une valeur typée. `get` valide le chemin : un chemin que le schéma ne
déclare pas lève `ArgumentError`. `configuration:values()` donne la section racine, à lire champ par champ.

Deux méthodes aident au démarrage :

- `configuration:source(path)` dit quelle couche l’a emporté ;
- `configuration:describe()` est le texte à journaliser au démarrage.

Les clés inconnues sont des erreurs à toute profondeur. Une seule `ConfigurationError` liste chaque
[violation](../reference/glossary.md#types-and-validation) (*violation*), un motif pour lequel une valeur n’est pas
conforme à son schéma. Chaque ligne donne le chemin à points, le code et la couche :

```text
config.load: invalid configuration (2 problems, environment production)
  database.port: the text is not an integer [coercion] (environment variable HECATE_DATABASE__PORT)
  databse: the property is not declared [additional_properties] (config/production.lua)
```

`context.violations` contient aussi le JSON Pointer de chaque violation.

## Utiliser les clés du framework {#use-the-framework-keys}

Toute configuration a les clés ci-dessous. Le noyau applique les clés `logging.*` quand il construit les
journaliseurs.

| Clé | Défaut | Signification |
|---|---|---|
| `logging.severity` | `informational` | la gravité des journaliseurs |
| `logging.severities` | aucun | une gravité par nom de journaliseur |
| `logging.sinks` | `console` | parmi `console`, `json_lines` et `file` |
| `logging.file.path` | aucun | le fichier de la destination `file` |
| `logging.async` | `false` | envelopper chaque destination dans un `AsyncSink` |
| `logging.redact` | aucun | les noms de champs à masquer |
| `limits.max_depth` | 1000 | profondeur d’imbrication de `hecate.json` et `hecate.schema`, de 1 à 1000 |
| `server.grace_timeout` | 30 | secondes d’un arrêt en douceur |

Un projet peut abaisser `limits.max_depth`, jamais le relever.

`server.grace_timeout` (`HECATE_SERVER__GRACE_TIMEOUT`) est le temps qu’un arrêt en douceur laisse aux requêtes en
cours pour se terminer avant de les annuler. Gardez-le plus court que le délai d’arrêt du déploiement : `docker stop`
attend 10 s par défaut, Kubernetes 30 s.

Chaque clé et son défaut figurent dans [Clés de configuration](../reference/configuration-keys.md).
