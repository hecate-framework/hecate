---
description: Livrer une application hecate sur un serveur sans Docker : une archive de livraison, une unité systemd, un lien symbolique pour changer de version et un proxy inverse pour TLS.
hecate: "0.x"
lua: "5.5"
order: 6
source_revision: 1cda62b4db438468c5415a578cb7bde8c8a44b89
---

# Livrer sur un serveur

Ce guide livre un projet sur un serveur Linux sans conteneur. Il est écrit pour hecate 0.x et Lua 5.5. Le serveur n’a
besoin que de l’exécutable `hecate`.

## Construire la livraison

Construisez sur le système d’exploitation et l’architecture du serveur (les dépendances avec du code C sont compilées
pour lui), en CI :

```sh
hecate install --frozen
hecate package
```

`hecate package` écrit `shop-0.1.0-linux-x86_64.tar.gz` et `shop-0.1.0-linux-x86_64.tar.gz.sha256` : le manifeste, le
verrou, `main.lua`, `src`, `config` et `lua_modules`, plus un fichier `RELEASE` avec les versions. Les tests, `.git`,
`.hecate` et le site de documentation n’y figurent pas. Gardez les secrets hors du projet : ils viennent de
l’environnement du serveur.

## Lancer les vérifications en CI

`hecate generate workflow ci` écrit `.github/workflows/ci.yml` (`hecate new shop --ci github` le fait pour un nouveau
projet) : à chaque push et à chaque pull request, sur Linux, macOS et Windows, il installe l’exécutable avec l’action
d’installation `hecate-framework/hecate-actions/setup`, puis exécute `hecate install --frozen`, `hecate test` et, pour un projet
qui a un contrat, `hecate contract export` et `hecate contract lint`. Ajoutez `--doc` pour construire aussi la
documentation. Le workflow n’appelle que des commandes `hecate` : une exécution se comporte donc comme une exécution
locale ; régénérez-le avec `--force` après une mise à niveau de Hecate. Pour construire et empaqueter la livraison sur la
plateforme du serveur, ajoutez un job qui exécute `hecate install --frozen` et `hecate package`.

Deux autres workflows : `hecate generate workflow contract` écrit `.github/workflows/contract.yml`, qui, à chaque pull
request, exécute `hecate contract diff origin/<branche de base>` et échoue sur un changement incompatible du contrat
(versionnez d’abord `openapi.json` sur la branche de base, avec `hecate contract export --output openapi.json`) ;
`hecate generate workflow docs-pages` écrit `.github/workflows/docs.yml`, qui, lors d’un push sur la branche par défaut,
construit la documentation avec `hecate doc build --yes` et la publie sur GitHub Pages (réglez la source de Pages sur
« GitHub Actions »). Un workflow `release` n’est pas encore généré.

## Préparer le serveur

```sh
hecate generate systemd --user shop --executable /usr/local/bin/hecate --output shop.service
```

Modifiez l’unité si besoin, copiez-la dans `/etc/systemd/system/shop.service` et créez un fichier pour les réglages et
les secrets, `/etc/shop/env`, avec des variables `HECATE_*` (`HECATE_ENV=production`, le mot de passe de la base de
données, etc.) ; ajoutez `EnvironmentFile=/etc/shop/env` à l’unité. Puis
`systemctl daemon-reload && systemctl enable shop`.

## Déployer

Chaque livraison va dans son propre répertoire, et un lien indique laquelle s’exécute :

```sh
sha256sum -c shop-0.1.0-linux-x86_64.tar.gz.sha256
mkdir /srv/shop/releases/0.1.0 && tar -xzf shop-0.1.0-linux-x86_64.tar.gz -C /srv/shop/releases/0.1.0
ln -sfn /srv/shop/releases/0.1.0 /srv/shop/current
systemctl reload shop
```

Le répertoire de travail de l’unité est le lien `current`. `systemctl reload` envoie `SIGHUP`, qui remplace un à un les
workers d’une application multiprocessus, sans interruption de service (un redémarrage
est `systemctl restart shop`). Pour revenir en arrière, faites pointer le lien vers la livraison précédente et
rechargez.

## Placer un proxy inverse devant

`hecate serve` écoute sur l’interface de bouclage. Laissez un proxy inverse tel que Caddy ou nginx posséder le port
public et TLS, et transmettre les requêtes à `127.0.0.1:8080`. La liste de contrôle
énumère ce qu’il faut vérifier avant le premier déploiement.
