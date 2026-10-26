---
title: La concurrence dans hecate
description: Comment les calculs lancés, les futures et les portées s'articulent.
hecate: "0.x"
lua: "5.5"
order: 2
source_revision: 82e2890
---

hecate exécute de nombreuses **coroutines** sur un **réacteur**. Un appel suspendant
comme `sleep` met la coroutine en pause pendant que les autres avancent.

## Les trois idées

- Une **future** est le résultat à venir d'un calcul.
- `fork` lance un calcul et renvoie sa future.

> [!TIP]
> Voir la [page elle-même](concurrency.md).
