---
title: Guides pratiques
description: Des recettes qui résolvent un problème précis avec hecate, écrites pour hecate 0.x et Lua 5.5.
hecate: "0.x"
lua: "5.5"
order: 0
source_revision: 310648b
---

# Guides pratiques

Chaque guide résout un problème et suppose que vous connaissez les bases. Pour comprendre les
raisons d’une recette, lisez la page correspondante de la section
[Explications](../explanation/index.md).

## Réseau et processus

- [Se connecter et servir en TCP](connect-and-serve-over-tcp.md) : se connecter, accepter des
  connexions, lire et écrire des lignes, fermer une seule direction, résoudre des noms.
- [Client et serveur TLS](tls-client-and-server.md) : faire confiance au magasin du système ou à
  une autorité privée, servir en TLS, exiger des certificats clients, lire les erreurs TLS.
- [Échéances et annulation sur les flux](deadlines-and-cancellation.md) : borner une connexion,
  une lecture ou une acceptation, et savoir ce que laisse une opération annulée.
- [UDP, sockets Unix, tubes nommés et DNS](udp-pipes-and-dns.md) : les transports autres que TCP.
- [Lancer des processus enfants et se passer des connexions](run-processes-and-pass-connections.md) :
  `run_process`, `spawn`, le tube de messages et le transfert d’une connexion à un enfant.

## Performances

- [Mesurer les performances](measure-performance.md) : exécuter le benchmark d’écho TCP, lire ses
  chiffres et comparer une modification à sa base.

## Données

- [Encoder et décoder du JSON](encode-and-decode-json.md) : entiers et flottants, `null`, tableaux
  vides, sortie canonique et erreurs de décodage.
- [Journaliser des enregistrements structurés](log-structured-records.md) : gravités, contexte,
  puits, secrets et limites de volume.
