---
description: Comment hecate.http modélise les messages, mène une connexion de l’acceptation à la fermeture, borne chaque ressource, et pourquoi ses limites ont les valeurs par défaut qu’elles ont.
hecate: "0.x"
lua: "5.5"
order: 4
source_revision: 127cb3d2f023c24467492b8959dd7bc7bc0390d7
---

# Le modèle HTTP

Cette page explique comment `hecate.http` représente les messages, comment vit une connexion, et pourquoi les
limites et les valeurs par défaut sont ce qu’elles sont. Elle est écrite pour hecate 0.x et Lua 5.5. Pour les
recettes, lisez [Servir du HTTP](../how-to/serve-http.md).

`hecate.http` est une couche de protocole bâtie sur [`hecate.net`](transport-model.md). Elle parle HTTP/1.1
([RFC 9112](https://www.rfc-editor.org/rfc/rfc9112)) et suit la sémantique de la
[RFC 9110](https://www.rfc-editor.org/rfc/rfc9110). Elle n’a ni routage, ni HTTP/2, ni WebSocket. Les couches
supérieures ajoutent le routage et les filtres par-dessus.

## Le modèle de message {#the-message-model}

Un message est une donnée simple avec quelques méthodes. Le vocabulaire est celui de la RFC 9110 : *method*
(méthode), *target* (cible), *status code* (code d’état), *field* (champ), *content* (contenu) et *media type*
(type de média).

| Classe | Ce qu’elle contient ou fait |
|---|---|
| `Request` | une `method`, une `target` (et ses `path` et `query`), des `fields` et un contenu |
| `Response` | un `status`, une `reason`, des `fields` et un contenu |
| `Fields` | les champs d’en-tête d’un message |
| `MediaType` | analyse et formate les valeurs de `Content-Type` |
| `Status` | connaît les phrases de raison, et les codes d’état qui ne portent jamais de contenu |
| `Cookie`, `SetCookie` | analysent le champ `Cookie` et formatent `Set-Cookie`, comme l’exige la RFC 6265 |

Les `Fields` ne sont pas sensibles à la casse, peuvent contenir plusieurs valeurs pour un même nom, et gardent leur
ordre. Ils refusent CR, LF et NUL dans une valeur, et les noms qui ne sont pas des jetons (*tokens*). Un saut de
ligne introduit en contrebande ne devient jamais un second champ :

```lua
local core = require("hecate.core")
local http = require("hecate.http")

local fields = http.Fields()
fields:add("Set-Cookie", "a=1")
fields:add("set-cookie", "b=2")
print(fields:get("SET-COOKIE"), #fields:get_all("Set-Cookie"))
-- Prints: a=1	2
local ok, err = pcall(fields.set, fields, "X-Note", "one\r\nInjected: yes")
print(ok, core.name(err))
-- Prints: false	ArgumentError
```

Un champ `Set-Cookie` n’est jamais combiné en une seule ligne.

Les mêmes classes servent le serveur et le client. Une [action](../reference/glossary.md#object-model-and-architecture)
(*action*), la fonction qui sert une requête, renvoie une `Response`. Le client en renvoie une aussi, dont le
contenu est encore sur le fil.

### Le contenu est un flux {#content-is-a-stream}

Le contenu d’un message peut être volumineux ; c’est donc un [flux](../reference/glossary.md#concurrency)
(*stream*), une suite ordonnée d’octets lue à la demande. Une requête de serveur et une réponse de client donnent un
`ContentStream` : `read()` renvoie un fragment à la fois. `read_content(limit?)` collecte tout le contenu dans une
borne.

Le contenu d’une réponse que vous construisez est plus commode. C’est `nil`, une chaîne, ou une fonction qui écrit.
La forme fonction est ce qui fait d’une réponse un flux. Le cadrage (codage par fragments, ou longueur déclarée) est
choisi d’après ce que vous donnez.

`http` manipule des octets et ne sérialise jamais une réponse : le constructeur `Response` refuse une table, qui
relève de la couche supérieure. Le client fait exception : le contenu d’une requête de client peut être une table,
que le client encode en JSON.

Les champs de cadrage appartiennent au protocole, si bien que votre code ne peut pas corrompre le cadrage d’une
connexion :

- le serveur fixe `Content-Length`, `Transfer-Encoding` et `Connection`, et remplace ceux de l’action ;
- le client fixe lui-même `Host`, `Content-Length` et `Transfer-Encoding`. Il garde votre champ `Connection`, et
  ne réutilise pas une connexion après un `Connection: close` que vous avez envoyé.

## La vie d’une connexion {#the-life-of-a-connection}

Le serveur transforme chaque couche du travail en un calcul d’une [portée](../reference/glossary.md#concurrency)
(*scope*), une région qui possède les calculs démarrés en son sein :

1. `serve` exécute une boucle d’acceptation dans une portée. Chaque connexion acceptée est un calcul de cette
   portée, si bien qu’un client lent ne retarde personne.
2. Avec TLS, la poignée de main (*handshake*) s’exécute dans le calcul propre à la connexion, jamais dans la boucle
   d’acceptation.
3. La connexion lit le flux par fragments d’au plus 16 Kio et alimente un analyseur incrémental (llhttp, choisi
   dans l’ADR 0019). Elle reçoit des événements : une [tête](../reference/glossary.md#http) (*head*), des données,
   la fin d’un message.
4. Chaque requête reçoit sa propre portée et une [coroutine](../reference/glossary.md#concurrency) qui exécute
   l’action. Annuler la portée annule l’action et ce qu’elle a démarré.
5. Le serveur écrit la réponse, purge le contenu que l’action a laissé non lu, et passe à la requête suivante. La
   connexion maintenue (une [connexion persistante](../reference/glossary.md#http), *persistent connection*) est le
   comportement par défaut de HTTP/1.1.
6. La connexion se termine sur `Connection: close`, une erreur, un délai ou un arrêt.

Une connexion sert ses requêtes une à une. Quand un client [envoie en pipeline](../reference/glossary.md#http)
(*pipelining*) plusieurs requêtes, les réponses arrivent dans l’ordre des requêtes, comme l’exige la RFC 9112. La
concurrence vient des connexions, pas des requêtes d’une même connexion.

Le serveur ne lit les octets suivants qu’après avoir répondu à toutes les requêtes déjà analysées. C’est la
[contre-pression](../reference/glossary.md#concurrency) (*back-pressure*) : un client qui envoie en pipeline plus
vite que l’action ne travaille attend dans les tampons du noyau, pas dans la mémoire du serveur.

### Les erreurs ne fuient jamais {#errors-never-leak}

Une erreur devient des [détails de problème](https://www.rfc-editor.org/rfc/rfc9457) (RFC 9457), avec un texte fixe
choisi d’après la classe de l’échec. Un échec d’action, un échec réseau et un échec d’analyse ont chacun le leur.

Le texte de l’erreur réelle, une adresse ou un numéro d’erreur n’atteint jamais le client. L’application l’obtient
par `on_error`. C’est une règle de sécurité : un message d’erreur est une donnée sur votre serveur.

### Arrêt en douceur {#graceful-shutdown}

`shutdown(grace_timeout)` cesse d’accepter. Il ferme les connexions qui attendent une requête suivante, et laisse
chaque requête en cours se terminer, avec `Connection: close`.

Ce n’est qu’à l’expiration de la [période de grâce](../reference/glossary.md#http) (*grace period*) que les requêtes
restantes sont annulées. Rien n’est coupé au milieu d’une réponse, sauf si elle est en retard.

Une connexion toute neuve, dont aucun octet de la première requête n’est encore arrivé, n’est pas fermée
immédiatement. Elle dispose de 1 seconde, ou de la période de grâce quand elle est plus courte, pour commencer sa
requête, qui est alors servie avec `Connection: close`.

## Le pool de connexions du client {#the-clients-connection-pool}

Un client garde des connexions inactives par [origine](../reference/glossary.md#http) (*origin*) : le schéma,
l’hôte et le port d’une URL. Ouvrir une connexion coûte un aller-retour, et une poignée de main TLS coûte plus. Le
pool suit quelques règles qui rendent la réutilisation sûre :

- Une connexion inactive expire après 30 secondes, avant les 75 du serveur, si bien que c’est le client qui ferme.
- Une connexion avec du contenu non lu, ou avec des octets restants après une réponse, n’est jamais rendue au pool.
- Une requête annulée ou échouée abandonne sa connexion, car son état est inconnu.
- Une connexion réutilisée peut se révéler morte avant qu’aucun octet de la réponse n’arrive. La requête est alors
  retentée une fois, sur une nouvelle connexion, quand sa méthode est idempotente et que son contenu peut être
  renvoyé (aucun, ou une chaîne). Un POST n’est jamais répété : le serveur a pu le traiter.

## Pourquoi ces limites {#why-these-limits}

Chaque limite existe parce qu’une ressource non bornée est une attaque. Un serveur qui accepte une tête de n’importe
quelle taille, ou qui attend indéfiniment un octet, peut être retenu par un seul client à la connexion lente.

Le serveur borne chaque étape séparément, car les attaques diffèrent :

| Étape | Borne | Protège contre |
|---|---|---|
| La tête | `head_timeout` comme échéance sur toute la tête, et les limites de l’analyseur | un client qui envoie un octet par intervalle (slowloris) |
| L’attente entre deux requêtes | `idle_timeout` | des connexions inactives qui retiennent des descripteurs |
| Le contenu | `max_content`, `content_timeout`, `request_timeout` | un corps énorme, et un corps qui goutte à goutte |
| La réponse | `write_timeout` | un lecteur qui ne lit jamais |
| Le contenu non lu | `drain_timeout` | un client qui occupe une connexion après la réponse |
| La poignée de main | `handshake_timeout`, `max_handshakes`, `max_handshake_bytes` | un client qui fait traîner la poignée de main TLS |

Deux choix méritent un mot.

Le premier est la nature de la borne sur la tête et sur le contenu. `head_timeout` est une échéance sur toute la
tête. `content_timeout` est un délai entre deux lectures. Une tête est petite, donc un budget de temps pour son
ensemble est équitable, et c’est la défense contre un client qui envoie un octet à la fois. Le contenu peut être
volumineux et lent légitimement, donc seul un blocage le coupe. `request_timeout` plafonne le temps total, si bien
qu’un client qui envoie un octet par lecture finit quand même par s’arrêter.

Le second est `max_connections`, qui n’a pas de limite par défaut. Un bon nombre dépend de la limite de
descripteurs du processus, que le déploiement fixe, et de l’existence éventuelle d’un proxy qui plafonne les
connexions en amont. Plutôt que de deviner, le serveur reste borné par la limite de descripteurs, `idle_timeout` et
`head_timeout`, et le guide dit de la fixer.

Quand la boucle d’acceptation rencontre un épuisement de descripteurs (`EMFILE`, `ENFILE`) ou tout autre échec
d’acceptation, les connexions en service continuent d’être servies. La boucle recule de 50 ms à 1 s et reprend
d’elle-même. Elle signale la rafale une seule fois, à `logger` et à `on_error`.

### Pourquoi ces valeurs par défaut {#why-these-defaults}

Les valeurs suivent ce que choisissent les serveurs courants (nginx, Apache, Node, Go) :

- `max_content` vaut 1 Mio. Une action qui a besoin de plus le demande, si bien qu’aucun point d’accès n’accepte des
  téléversements par accident.
- `head_timeout` vaut 60 secondes et `content_timeout` vaut 60 secondes, comme les serveurs courants.
- `idle_timeout` vaut 75 secondes, la valeur de nginx. Un proxy placé devant hecate devrait en utiliser une plus
  courte.
- `backlog` vaut 128, et le port est 8080.
- Les limites de l’analyseur sont 8 Kio pour une cible et un champ, 100 champs et 64 Kio pour une tête.
- L’hôte par défaut est `127.0.0.1`. Exposer le serveur est un acte explicite.

Une valeur par défaut est un énoncé sur le cas typique. Les valeurs sont sûres, pas optimisées. Mesurez votre
propre charge avant d’en relever une.

## Rigueur {#strictness}

L’analyseur accepte HTTP/1.0 et HTTP/1.1 et rien d’autre. Il refuse ce que la RFC 9112 qualifie de dangereux quand
deux lecteurs pourraient ne pas s’accorder sur la fin d’un message :

- un `Content-Length` avec un `Transfer-Encoding` ;
- plusieurs valeurs de `Content-Length` ;
- une ligne de requête sans version.

Ce sont les bases de la contrebande de requêtes (*request smuggling*). Là où llhttp est plus strict que la RFC,
hecate garde le comportement le plus strict. Les formulaires suivent le même principe : une séquence de
pourcentage mal formée est refusée plutôt que devinée.

Le champ `Host` doit être un hôte et un port uniques et valides. Une cible de forme absolue n’est acceptée que si
son autorité est égale à `Host`.

## Ce que le serveur et le client ne font pas {#what-the-server-and-the-client-do-not-do}

- Pas de délai par requête pour les actions. Une action qui ne revient jamais retient sa connexion.
- Un client qui se déconnecte pendant que son action s’exécute n’est pas détecté avant la prochaine écriture.
- Pas de limite sur le nombre de requêtes par connexion.
- `Transfer-Encoding: gzip, chunked` est lu comme fragmenté et n’est pas décompressé.
- Le client n’a ni prise en charge de proxy, ni compression, ni pot de cookies, ni crochet pour filtrer les
  adresses.
- Pas de HTTP/2.

## Voir aussi {#see-also}

- [Servir du HTTP](../how-to/serve-http.md)
- [Définir les limites, les délais et TLS du serveur HTTP](../how-to/http-limits-timeouts-and-tls.md)
- [Le modèle de transport](transport-model.md)
- [Confiance TLS et valeurs par défaut de sécurité](tls-trust-and-security.md)
