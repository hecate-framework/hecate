---
description: Exécuter le benchmark d’écho TCP, lire ses chiffres de latence et de débit, et comparer votre arbre de travail à une référence Git.
hecate: "0.x"
lua: "5.5"
order: 7
source_revision: 1e4a3b0
---

# Mesurer les performances

Ce guide montre comment exécuter le benchmark réseau du dépôt et comment comparer une modification
à sa base. Il est écrit pour hecate 0.x et Lua 5.5, et fonctionne sous Linux et macOS.

Le scénario `tcp-echo` démarre un serveur d’écho construit sur `hecate.reactor` et `hecate.net`,
puis le charge avec un générateur de charge écrit en Lua. Le générateur est à *boucle ouverte* :
chaque connexion doit envoyer une requête par intervalle, et la latence d’une requête se mesure
depuis l’instant où elle était due, non depuis celui où elle a été envoyée. Un serveur lent ne peut
donc pas masquer sa file d’attente (omission coordonnée).

## Exécuter le scénario

Relevez la limite de fichiers ouverts au-dessus du nombre de connexions, puis lancez-le :

```sh
ulimit -n 20000
lua tools/run.lua bench tcp-echo --rounds=5 --connections=10000 --rate=5000 --duration=10
```

La tâche affiche la médiane, le minimum et le maximum de chaque mesure sur l’ensemble des
rondes, ainsi que le rapport entre le plus grand et le plus petit. Ajoutez `--json` pour un
rapport lisible par une machine.

| Mesure | Unité | Signification |
|---|---|---|
| `throughput` | requêtes/s | requêtes terminées par seconde après l’échauffement |
| `errors` | connexions | connexions qui n’ont pas pu s’ouvrir ou qui se sont rompues |
| `latency p50`, `p90`, `p99`, `p99.9`, `max` | µs | latence depuis l’instant dû |

Un débit inférieur à `--rate` signifie que le serveur, ou le générateur, est saturé. Les options du
générateur de charge sont `--connections`, `--rate` (requêtes par seconde au total), `--duration`
et `--warmup` (secondes), et `--payload` (octets).

## Comparer à une base

`--compare` extrait une référence Git dans `.hecate/bench-base` et exécute les mêmes fichiers de
scénario sur cet arbre et sur votre arbre de travail, en alternance (A/B/A/B), sur le même hôte :

```sh
lua tools/run.lua bench tcp-echo --compare=origin/main --rounds=7
```

La tâche se termine avec le statut 1 quand une différence est significative (test U de
Mann-Whitney, p < 0,01) **et** supérieure à 10 % sur le débit ou la latence p99. Tout écart plus
petit est du bruit.

## Épingler les processus

Sur une machine à plusieurs cœurs, donnez au serveur et au générateur des cœurs distincts :

```sh
lua benchmarks/run.lua tcp-echo --server-pin=2 --load-pin=3
```

## Chiffres publiables

Les chiffres d’une machine partagée ou virtuelle servent à comparer deux commits, pas à être cités.
Pour des chiffres absolus, suivez la procédure pour un hôte au repos dans
[`benchmarks/README.md`](https://github.com/hecate-framework/hecate/blob/main/benchmarks/README.md).
Les demandes de fusion étiquetées `performance` exécutent la comparaison en CI (`benchmarks.yml`).
