---
description: Un cadre applicatif modulaire, piloté par contrat, pour les API web en Lua 5.5.
hecate: "0.x"
lua: "5.5"
layout: home
source_revision: d18b73f
actions: ["Guides pratiques | how-to/ | primary", "Explications | explanation/", "Lire le glossaire | reference/glossary", "Code source | https://github.com/hecate-framework/hecate"]
---

# hecate

hecate est un écosystème complet pour construire des API HTTP en Lua : un environnement
d’exécution asynchrone, un serveur HTTP, un routeur, des schémas et la validation, des contrats
OpenAPI automatiques, un cadre de test, un générateur de documentation, des pilotes de bases de
données, un mappeur objet-relationnel et un outil en ligne de commande.

> [!NOTE] État d’avancement
> Les paquets core, reactor, net, json, log, http, router, schema, container, config et kernel sont
> implémentés et documentés, de même que le générateur qui construit ce site. Voir les
> [guides pratiques](how-to/index.md), les [explications](explanation/index.md) et la
> [référence](reference/index.md) générée. OpenAPI, le cadre de test, la CLI et l’accès aux données
> sont encore spécifiés et non implémentés. Ce site grandit avec le code, paquet par paquet.

## Principes

- **Un seul cadre, pas un assemblage.** Chaque composant partage le modèle objet, le modèle
  d’erreurs, la nomenclature et le cycle de publication.
- **Contrat d’abord.** Une route et ses schémas sont déclarés une seule fois, sous forme de
  données à l’exécution. La validation, les contrats OpenAPI, la documentation de l’API et les
  tests de contrat en découlent.
- **Concurrence transparente.** Les actions se lisent comme du code séquentiel. Les
  entrées et sorties suspendent la coroutine en cours d’exécution.
