---
description: Ce qui arrive à une requête HTTP dans hecate, de la connexion lue par le réacteur à la réponse écrite - filtres, routage, validation, l’action et la sérialisation.
hecate: "0.x"
lua: "5.5"
order: 9
source_revision: fafa8c2
---

# La vie d’une requête

Cette page suit une requête à travers le framework. Elle est écrite pour hecate 0.x et Lua 5.5. L’organisation des paquets en couches est expliquée dans [Architecture et couches](../../../../maintainer/en/explanation/architecture-and-layers/), sur le site des mainteneurs.

1. Le réacteur signale qu’une connexion est lisible. `http.Server` analyse la tête de la requête avec llhttp.
2. Le serveur exécute l’action de l’application dans une nouvelle [coroutine](../reference/glossary.md#concurrency), à
   l’intérieur d’une [portée](../reference/glossary.md#concurrency) propre à cette requête.
3. Les [filtres](../reference/glossary.md#object-model-and-architecture) globaux de l’application s’exécutent.
4. À l’intérieur de ceux-ci, la garde intercepte les erreurs, et le routeur fait correspondre la méthode et le chemin.
   Une requête qui ne correspond à rien reçoit une réponse de détails de problème `404`, `405` ou `400`, qui remonte à
   travers les filtres globaux.
5. Les filtres du module fonctionnel, du contrôleur et de la route s’exécutent.
6. Le noyau (`kernel`) coerce et valide les paramètres de chemin, la requête, les champs d’en-tête, les cookies et le
   contenu par rapport aux schémas de la route. Un échec donne une réponse de détails de problème `422`.
7. L’[action](../reference/glossary.md#object-model-and-architecture) s’exécute : une méthode de contrôleur ou une
   fonction. Elle renvoie une valeur, une `Response` ou un problème.
8. Le noyau sérialise le résultat en une
   [représentation](../reference/glossary.md#object-model-and-architecture), en la validant par rapport au schéma de
   réponse en développement et en test.
9. Le serveur écrit la réponse. L’écriture se suspend jusqu’à ce que les octets soient remis au système.

Les entrées sont validées après les filtres, juste avant l’action : un filtre qui refuse une requête (l’authentification,
par exemple) ne coûte aucune lecture de son contenu. La portée de la requête ne se termine pas avant que tous les calculs
démarrés avec `fork` pendant le traitement de la requête soient terminés : un travail d’arrière-plan ne peut donc pas
survivre à sa requête sans qu’on le remarque.

[Filtres](../../../../user/en/how-to/filters/) et [Faire correspondre les erreurs du domaine à des détails de problème](../../../../user/en/how-to/map-domain-errors-to-problem-details/)
montrent les étapes 3 à 8 en pratique.
