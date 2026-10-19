---
description: Pourquoi hecate vérifie les serveurs TLS avec le vérificateur du système d’exploitation, ce qu’ajoute ca_pem, ce qui ne peut pas être désactivé, et les réserves propres à chaque plateforme sur la révocation et la durée de vie des certificats.
hecate: "0.x"
lua: "5.5"
order: 2
source_revision: f1f3b5e
---

# Confiance TLS et valeurs par défaut de sécurité

Cette page explique comment hecate décide de faire confiance à un serveur TLS, et quels choix il
fait à votre place. Elle est écrite pour hecate 0.x et Lua 5.5. La décision est consignée dans
l’ADR 0024 (acceptée le 2026-10-18). Pour les recettes, voir
[Client et serveur TLS](../how-to/tls-client-and-server.md).

## Ce qu’un client croit par défaut

`net.connect_tls` et `net.tls.client_config` vérifient le certificat du serveur avec le
vérificateur du système d’exploitation. Sous Windows et macOS, la chaîne est contrôlée par les
services propres du système. Sous Linux, les répertoires usuels de certificats sont lus. Sans
option, un serveur public fonctionne.

Le crate Rust qui fournit cela est `rustls-platform-verifier`, utilisé avec le fournisseur
cryptographique `ring`. Il ajoute de quatre à sept petits crates par plateforme au module natif.

## Pourquoi le vérificateur du système d’exploitation

Deux autres conceptions ont été étudiées et rejetées.

- **Ne faire confiance qu’à ce que l’appelant passe dans `ca_pem`.** Cela n’ajoute rien aux
  dépendances, mais rien ne fonctionne face à un serveur public tant que vous ne livrez pas un
  lot d’autorités, et les magasins diffèrent d’une plateforme à l’autre. TLS doit fonctionner
  d’emblée.
- **Embarquer une liste de racines dans hecate.** La liste est la même partout, mais elle vieillit
  à chaque version et ignore ce que l’administrateur de la machine a décidé d’approuver ou de ne
  pas approuver.

Le magasin du système d’exploitation suit la politique propre de la machine, et un administrateur
peut la changer sans nouvelle version de hecate.

## Ce qu’ajoute `ca_pem`

`ca_pem` **ajoute** des ancres de confiance au magasin du système. Il sert pour une autorité
privée : la racine d’une entreprise, ou l’autorité d’un environnement de test. Les racines du
système restent approuvées.

`system_roots = false` retire les racines du système et ne fait confiance qu’à `ca_pem`. Il exige
`ca_pem`. Il vous donne un ensemble de confiance fermé, et il emploie le vérificateur qui est le
même sur toutes les plateformes, sans aucune politique du système d’exploitation. Les tests de
hecate l’utilisent pour rester hermétiques.

## Ce qui ne peut pas être désactivé

- **La vérification elle-même.** Aucune option n’installe un vérificateur qui accepte tous les
  certificats. Le seul vérificateur personnalisé est celui de la plateforme, et `ca_pem` ne fait
  qu’ajouter des ancres. Des options comme `verify` ou `insecure` n’existent pas : les passer lève
  `ArgumentError`, tout comme passer une option de serveur à une configuration de client.
- **La vérification du nom du serveur.** Le certificat doit être valide pour le nom auquel vous
  vous connectez, ou pour `server_name`. C’est contrôlé sur les trois plateformes (RFC 6125).
- **Le plancher du protocole.** hecate utilise les valeurs par défaut de rustls : TLS 1.3 et 1.2.
  Aucune option ne permet d’activer des versions plus anciennes ni d’autres suites de chiffrement.
- **0-RTT.** Il est désactivé.

Vous pouvez encore rendre une connexion peu sûre dans votre propre code, en vous connectant au
mauvais hôte ou en faisant trop largement confiance à une autorité privée. La bibliothèque retire
l’interrupteur, pas la responsabilité.

## Un magasin vide est une erreur

Si le magasin du système est vide ou incomplet, une poignée de main qui échoue avec un émetteur
inconnu lève `TlsError`. L’erreur dit ce qui manque et comment y remédier : installer les
certificats du système, ou passer `ca_pem`. Il n’y a aucun repli silencieux sur autre chose.

Les images Docker de hecate installent les certificats du système (`ca-certificates`) pour que la
configuration par défaut fonctionne dans un conteneur. Les vérifications de publication échouent
si une image d’exécution en est dépourvue.

## Révocation

Le refus d’un certificat révoqué dépend de la plateforme.

- **Windows et macOS :** le système d’exploitation contrôle la révocation, par OCSP (Online
  Certificate Status Protocol, RFC 6960) et par listes de révocation de certificats, et peut les
  récupérer par le réseau pendant la poignée de main. Dans un réacteur, cet appel **bloque le
  réacteur**, et avec lui chaque coroutine du processus, jusqu’à ce que le répondeur réponde ou
  que le système abandonne. Les adresses viennent de l’autorité de certification, pas du serveur
  que vous contactez : un serveur ne peut donc pas orienter le délai vers une adresse à lui. Une
  autorité lente peut malgré tout retarder une poignée de main.
- **Linux :** aucun contrôle de révocation.
- **`system_roots = false` :** aucune politique du système d’exploitation et aucune entrée-sortie :
  aucun contrôle de révocation sur aucune plateforme.

Si une poignée de main ne doit jamais bloquer, utilisez `system_roots = false` et acceptez que la
révocation ne soit pas contrôlée. Un serveur qui demande des certificats clients
(`client_ca_pem`) ne contrôle pas leur révocation : il ne configure aucune liste de révocation.

## Une confiance plus large par défaut

Le magasin du système contient de nombreuses autorités. Avec `ca_pem` seul, l’ensemble de
confiance était étroit ; par défaut, il est large. Si vous ne vous connectez qu’à des services que
vous exploitez, préférez `system_roots = false` avec votre propre autorité. Cela rétablit
l’ensemble étroit.

## La règle des 398 jours sous macOS

macOS refuse un certificat de serveur valide plus de 398 jours. Il le fait même quand l’autorité
de certification a été ajoutée avec `ca_pem`, parce que la politique du système d’exploitation
s’applique. Les certificats de longue durée d’une autorité privée échouent donc sous macOS avec la
confiance par défaut. Des certificats de courte durée, ou `system_roots = false`, l’évitent.
L’erreur est le texte propre du système : elle indique « not standards compliant », et
`context.reason` peut être absent.

## Ce qui n’est pas encore fourni

Non fait : les réglages de reprise de session, la politique d’agrafage OCSP, les listes de
révocation de certificats, le choix d’un certificat selon le SNI (Server Name Indication, RFC 6066)
côté serveur, les détails de certificat au-delà des octets DER du certificat du pair, et Android
(le vérificateur de plateforme y demande un environnement Java). Le côté serveur de
`tls.server_config` n’est pas modifié par l’ADR 0024.

## Voir aussi

- [Client et serveur TLS](../how-to/tls-client-and-server.md)
- [Le modèle de transport](transport-model.md)
- Référence : [`hecate.net.tls`](../reference/net/tls.md), [`TlsError`](../reference/net/TlsError.md)
