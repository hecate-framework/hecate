---
description: Les commandes de l’exécutable hecate : ce que fait chacune, ses options et ses codes de sortie.
hecate: "0.x"
lua: "5.5"
order: 5
source_revision: 57ace85c67235547aa716c4fcac0d2c745f00057
---

# La commande `hecate`

`hecate` est un exécutable unique qui embarque Lua 5.5, LuaRocks et ce dont la ligne de commande a besoin. C’est
l’interpréteur d’un projet Lua 5.5 : il exécute le code du projet dans un processus enfant, avec les modules du projet
sur le chemin de recherche, si bien qu’une machine n’a besoin ni de Lua ni de LuaRocks. Cette page liste les commandes ;
`hecate <commande> --help` affiche les options de l’une d’elles, et chaque commande accepte `--json` pour un résultat
lisible par une machine. Un statut de sortie `0` signifie le succès, `1` un échec de la commande ou de ce qu’elle a
exécuté, et `2` une erreur d’usage.

## Projets

| Commande | Ce qu’elle fait |
|---|---|
| `hecate new <name> [--template api\|minimal]` | Crée le répertoire `<name>` à partir d’un modèle et refuse un répertoire qui existe. `api` (par défaut) est un contrôle de santé et une ressource avec ses schémas, son module de routes et ses tests ; `minimal` est le contrôle de santé seul. Les deux écrivent le manifeste (avec la disposition `doc`), `main.lua`, `config/development.lua` et `config/test.lua`, les tests et une première page de documentation. |
| `hecate init [--name <name>]` | Ajoute le modèle `minimal` au répertoire courant, en conservant chaque fichier existant. |
| `hecate doctor` | Vérifie l’environnement : Lua, LuaRocks, libuv, les modules natifs, un compilateur C. |
| `hecate version` | Affiche les versions de Hecate, Lua, LuaRocks et libuv, ainsi que la plateforme. |
| `hecate completion bash\|zsh\|fish\|powershell` | Affiche le script de complétion d’un interpréteur de commandes. |

## Dépendances

Les dépendances d’un projet sont des rocks, listés dans `hecate.project.lua` et verrouillés dans `hecate.lock` (versionnez-le).

| Commande | Ce qu’elle fait |
|---|---|
| `hecate install [--frozen]` | Installe les dépendances dans `lua_modules` et écrit `hecate.lock`. Avec `--frozen`, elle installe exactement ce que dit le verrou et échoue lorsque le manifeste et le verrou diffèrent, ou lorsqu’un fichier installé diffère de sa somme de contrôle enregistrée. Les rocks avec du code C se compilent avec les en-têtes du Lua embarqué : aucun Lua du système n’est nécessaire. |
| `hecate add <rock>[@constraint] [--dev]` | Ajoute une dépendance au manifeste (la contrainte vaut par défaut `~> major.minor` de la version installée ; `--dev` l’ajoute à `development_dependencies`), l’installe et met à jour le verrou. |
| `hecate remove <rock>` | Retire une dépendance du manifeste et met à jour le verrou. |
| `hecate outdated` | Liste les rocks qui ont une version plus récente et indique si la contrainte du manifeste l’autorise. |
| `hecate update [<rock>]` | Prend les versions les plus récentes que les contraintes autorisent et réécrit le verrou. |

`rocks_servers` dans le manifeste liste des serveurs LuaRocks supplémentaires, consultés avant luarocks.org.

## Exécuter et tester

| Commande | Ce qu’elle fait |
|---|---|
| `hecate serve [--watch] [--workers <n>] [--env <name>]` | Exécute `main.lua` dans un processus enfant. `--watch` le redémarre lorsqu’un fichier `.lua` de `src`, de `config` ou `main.lua` change. `--workers` définit `HECATE_SERVER__WORKERS` (un nombre ou `auto`) ; `--env` définit `HECATE_ENV` (par exemple `development` ; sans lui, la variable est laissée telle quelle, et l’environnement est alors `production`). Ctrl+C et `SIGTERM` arrêtent l’application en douceur. |
| `hecate run <script> [--env <name>] [-- <arguments>]` | Exécute un script du projet : un nom de `scripts` dans le manifeste, ou un fichier `.lua` du projet. Les arguments qui lui sont destinés suivent `--`. |
| `hecate test [<path>...] [--filter <pattern>] [--case <name>] [--tag <tag>] [--exclude-tag <tag>] [--jobs <n>]` | Exécute les tests du projet (par défaut `tests/`) avec les dépendances du projet sur le chemin des modules. `--jobs` exécute les fichiers de test dans ce nombre de processus workers. |

## Contrat et documentation

| Commande | Ce qu’elle fait |
|---|---|
| `hecate contract export [--output <file>] [--pretty]` | Écrit le document OpenAPI 3.1 de l’application (le module nommé comme le projet doit avoir `application(options)` ; la section `contract` du manifeste donne le titre et la version). |
| `hecate contract lint <file>` | Analyse un document OpenAPI ; sortie `1` sur un constat de niveau erreur. |
| `hecate contract diff <old> <new>` ou `<ref>` | Liste les changements entre deux documents, ou entre le `openapi.json` d’une référence git (lu avec `git show` ; `--file` nomme un autre fichier) et l’application telle qu’elle est maintenant ; sortie `1` sur un changement incompatible. |
| `hecate doc build [--audience <name>] [--output <dir>] [--yes]` | Construit le site de documentation du projet dans `docs/dist`. Lorsque le projet demande une référence de code, LuaLS exécute les greffons que sa configuration déclare : la commande demande donc d’abord confirmation (`--yes` répond pour la CI). |
| `hecate generate meta [--namespace <name>] [--output <file>] [--force]` | Écrit le fichier de déclarations LuaLS des schémas du contrat, `meta/<module>.schemas.lua` par défaut ; listez `meta` dans `workspace.library` de `.luarc.json`. |

## Livraison

| Commande | Ce qu’elle fait |
|---|---|
| `hecate package [--output <file>]` | Écrit l’archive de livraison du projet et son `.sha256` : le manifeste, le verrou, `main.lua`, `src`, `config`, `lua_modules` et un fichier `RELEASE`. Exécutez d’abord `hecate install --frozen`, sur la plateforme du serveur. Voir [Livrer sur un serveur](../how-to/deliver-to-a-server.md). |
| `hecate generate systemd [--user <name>] [--workers <n>] [--working-directory <dir>] [--environment-file <file>] [--executable <path>] [--output <file>] [--force]` | Affiche, ou écrit, l’unité systemd qui exécute `hecate serve` : elle s’arrête sur `SIGTERM` et recharge sur `SIGHUP`. `--working-directory` et `--environment-file` sont des chemins sur le serveur (absolus) ; une valeur contenant un saut de ligne est refusée. |

## Le manifeste

`hecate.project.lua` est un fichier Lua qui renvoie une table, lu sans aucune variable globale. Ses clés : `name`,
`version`, `description`, `license`, `lua`, `dependencies`, `development_dependencies`, `scripts`, `rocks_servers`,
`contract` (`title`, `version`, `servers`) et `doc` (`guides_dir`, `output_dir`, `sources_dir`, `package_name`,
`site_configuration_path`). Voir [Créer et exécuter un projet](../how-to/create-and-run-a-project.md) pour une visite
guidée.
