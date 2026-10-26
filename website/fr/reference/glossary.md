---
description: Le vocabulaire de hecate, tiré de la littérature académique, et les termes qu’il remplace.
hecate: "0.x"
lua: "5.5"
order: 1
source_revision: cba7be6
---

<!-- Public version of docs/glossary.md, adapted for the website (the name is never
     capitalised, links point to the repository). Keep it in step with the source. -->
<!-- French version: each term is given in French with its English term in parentheses; the
     English term is the identifier or the reference. Decisions: website/fr/glossary-terms.md. -->

# Glossaire

hecate nomme les choses d’après la littérature académique plutôt que d’après les idiomes d’autres
langages ([ADR 0004](https://github.com/hecate-framework/hecate/blob/main/docs/adr/0004-academic-vocabulary.md)).
Ce glossaire est **obligatoire** pour les API publiques, la documentation et le code interne.
Les identifiants et les termes de la colonne « À la place de » restent en anglais.

## Règles {#rules}

1. Préférer le terme établi dans la littérature à un terme popularisé par un langage ou un cadre
   applicatif (`future`, pas `promise` ; `fork`/`join`, pas `spawn`/`all`).
2. **Les normes l’emportent.** Quand une RFC ou une spécification que nous implémentons définit un
   terme, on l’utilise : sémantique HTTP (RFC 9110), détails de problème (RFC 9457), JSON Pointer
   (RFC 6901), gabarits d’URI (RFC 6570), JSON Schema 2020-12, OpenAPI 3.1, SQL.
3. Quand un terme théorique entre en collision avec un sens pratique très répandu (la *sélection*
   de l’algèbre relationnelle face au `SELECT` de SQL), on utilise le terme théorique et on
   documente la correspondance de façon visible (voir « Algèbre relationnelle et SQL »
   ci-dessous).
4. Les identifiants sont en anglais, en `snake_case` pour les fonctions, méthodes, champs et
   modules, en `PascalCase` pour les classes, interfaces et traits.

## Concurrence {#concurrency}

| Terme | Signification | Référence | À la place de |
|---|---|---|---|
| coroutine (*coroutine*) | La coroutine native de Lua, asymétrique et avec pile ; l’unité d’exécution | de Moura & Ierusalimschy, *Revisiting Coroutines* (2009) | fiber, green thread |
| réacteur (*reactor*) | Démultiplexeur d’événements qui distribue la disponibilité ou l’achèvement des entrées-sorties à des gestionnaires | Schmidt, patron *Reactor* (1995) | event loop (acceptable en prose) |
| future (*future*) | Réceptacle d’une valeur produite par un calcul concurrent | Baker & Hewitt (1977) ; Friedman & Wise (1976) | promise, task |
| fork (*fork*) | Démarrer un calcul concurrent, en renvoyant une future | Conway (1963) | spawn, go, launch |
| lancer (*spawn*) | Démarrer un processus du système d’exploitation (`reactor.spawn`) ; jamais une coroutine, qui relève de `fork` | POSIX `posix_spawn` ; ADR 0023 | spawn pour une coroutine |
| join (*join*) | Attendre une ou plusieurs futures | Conway (1963) | await all, gather, Promise.all |
| select (*select*) | Attendre que la première de plusieurs alternatives soit prête | Hoare, CSP (1978) ; Dijkstra, commandes gardées (1975) | race, any |
| échéance (*deadline*) | Borne absolue sur l’achèvement d’un calcul | — | timeout (un délai est une durée relative ; les deux peuvent être acceptés comme arguments) |
| flux (*stream*) | Suite ordonnée d’octets lus, écrits et fermés dans l’ordre, sur un fichier, une connexion ou un autre flux | Ritchie, *A Stream Input-Output System* (1984) | socket (pour les transports qui ne sont pas des sockets), channel (un canal transporte des valeurs entre coroutines) |
| contre-pression (*back-pressure*) | Un producteur se suspend tant que son consommateur est plus lent, au lieu de mettre en tampon sans borne | spécification *Reactive Streams* (2015) | throttling, rate limiting |
| fermeture partielle (*half-close*) | Terminer une direction d’une connexion pendant que l’autre reste utilisable (`shutdown`) | RFC 9293, section 3.6 | — |
| primaire (*primary*) | Le processus qui démarre, supervise et, pour certaines stratégies, alimente les workers | Buschmann et al., *Pattern-Oriented Software Architecture* vol. 1 (1996), patron Master-Slave | master, parent (pour la relation du système d’exploitation, « processus parent » est accepté) |
| worker (*worker*) | Un processus avec son propre réacteur qui sert des requêtes ; les workers ne partagent rien | Buschmann et al. (1996), patron Master-Slave | slave, child process (pour la relation du système d’exploitation) |
| tube de messages (*message pipe*) | Une connexion à trames entre deux processus qui transporte des messages sous forme de chaînes et, facultativement, un handle de flux (`reactor.ipc`). À ne pas confondre avec `PipeStream`, un socket de flux local (socket de domaine Unix, tube nommé sous Windows) | POSIX `pipe(2)` ; ADR 0023 | channel (réservé à la communication entre coroutines) |
| pair (*peer*) | L’extrémité distante d’une connexion (`peer_address`) ou d’un tube de messages (`Peer`) | RFC 9293 | remote (dans « remote address »), client (quand le rôle est inconnu) |
| stratégie d’écoute (*listening strategy*) | La façon dont les workers obtiennent leurs connexions : `reuseport` ou `round_robin` ([ADR 0023](https://github.com/hecate-framework/hecate/blob/main/docs/adr/0023-multi-process-serving.md)) | — | cluster mode |
| calcul (*computation*) | Une unité en cours d’exécution du planificateur : une coroutine démarrée avec `fork` ou `detach`, ou la coroutine principale ; ce que possède une portée et ce que représente une future | `concurrency.md` | task |
| point de suspension (*suspension point*, suspendre) | Un appel où la coroutine en cours cède la main au réacteur : toute opération d’entrée-sortie et toute primitive de `hecate.reactor`. Un appel suspendu ne bloque pas le réacteur | `concurrency.md` | blocking, async |
| annulation (*cancellation*) | Demande coopérative d’arrêter un calcul | — | abort, kill |
| portée (*scope*) | Région de concurrence structurée qui possède les calculs démarrés avec `fork` | Sústrik (2016) ; Smith, *nursery* (2018) | task group, nursery |
| canal (*channel*) | Communication typée entre coroutines | Hoare, CSP (1978) | queue (quand elle sert à communiquer) |
| sémaphore (*semaphore*) | Primitive de synchronisation à compteur | Dijkstra (1965) | limiter |
| mutex (*mutex*) | Verrou d’exclusion mutuelle | Dijkstra (1965) | lock (acceptable en prose) |
| moniteur (*monitor*) | Mutex avec variables de condition | Hoare (1974) ; Brinch Hansen (1973) | — |
| condition (*condition*) | Variable de condition attachée à un moniteur | Hoare (1974) | event, signal |

## Modèle objet et architecture {#object-model-and-architecture}

| Terme | Signification | Référence | À la place de |
|---|---|---|---|
| classe (*class*) | Gabarit d’objets au comportement partagé | — | — |
| trait (*trait*) | Ensemble réutilisable de méthodes composé dans une classe, avec résolution explicite des conflits | Schärli, Ducasse, Nierstrasz, Black (2003) | mixin (sauf si des mixins linéarisés sont visés), concern |
| interface (*interface*) | Ensemble de signatures de méthodes requises, dont la conformité est vérifiée | — | protocol (acceptable), contract (réservé aux contrats d’API) |
| finalisation (*finalisation*) | Étape qui résout la composition des traits et la conformité aux interfaces, puis aplatit les membres dans la table de la classe | Schärli et al. (2003) | build, seal, compile |
| conformité (*conformance*) | Une classe fournit chaque méthode qu’exige une interface | — | compliance |
| superclasse (*superclass*) | Classe dont une classe hérite (héritage simple) | — | parent class, base class |
| énumération (*enumeration*) | Ensemble fermé et nommé de valeurs | — | enum |
| chaîne de causes (*cause chain*) | Erreurs liées par `cause`, rendues par `__tostring` | — | — |
| inversion de contrôle (*inversion of control*) | Le cadre applicatif appelle le code de l’utilisateur | Fowler (2004) | — |
| conteneur (*container*) | Objet qui résout et construit des dépendances | Fowler (2004) | service locator (un anti-patron, pas un synonyme) |
| service (*service*) | Un objet enregistré dans le conteneur et résolu par lui | Fowler (2004) | bean, provider |
| action (*action*) | La méthode de contrôleur ou la fonction qu’invoque une route ; ce que les filtres enveloppent. « Gestionnaire » (*handler*) est réservé aux gestionnaires d’achèvement d’E/S du réacteur | `http-and-routing.md` | handler |
| contrôleur, module de routes, module fonctionnel (*controller, route module, feature module*) | Les deux styles de déclaration de routes (une classe d’actions, ou `hecate.routes(name)`) et le regroupement que fait le noyau en module fonctionnel ([ADR 0006](https://github.com/hecate-framework/hecate/blob/main/docs/adr/0006-declarative-routes-as-runtime-data.md)) | ADR 0006 ; `http-and-routing.md` | router group, blueprint, plugin ; « module » seul, ambigu avec un module Lua |
| chaîne de responsabilité (*chain of responsibility*) | Gestionnaires ordonnés autour d’une action | Gamma et al. (1994) | middleware stack |
| filtre (*filter*) | Un élément de la chaîne autour d’une action | — | middleware |
| racine de composition (*composition root*) | Lieu unique où le graphe d’objets est assemblé | Seemann (2011) | bootstrap file |
| entité (*entity*) | Une classe dont les instances ont une identité et sont persistées par un data mapper | Evans (2003) | model, record |
| objet-valeur (*value object*) | Objet immuable comparé par valeur | Evans (2003) | DTO (quand l’immuabilité est visée) |
| représentation (*representation*) | La forme transférable de l’état d’une ressource | Fielding (2000) ; RFC 9110 | DTO, view model |

## Données {#data}

| Terme | Signification | Référence | À la place de |
|---|---|---|---|
| relation (*relation*) | Ensemble de n-uplets sur un en-tête d’attributs | Codd (1970) | table (dans l’API de l’ORM ; « table » reste correct pour le DDL SQL) |
| n-uplet (*tuple*) | Élément d’une relation | Codd (1970) | row, record |
| attribut (*attribute*) | Composant nommé et typé d’un en-tête | Codd (1970) | column, field (dans les métadonnées de mappage) |
| prédicat (*predicate*) | Condition booléenne sur des n-uplets | Codd (1970) | where clause |
| projection (*projection*, π) | Restriction à un sous-ensemble d’attributs | Codd (1970) | select columns |
| sélection / restriction (*selection / restriction*, σ) | Restriction aux n-uplets qui satisfont un prédicat | Codd (1970) | where / filter |
| jointure (*join*, ⋈) | Combinaison de relations selon un prédicat | Codd (1970) | — |
| data mapper (*data mapper*) | Déplace des données entre des objets et une base de données, en les gardant indépendants | Fowler, *PoEAA* (2002) | — |
| unité de travail (*unit of work*) | Suit les changements pendant une transaction métier et les valide de façon atomique | Fowler, *PoEAA* (2002) | session, entity manager |
| table d’identités (*identity map*) | Garantit que chaque n-uplet est chargé une seule fois par unité de travail | Fowler, *PoEAA* (2002) | cache |
| dépôt (*repository*) | Accès aux agrégats à la manière d’une collection | Evans (2003) ; Fowler (2002) | DAO |
| schéma de base de données (*database schema*) | Les relations, contraintes et index d’une base de données (DDL SQL) ; pas une déclaration de type de `hecate.schema` | ISO/IEC 9075 | schema (seul, dans l’accès aux données) |
| migration (*migration*) | Transformation de schéma versionnée et réversible | — | — |
| pool de connexions (*connection pool*) | Ensemble borné de connexions réutilisables | — | — |

### Algèbre relationnelle et SQL {#relational-algebra-and-sql}

| Algèbre relationnelle (API de hecate) | SQL |
|---|---|
| `projection` | `SELECT a, b` |
| `selection` (aussi `restriction`) | `WHERE ...` |
| `join` | `JOIN ... ON ...` |
| `rename` (ρ) | `AS` |
| `union`, `intersection`, `difference` | `UNION`, `INTERSECT`, `EXCEPT` |

Ce tableau figure en tête des pages de référence `query` et `orm`.

## Types et validation {#types-and-validation}

| Terme | Signification | Référence | À la place de |
|---|---|---|---|
| type raffiné (*refinement type*) | Un type de base restreint par des prédicats (`integer` avec `minimum = 1`) | Freeman & Pfenning (1991) | constrained type, validator |
| type somme / union étiquetée (*sum type / tagged union*) | Valeur qui est exactement l’une de plusieurs variantes | — | discriminated union (acceptable, terme d’OpenAPI) |
| type produit (*product type*) | Enregistrement de composants nommés | — | — |
| coercition (*coercion*) | Conversion d’une entrée textuelle en valeur typée | — | casting, parsing (quand la coercition est visée) |
| schéma (*schema*) | Déclaration d’un type utilisable pour la validation, la coercition et l’émission de contrats | JSON Schema 2020-12 | model, DTO |

Les mots-clés de schéma suivent le vocabulaire de JSON Schema 2020-12 en `snake_case` :
`minimum`, `maximum`, `exclusive_minimum`, `multiple_of`, `min_length`, `max_length`, `pattern`,
`format`, `min_items`, `max_items`, `unique_items`, `enum`, `const`.

## HTTP {#http}

Les termes de la RFC 9110 sont utilisés tels que définis : *resource* (ressource),
*representation* (représentation), *method* (méthode), *status code* (code d’état), *field*
(champ d’en-tête), *content* (contenu du message), *media type* (type de média). Les erreurs sont
des *problem details* (détails de problème, RFC 9457 ; `hecate.problem.*` est l’espace de noms). Les paramètres de chemin suivent la syntaxe des gabarits d’URI
(RFC 6570, sous-ensemble de niveau 1).

## Journalisation {#logging}

Les gravités (*severities*) suivent la RFC 5424 : `emergency`, `alert`, `critical`, `error`, `warning`,
`notice`, `informational`, `debug`. Un journaliseur enregistre les gravités au moins aussi élevées que son
option `severity` (jamais « niveau » ni « seuil »).
