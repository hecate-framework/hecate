---
description: Comment hecate déplace des octets sur le réseau : flux, suspension plutôt que rappels, contre-pression, fermeture partielle, tampons, règles d’annulation et pourquoi close ne suspend jamais.
hecate: "0.x"
lua: "5.5"
order: 1
source_revision: cba7be6
---

# Le modèle de transport

Cette page explique comment `hecate.reactor` et `hecate.net` déplacent des octets entre
processus, et pourquoi l’API a la forme qu’elle a. Elle est écrite pour hecate 0.x et Lua 5.5.
Pour les recettes, voir [Se connecter et servir en TCP](../how-to/connect-and-serve-over-tcp.md).

## Deux couches

`hecate.reactor` enveloppe une seule fois les handles réseau de libuv : TCP, UDP, tubes et
résolution de noms. `hecate.net` s’appuie dessus et ajoute la résolution de noms avant la
connexion, le lecteur et l’écrivain tamponnés, et TLS. `net` ne parle jamais à libuv lui-même.
Tout ce qui attend passe par le [réacteur](../reference/glossary.md#concurrency) (*reactor*),
c’est pourquoi les règles ci-dessous valent pour chaque transport.

## Flux

Un [flux](../reference/glossary.md#concurrency) (*stream*) est une suite ordonnée d’octets lus,
écrits et fermés dans l’ordre. Une connexion TCP, un socket Unix, un tube nommé et une session
TLS sont tous des flux. L’interface `Stream` demande trois opérations :

- `read(max)` renvoie les octets qu’une réception a livrés, au plus `max`. Il ne renvoie jamais
  de chaîne vide. Il renvoie `nil` à la fin du flux.
- `write(data)` accepte la totalité de `data`, ou lève une erreur. Il ne signale jamais une
  écriture partielle.
- `close()` est idempotent et ne suspend jamais.

Un flux peut aussi offrir `shutdown()` pour une fermeture partielle, et `is_closed()`. Les flux
sont utilisables avec `<close>`. Le lecteur et l’écrivain tamponnés fonctionnent sur n’importe
quel flux, et un flux TLS est un flux au-dessus d’un autre flux, qu’il possède.

Un socket UDP n’est pas un flux. Chaque appel déplace un datagramme, et les frontières comptent.

## Suspension plutôt que rappels

Aucun rappel (*callback*) n’est jamais exposé à votre code. Un appel comme `read` suspend la
[coroutine](../reference/glossary.md#concurrency) en cours. Le réacteur exécute d’autres
coroutines pendant ce temps et reprend celle-ci quand le système d’exploitation a une réponse.
Votre gestionnaire se lit donc comme du code séquentiel :

```lua
local line = reader:read_line()
writer:write(answer(line))
writer:flush()
```

Le prix à payer est que ces fonctions doivent être appelées depuis une coroutine gérée. En
dehors, elles lèvent `NonYieldableContextError`. Il en va de même dans une fonction à travers
laquelle Lua ne peut pas céder la main, comme le comparateur de `table.sort`.

## Contre-pression

Un producteur ne doit pas dépasser son consommateur sans borne. Dans hecate, le producteur
*suspend* au lieu d’empiler les données en mémoire. C’est la
[contre-pression](../reference/glossary.md#concurrency) (*back-pressure*).

- `write` suspend jusqu’à ce que le système d’exploitation ait accepté les données. Quand le pair
  lit lentement, sa fenêtre de réception se remplit et vos écritures attendent.
- Côté lecture, un flux TCP lit à l’avance jusqu’à 64 Kio, puis cesse de lire tant que votre code
  n’a pas rattrapé son retard. La fenêtre du pair se ferme alors, et ses écritures attendent à
  leur tour. Un tube de messages ne lit pas à l’avance.
- Le lecteur tamponné borne une ligne ou un enregistrement (65536 octets par défaut) : un pair ne
  peut donc pas vous faire mettre en tampon une ligne sans limite. `read_exact` prend un `limit`
  pour la même raison.

## Fermeture partielle

Une connexion a deux directions. `shutdown()` termine la direction sortante et laisse la
direction entrante ouverte : c’est une [fermeture partielle](../reference/glossary.md#concurrency)
(*half-close*). Le pair voit la fin du flux, répond, puis ferme. Les protocoles qui marquent ainsi
la fin d’une requête s’y appuient. Pour TLS, `shutdown()` envoie aussi `close_notify`.

## Tampons

Le lecteur tamponné garde les octets arrivés mais non consommés. `read_until` explore chaque
fragment une seule fois : le coût est donc linéaire en la longueur de l’enregistrement, quel que
soit son découpage.

L’écrivain tamponné rassemble les petites écritures et les envoie quand `flush` est appelé ou
que le tampon atteint sa capacité (8192 octets par défaut). Une charge au moins aussi grande que
la capacité, écrite quand rien n’est en tampon, va directement au flux, sans copie.

Aucun des deux ne possède son flux. Fermer un écrivain jette ce qu’il détient encore : on vide
donc le tampon d’abord. Un écrivain dont le vidage a échoué ou a été annulé est *empoisonné* : il
ne peut pas savoir ce qui a été envoyé, et chaque appel suivant lève une erreur.

## Règles d’annulation

Toute opération peut être annulée, par une échéance ou par sa portée (*scope*). libuv peut retirer
une lecture ou une acceptation en attente, mais pas une écriture, une connexion ou un `shutdown`
déjà remis au système d’exploitation. Les règles en découlent :

- Un `read`, `accept` ou `receive_from` annulé laisse l’objet utilisable et ne perd rien.
- Un `write`, `send_to`, `shutdown` ou `connect` annulé ferme l’objet, parce que la quantité
  envoyée est inconnue.

Le tableau de chaque opération est dans
[Échéances et annulation sur les flux](../how-to/deadlines-and-cancellation.md). Aucune opération
ne prend d’argument de délai : vous l’enveloppez dans `reactor.deadline`.

## Un seul lecteur à la fois

Une seule coroutine lit, accepte ou reçoit à la fois sur un objet. Un second appel concurrent
lève une erreur au lieu d’attendre. La raison est que deux lecteurs se partageraient les octets
d’un même flux, et que les données vues par chacun dépendraient de l’ordonnancement. Les écritures
de plusieurs coroutines sont mises en file dans l’ordre des appels.

Créez un seul lecteur tamponné par flux. La bibliothèque ne l’impose pas : un second lecteur sur
le même flux n’est pas refusé, et les deux lecteurs se partagent ses octets.

## Pourquoi `close` ne suspend jamais

`close` est la dernière chose qui s’exécute à la fin d’un bloc `<close>`, y compris quand la fin
est causée par une annulation. Une coroutine annulée doit pouvoir libérer ses ressources sans
attendre le réseau : `close` rend donc la main tout de suite et réveille chaque coroutine qui
attend sur l’objet, avec `ECANCELED`.

La conséquence est que `close` ne peut pas faire de travail qui exige le réseau. Il ne peut pas
vider un tampon, ni envoyer un `close_notify` TLS. Vous le faites explicitement, avant la fin du
bloc : `writer:flush()`, puis `stream:shutdown()`.

## Erreurs

Un échec du transport lève `reactor.TransportError`, une `NetworkError`. `context.errno` est le
nom libuv, comme `ECONNREFUSED`, `EPIPE` ou `EBADF` (un objet fermé), et `context.operation`
nomme l’opération. `IoError` est réservée au système de fichiers et aux processus. Une poignée
de main ou une vérification TLS qui échoue lève `TlsError`, aussi une `NetworkError`.

## Voir aussi

- [Échéances et annulation sur les flux](../how-to/deadlines-and-cancellation.md)
- [Confiance TLS et valeurs par défaut de sécurité](tls-trust-and-security.md)
- Référence : [`hecate.net`](../reference/net/index.md), [`Stream`](../reference/net/Stream.md),
  [`hecate.reactor`](../reference/reactor/index.md)
