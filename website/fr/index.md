---
description: Un cadre applicatif modulaire, piloté par contrat, pour les API web en Lua 5.5.
hecate: "0.x"
lua: "5.5"
layout: home
source_revision: f1f3b5e
actions: ["Guides pratiques | how-to/ | primary", "Explications | explanation/", "Lire le glossaire | reference/glossary", "Code source | https://github.com/hecate-framework/hecate"]
---

# hecate

hecate est un écosystème complet pour construire des API HTTP en Lua : un environnement
d’exécution asynchrone, un serveur HTTP, un routeur, des schémas et la validation, des contrats
OpenAPI automatiques, un cadre de test, un générateur de documentation, des pilotes de bases de
données, un mappeur objet-relationnel et un outil en ligne de commande.

> [!NOTE] État d’avancement
> Les paquets core, reactor, net, json et log sont implémentés et documentés, de même que le
> générateur qui construit ce site. Voir les [guides pratiques](how-to/index.md), les
> [explications](explanation/index.md) et la [référence](reference/index.md) générée. Tout le reste
> est encore spécifié et non implémenté. Ce site grandit avec le code, paquet par paquet.

## Principes

- **Un seul cadre, pas un assemblage.** Chaque composant partage le modèle objet, le modèle
  d’erreurs, la nomenclature et le cycle de publication.
- **Contrat d’abord.** Une route et ses schémas sont déclarés une seule fois, sous forme de
  données à l’exécution. La validation, les contrats OpenAPI, la documentation de l’API et les
  tests de contrat en découlent.
- **Concurrence transparente.** Les gestionnaires se lisent comme du code séquentiel. Les
  entrées et sorties suspendent la coroutine en cours d’exécution.
