---
title: Référence
description: La référence de hecate : la référence de code générée de chaque paquet et le glossaire.
hecate: "0.x"
lua: "5.5"
order: 0
source_revision: 9c2e1670e2e08b919db0b4399100c4b46c00a2a0
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
- [`hecate.router`](router/index.md) : le routeur à arbre radix, les gabarits de chemin, l’appariement, le routage inverse et les erreurs de table de routes.
- [`hecate.schema`](schema/index.md) : types raffinés, validation, coercition et émission de JSON Schema.
- [`hecate.container`](container/index.md) : le conteneur d’inversion de contrôle, les durées de vie, l’injection par constructeur, la validation au démarrage et la libération.
- [`hecate.config`](config/index.md) : la configuration en couches validée par des schémas, les variables d’environnement, les secrets et la `Configuration` immuable.

Le [glossaire](glossary.md) définit le vocabulaire utilisé partout.
