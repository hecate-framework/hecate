---
title: Référence
description: La référence de hecate : la référence de code générée de chaque paquet et le glossaire.
hecate: "0.x"
lua: "5.5"
order: 0
source_revision: 79f332b
---

# Référence

La référence de code est générée à partir des annotations des sources. Une section existe pour
chaque paquet documenté.

- [`hecate.core`](core/index.md) : modèle objet, erreurs.
- [`hecate.reactor`](reactor/index.md) : coroutines, futures, concurrence structurée, minuteurs,
  signaux, processus, système de fichiers, TCP, UDP, tubes et résolution de noms.
- [`hecate.net`](net/index.md) : flux, TCP, UDP, tubes, résolution de noms, TLS et couche
  tamponnée.
- [`hecate.json`](json/index.md) : encodage, décodage, marqueurs et erreurs.
- [`hecate.log`](log/index.md) : enregistrements structurés, gravités de la RFC 5424, contexte et puits.
- [`hecate.http`](http/index.md) : le serveur et le client HTTP/1.1, les messages, les flux de contenu, les formulaires et les détails de problème.
- [`hecate.router`](router/index.md) : le routeur à arbre radix, les gabarits de chemin, l’appariement, le routage inverse et les erreurs de table de routes.
- [`hecate.schema`](schema/index.md) : types raffinés, validation, coercition et émission de JSON Schema.
- [`hecate.openapi`](openapi/index.md) : le document OpenAPI 3.1 assemblé à partir de la table de routes, son encodage canonique, le contrôle de style et la comparaison des ruptures de compatibilité.
- [`hecate.container`](container/index.md) : le conteneur d’inversion de contrôle, les durées de vie, l’injection par constructeur, la validation au démarrage et la libération.
- [`hecate.config`](config/index.md) : la configuration en couches validée par des schémas, les variables d’environnement, les secrets et la `Configuration` immuable.
- [`hecate.kernel`](kernel/index.md) : l’application, les modules fonctionnels, les contrôleurs, les modules de routes, les filtres, les détails de problème, le superviseur et les stratégies d’écoute du service multi-processus.
- [`hecate.test`](test/index.md) : le cadre de test xUnit : cas, suites, fixtures, assertions, client HTTP en processus, tests fondés sur des propriétés et couverture.
- [`hecate`](hecate/index.md) : le méta-module qui réexporte la surface du cadre pour les applications, et les noms de types qui les annotent.
- [`hecate.unicode`](unicode/index.md) : normalisation Unicode des chaînes UTF-8, NFC et NFD, et version d’Unicode utilisée.
- [`hecate.unicode_data`](unicode-data/index.md) : les tables générées de la base de caractères Unicode derrière `hecate.unicode`, versionnées par la version d’Unicode.
- [`hecate.doc`](doc/index.md) : le générateur de documentation et de site statique, et la génération de la documentation d’un projet.

Deux pages sont générées à partir des sources et des spécifications (en anglais pour l’instant) :

- Codes d’erreur : chaque classe d’erreur, son code stable, son parent et les valeurs de `context.reason`.
- Clés de configuration : les clés que toute configuration déclare, leur type, valeur par défaut, valeurs admises, variable d’environnement et signification.

Pages rédigées à la main :

- [Documentation d’un projet](project-documentation.md) : les pages générées pour un projet utilisateur, les fichiers meta de LuaLS, les points d’extension du thème et `llms.txt`.
- [La commande `hecate`](cli.md) : la référence de l’exécutable.
- Mots-clés et formats de schéma, jetons de thème : en anglais seulement pour l’instant.

Le [glossaire](glossary.md) définit le vocabulaire utilisé partout.
