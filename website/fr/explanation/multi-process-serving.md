---
description: La conception du service multiprocessus dans hecate (ADR 0023) : workers sans état partagé, un primaire, deux stratégies d’écoute et un tube de messages, et ce qui existe aujourd’hui.
hecate: "0.x"
lua: "5.5"
order: 3
source_revision: cc88cb1
---

# Service multiprocessus

Cette page explique comment hecate utilise plusieurs processus pour servir des requêtes, et
pourquoi. Elle est écrite pour hecate 0.x et Lua 5.5. La conception est l’ADR 0023 (acceptée le
2026-10-18).

> [!NOTE] Ce qui existe aujourd’hui
> Les primitives de `hecate.reactor` (`reactor.spawn`, `reactor.ipc`) et la politique de
> `hecate.kernel` existent : le superviseur, la stratégie `round_robin`, les clés `server.workers`
> et `server.strategy`, l’arrêt en douceur et le rechargement progressif. Deux éléments manquent.
> La stratégie `reuseport` est écrite mais attend la prise en charge par luv (OQ-43). Il n’y a pas
> encore de commande `hecate serve --workers` : une `Application` démarre elle-même ses workers.
> La section [Ce qui existe aujourd’hui](#what-exists-today) liste chaque élément.

## Pourquoi des processus

Un processus hecate exécute un état Lua et un [réacteur](../reference/glossary.md#concurrency)
(*reactor*). Ses coroutines partagent cet état et s’exécutent une à la fois. Pour utiliser
plusieurs cœurs de processeur, hecate lance plusieurs processus, pas plusieurs threads dans un
processus. Des threads exigeraient un état Lua chacun, chaque message entre eux demanderait une
sérialisation, et chaque module natif devrait être sûr vis-à-vis des threads.

Le service multiprocessus fait partie de la conception dès le départ. Il doit être rapide sous
Linux, où tourneront la plupart des serveurs. macOS et Windows doivent fonctionner et être
corrects, mais ils ne décident jamais de la conception du chemin Linux.

## Workers sans état partagé

Un serveur est un [primaire](../reference/glossary.md#concurrency) (*primary*) et *N*
[workers](../reference/glossary.md#concurrency). Un worker est le même programme relancé avec un
rôle de worker. Il a son propre état Lua, son propre réacteur et ses propres connexions. Par
défaut, *N* est le nombre de cœurs de processeur.

Rien n’est partagé entre les workers. L’état qui doit l’être vit hors des processus, dans une base
de données ou dans Redis. hecate n’offre aucune mémoire partagée.

Le primaire démarre les workers, attend que chacun dise qu’il est prêt, redémarre celui qui
plante, et les arrête. Une connexion reste sur le worker qui l’a prise. Cela équilibre le nombre
de *connexions*, mais pas la *charge* : un worker qui a plusieurs connexions de longue durée peut
être plus occupé que les autres.

## Mécanisme et politique

Le travail est réparti entre deux paquets.

- `hecate.reactor` contient le mécanisme, les primitives propres à chaque plateforme :
  `reactor.spawn`, `reactor.ipc` et l’option `reuseport`. Elles ne savent rien des serveurs.
- `hecate.kernel` contient la politique : le superviseur dans le primaire (démarrage,
  disponibilité, redémarrage avec recul exponentiel et limite de boucle de plantages, signaux,
  rechargement progressif, arrêt en douceur) et les stratégies d’écoute.

## Stratégies d’écoute

Une [stratégie d’écoute](../reference/glossary.md#concurrency) (*listening strategy*) décide d’où
un worker obtient ses connexions. C’est la seule partie de la conception qui dépend de la
plateforme. Tout ce qui est au-dessus, le serveur, le routeur et les actions, est identique
pour chaque stratégie. Il y en a deux.

| Stratégie | Qui accepte | Primaire sur le chemin des données | Par défaut sur |
|---|---|---|---|
| `reuseport` | chaque worker, sur son propre socket lié avec `SO_REUSEPORT` | non | Linux |
| `round_robin` | le primaire, qui passe chaque connexion acceptée au worker suivant | oui, pour accepter et transférer seulement | macOS et Windows, et le repli partout |

`server.strategy` vaut `auto`, qui choisit la valeur par défaut de la plateforme, ou le
nom d’une stratégie. Quand la stratégie choisie n’est pas prise en charge, le serveur se replie
sur `round_robin`, qui fonctionne partout, et journalise un avertissement avec la raison.

### Pourquoi ces deux-là

La conception repose sur une mesure faite sur les trois plateformes, avec quatre workers.

- **`reuseport`** a équilibré uniformément sous Linux. Sous macOS, un worker a pris toutes les
  connexions. Il n’existe pas sous Windows. C’est le bon choix sous Linux et nulle part ailleurs.
- **Un socket d’écoute partagé par tous les workers** a mal équilibré sous Linux et macOS, et sous
  Windows un worker a pris toutes les connexions. Il n’équilibre nulle part : il n’est donc pas
  proposé.
- **Le primaire accepte et passe chaque connexion** a équilibré parfaitement sur les trois
  plateformes, sans code natif. Pour des connexions de longue durée et jusqu’à environ 10 000
  nouvelles connexions par seconde, il a été aussi rapide que `reuseport`. (Une première mesure
  montrait un écart sous Linux. Il venait d’un générateur de charge qui partageait le cœur du
  primaire, et il a disparu quand le générateur a tourné dans son propre processus.) Le primaire
  passe environ 37 microsecondes par nouvelle connexion, ce qui place le plafond près de 27 000
  par seconde sur la machine de test. Sous Windows, le transfert est plus lent, environ 3 300
  connexions par seconde.

`round_robin` est donc la valeur par défaut là où `reuseport` n’équilibre pas, et le repli.
`reuseport` ne compte que sous Linux, pour un serveur qui ouvre plus d’environ 10 000 nouvelles
connexions par seconde, ce que ne fait pas un serveur qui réutilise ses connexions.

## Le tube de messages

Chaque worker a un [tube de messages](../reference/glossary.md#concurrency) (*message pipe*) vers
le primaire, identique sur toutes les plateformes et jamais sur le chemin des données. Il
transporte aujourd’hui `ready` et `stop(deadline)`. Le nom `reload` est réservé, et les compteurs
ne sont pas encore implémentés.

- Un worker qui voit le tube se fermer sait que le primaire est mort. Il vide ses requêtes et
  sort. Aucune protection propre à une plateforme contre les orphelins n’est nécessaire.
- Le primaire ne signale jamais directement un worker. Il envoie `stop`, et tue le processus après
  l’échéance. Cela se comporte de la même façon sous Windows, où les signaux POSIX n’existent pas.
- Avec `round_robin`, le même tube transporte les connexions : `Peer:send` passe un `TcpStream` à
  un worker, avec un message.

## Arrêt et rechargement

Un worker qui s’arrête ferme son écouteur, termine les requêtes en cours jusqu’à l’échéance, puis
annule ce qui reste.

- Avec `round_robin`, le primaire cesse de passer des connexions à un worker en cours de vidage :
  rien n’est perdu.
- Avec `reuseport`, le noyau réinitialise les connexions en file dans le backlog d’un socket qui
  se ferme. Un rechargement progressif démarre donc le worker de remplacement, attend son `ready`,
  puis arrête l’ancien, et garde au plus un worker hors service à la fois. Cette limite est
  documentée, pas cachée.

Le rechargement progressif existe dans `kernel` (`Supervisor:reload` ; `SIGHUP` dans le primaire,
ou `Application:reload`, qui prend une seule table d’options, `{ grace_timeout?, ready_timeout? }`).
Il remplace les workers par redémarrage, un à la fois, et n’envoie aucun message `reload` : ce nom
reste réservé.

Les workers héritent de tout l’environnement du primaire, plus les variables `HECATE_WORKER_*` de
leur rôle. Un worker refuse un hôte ou un backlog mal formé dans ces variables.

## Ce qui existe aujourd’hui {#what-exists-today}

| Élément | État |
|---|---|
| `reactor.spawn`, `Process` (`wait`, `kill`, `pid`) | Implémenté. |
| `reactor.ipc` : `Peer:send`, `Peer:receive`, passage de handles, `ipc.parent()` | Implémenté. |
| Option TCP `reuseport`, `reactor.supports_reuseport()` | Implémenté, mais voir ci-dessous. |
| Superviseur : disponibilité, redémarrage, arrêt en douceur, rechargement progressif (`kernel`) | Implémenté. |
| Stratégie `round_robin`, clés de configuration `server.workers` et `server.strategy` | Implémenté. |
| Stratégie `reuseport` | Écrite, attend la prise en charge par luv (voir ci-dessous). |
| `hecate serve --workers` | Non implémenté (paquet `cli`, phase 3). |
| Compteurs du protocole de contrôle | Non implémenté. |
| Suite de conformité des stratégies sur trois plateformes | Non implémenté. |

### `reuseport` ne fonctionne pas encore {#reuseport-does-not-work-yet}

L’option TCP `reuseport` exige une version de luv qui l’expose pour TCP. luv 1.53, la version sur
laquelle hecate est figé, ne le fait pas (OQ-43). `reactor.supports_reuseport()` renvoie `false`,
et `listen_tcp(..., { reuseport = true })` lève `TransportError` avec `ENOTSUP`, au lieu d’ignorer
l’option. Tant que luv ne la prend pas en charge, `auto` choisit aussi `round_robin` sous Linux.
Le cadre reste complet, et aussi rapide pour les connexions réutilisées.

Là où l’option est prise en charge, elle ne dit rien de l’équilibrage : macOS accepte
l’indicateur et n’équilibre pas.

Pour assembler une version artisanale avec ces primitives, suivez
[Lancer des processus enfants et se passer des connexions](../how-to/run-processes-and-pass-connections.md).
Vous écrivez alors vous-même la supervision.

## Limites

- Un worker ignore `sigterm` et `sigint`, parce qu’un terminal les envoie à tout le groupe de
  processus. `kill <pid du worker>` ne fait rien : seul le primaire arrête un worker.
- Windows ne délivre jamais `sigterm` et ne surveille pas `sighup`. Un gestionnaire de services qui
  arrête le primaire avec `TerminateProcess` n’obtient aucun arrêt en douceur. Les workers voient
  le tube de messages se fermer et vident leurs requêtes avec le délai de grâce par défaut.
- Sous Linux, `SO_REUSEPORT` permet à tout processus du même utilisateur de lier le même port et
  de prendre une part des connexions. Sur un hôte partagé, `round_robin` est le choix le plus sûr.

## Hors périmètre

Les threads pour servir les requêtes, l’affinité de session (un worker ne peut pas passer une
connexion vivante à un autre worker : les connexions WebSocket restent donc là où elles ont
commencé), et les mises à jour binaires sans interruption par héritage de descripteurs vers un
nouveau binaire.

## Voir aussi

- [Lancer des processus enfants et se passer des connexions](../how-to/run-processes-and-pass-connections.md)
- [Le modèle de transport](transport-model.md)
- Référence : [`reactor.spawn`](../reference/reactor/functions/spawn.md),
  [`reactor.ipc`](../reference/reactor/ipc.md),
  [`reactor.supports_reuseport`](../reference/reactor/functions/supports_reuseport.md),
  [`reactor.listen_tcp`](../reference/reactor/functions/listen_tcp.md)
