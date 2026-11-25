---
description: Créer un projet hecate, installer ses dépendances, l’exécuter, le tester, exporter son contrat, construire sa documentation et garder ses dépendances à jour, le tout avec la commande hecate.
hecate: "0.x"
lua: "5.5"
order: 5
source_revision: 57ace85c67235547aa716c4fcac0d2c745f00057
---

# Créer et exécuter un projet

Ce guide mène un nouveau projet de rien à une API testée et documentée avec la [commande `hecate`](../reference/cli.md).
Il est écrit pour hecate 0.x et Lua 5.5. Vous n’avez besoin que de l’exécutable `hecate` : ni Lua, ni LuaRocks.

## Le créer

```sh
hecate new shop
cd shop
hecate install
```

`hecate new` écrit un projet avec un contrôle de santé et une ressource `items` : `hecate.project.lua` (le manifeste),
`main.lua` (démarre l’application), `src/shop/` (l’application, ses schémas et ses routes), `tests/`, `config/` et
`docs/`. `hecate install` place les dépendances dans `lua_modules` et écrit `hecate.lock` ; versionnez le verrou, et
utilisez `hecate install --frozen` en CI pour obtenir exactement ce qu’il dit.

## L’exécuter et le tester

```sh
hecate test
hecate serve --env development
```

`hecate test` exécute `tests/` avec les modules du projet sur le chemin de recherche ; `--jobs 4` exécute les fichiers
dans quatre processus workers. `hecate serve` exécute `main.lua` (port lu dans `PORT`, 8080 par défaut) et s’arrête en
douceur sur Ctrl+C. `--env development` choisit l’environnement de [configuration](../../en/how-to/configure-an-application.md) : les
fichiers générés `config/development.lua` et `config/test.lua` n’exécutent qu’un processus, alors que l’environnement
`production`, par défaut, démarre un worker par cœur moins un (`--workers 2` choisit le nombre). `--watch` redémarre
l’application lorsque les sources changent.

## Vérifier le contrat

```sh
hecate contract export --output openapi.json
hecate contract lint openapi.json
hecate generate meta
```

La première commande écrit le [contrat](../../en/how-to/serve-and-export-the-contract.md) de l’application (la section `contract` du
manifeste donne son titre et sa version), la deuxième l’analyse et sort avec `1` sur une erreur. Versionnez
`openapi.json` et `hecate contract diff <ref>` vous dit ce qu’un changement a cassé depuis cette référence git.
`hecate generate meta` écrit `meta/shop.schemas.lua`, le fichier de déclarations qui permet à un éditeur de connaître
les types des schémas.

## Construire la documentation

```sh
hecate doc build --yes
```

Le site va dans `docs/dist` : un dossier de fichiers statiques par audience, construit à partir des pages Markdown de
`docs/` et de la référence de code de `src/`. Les fichiers n’ont besoin d’aucun serveur : ouvrez `docs/dist/index.html`
depuis le système de fichiers, ou publiez le dossier sur n’importe quel hébergeur statique. La référence de code exécute
LuaLS, qui exécute le greffon que sa configuration déclare : ne construisez qu’un projet de confiance, et répondez à la
question (ou passez `--yes`) en connaissance de cause.

## Garder les dépendances à jour

```sh
hecate add plc@"~> 0.5"
hecate outdated
hecate update
```

`add` et `remove` modifient le manifeste et le verrou ; `outdated` liste les rocks qui ont une version plus récente et
indique si vos contraintes l’autorisent ; `update` prend les versions les plus récentes qu’elles autorisent. Pour livrer
le résultat sur un serveur, voir [Livrer sur un serveur](deliver-to-a-server.md).
