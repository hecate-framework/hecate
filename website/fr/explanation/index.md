---
title: Explications
description: Les concepts et les raisons de conception de hecate, écrits pour hecate 0.x et Lua 5.5.
hecate: "0.x"
lua: "5.5"
order: 0
source_revision: cba7be6
---

# Explications

Ces pages expliquent comment hecate fonctionne et pourquoi il est conçu ainsi. Elles ne donnent
pas de recettes : les [guides pratiques](../how-to/index.md) en donnent.

- [Le modèle de transport](transport-model.md) : flux, suspension plutôt que rappels,
  contre-pression, fermeture partielle, tampons et annulation.
- [Confiance TLS et valeurs par défaut de sécurité](tls-trust-and-security.md) : pourquoi le
  vérificateur du système d’exploitation, ce qui ne peut pas être désactivé, et les réserves
  propres à chaque plateforme.
- [Service multiprocessus](multi-process-serving.md) : workers sans état partagé, stratégies
  d’écoute et tube de messages, et ce qui existe aujourd’hui.

Le vocabulaire est défini dans le [glossaire](../reference/glossary.md).
