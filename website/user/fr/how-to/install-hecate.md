---
description: Installer l’exécutable hecate depuis une version publiée - les archives et la vérification de leur somme de contrôle, les paquets Linux (deb, rpm, Arch, Alpine), le zip Windows, l’archive macOS, le plancher glibc et les versions préliminaires.
hecate: "0.x"
lua: "5.5"
order: 5
source_revision: 95f28fe2026e96510f0256818dbc1fcb5b084c5a
---

# Installer hecate

Ce guide installe l’exécutable `hecate` depuis une version publiée sur GitHub. Il est écrit pour hecate 0.x et Lua 5.5.
L’exécutable est autonome : il embarque Lua 5.5, LuaRocks et les modules natifs, rien d’autre n’est donc à installer
pour l’exécuter. Une fois qu’il est dans votre `PATH`, [créez un projet](create-and-run-a-project.md).

Chaque version a les mêmes fichiers, sur `https://github.com/hecate-framework/hecate/releases`. Une version se nomme
`<version>-<révision>` sans `v` : `0.1.0-1`. `<version>` est ce qu’affiche `hecate version` ; la révision compte les
versions publiées d’une même version. Les fichiers de la version `0.1.0-1` (les paquets Linux sont pour x86_64) :

| Plateforme | Fichier |
|---|---|
| Linux, toute distribution | `hecate-0.1.0-1-linux-x86_64.tar.gz` |
| Debian, Ubuntu | `hecate_0.1.0-1_amd64.deb` |
| Fedora, RHEL et dérivées | `hecate-0.1.0-1.x86_64.rpm` |
| Arch Linux | `hecate-0.1.0-1-x86_64.pkg.tar.zst` |
| Alpine Linux | `hecate-0.1.0-r1.x86_64.apk` |
| macOS (Apple silicon) | `hecate-0.1.0-1-darwin-aarch64.tar.gz` |
| Windows (x86_64) | `hecate-0.1.0-1-windows-x86_64.zip` |

Chaque fichier a un fichier de même nom auquel s’ajoute `.sha256`.

## Vérifier un téléchargement {#verify-a-download}

Le fichier `.sha256` contient l’empreinte et le nom du fichier, au format de `sha256sum`. Mettez les deux fichiers dans
le même répertoire et vérifiez :

```sh
sha256sum -c hecate-0.1.0-1-linux-x86_64.tar.gz.sha256    # Linux
shasum -a 256 -c hecate-0.1.0-1-darwin-aarch64.tar.gz.sha256    # macOS
```

Sous Windows, comparez l’empreinte à la main :

```powershell
(Get-FileHash hecate-0.1.0-1-windows-x86_64.zip -Algorithm SHA256).Hash
Get-Content hecate-0.1.0-1-windows-x86_64.zip.sha256
```

Les versions publiées portent aussi une attestation de provenance de construction, qui prouve que le fichier a été
construit par le workflow de publication du dépôt à partir du commit étiqueté :

```sh
gh attestation verify hecate-0.1.0-1-linux-x86_64.tar.gz --repo hecate-framework/hecate
```

## Archive Linux {#linux-archive}

L’archive contient `hecate` à sa racine. Décompressez-la là où votre `PATH` cherche :

```sh
sudo tar -xzf hecate-0.1.0-1-linux-x86_64.tar.gz -C /usr/local/bin hecate
hecate version
```

## Paquets Linux {#linux-packages}

Les paquets s’installent depuis un fichier avec l’outil du système. Il n’y a pas de dépôt à ajouter ni de clé à
importer. Chaque paquet place les mêmes fichiers sur le système :

- `/usr/bin/hecate`
- les complétions pour bash (`/usr/share/bash-completion/completions/hecate`), zsh
  (`/usr/share/zsh/site-functions/_hecate`) et fish (`/usr/share/fish/vendor_completions.d/hecate.fish`)
- la licence, dans `/usr/share/doc/hecate/copyright` (deb) ou `/usr/share/licenses/hecate/LICENSE` (les autres)

Vérifiez d’abord le fichier, puis installez-le en tant que root.

### Debian et Ubuntu {#debian-and-ubuntu}

```sh
sudo apt install ./hecate_0.1.0-1_amd64.deb
```

`dpkg -i hecate_0.1.0-1_amd64.deb` fait la même chose sans résoudre les dépendances ; la seule est
`libc6 (>= 2.28)`. Supprimez le paquet avec `sudo apt remove hecate`.

### Fedora, RHEL, AlmaLinux et Rocky Linux {#fedora-rhel-almalinux-and-rocky-linux}

```sh
sudo dnf install ./hecate-0.1.0-1.x86_64.rpm
```

Supprimez-le avec `sudo dnf remove hecate`. Le paquet n’est pas signé : `dnf` ne vérifie aucune signature pour un
fichier local, et `rpm -K` n’en signale aucune.

### Arch Linux {#arch-linux}

```sh
sudo pacman -U ./hecate-0.1.0-1-x86_64.pkg.tar.zst
```

Supprimez-le avec `sudo pacman -R hecate`. Arch n’a aucun moyen d’écrire « avant la version » dans un numéro de
version : une version préliminaire `0.4.2rc1` se classe donc après `0.4.2` pour `pacman`. Supprimez une version
préliminaire avant d’installer la version finale.

### Alpine Linux {#alpine-linux}

```sh
apk add --allow-untrusted ./hecate-0.1.0-r1.x86_64.apk
```

Le paquet n’est pas signé, car le projet n’a pas encore de clé de signature : c’est pourquoi `apk` exige
`--allow-untrusted`, et pourquoi vous devez d’abord vérifier le `.sha256`. Supprimez-le avec `apk del hecate`.

Le paquet Alpine contient un exécutable lié statiquement à musl, qui n’a donc besoin de rien d’autre du système. Un
exécutable statique ne peut pas charger de bibliothèques partagées : les modules Lua de votre projet et les modules
natifs intégrés à `hecate` fonctionnent, mais une dépendance à code C que `hecate install` compile ne peut pas être
chargée par lui sur Alpine.

### Mettre à jour {#updating}

Un paquet est une mise à jour quand il a une version supérieure : installez le fichier plus récent de la même façon.
Les versions des publications et des paquets sont décrites dans [Versions préliminaires](#pre-release-versions).

## macOS {#macos}

Décompressez l’archive et placez `hecate` dans votre `PATH` :

```sh
sudo tar -xzf hecate-0.1.0-1-darwin-aarch64.tar.gz -C /usr/local/bin hecate
hecate version
```

L’exécutable n’est ni signé ni notarisé. Un navigateur marque un fichier téléchargé comme mis en quarantaine, et
Gatekeeper refuse alors de l’exécuter ; `curl -LO` ne le marque pas. Si vous l’avez téléchargé avec un navigateur,
retirez la marque avec `xattr -d com.apple.quarantine /usr/local/bin/hecate`, une fois la somme de contrôle vérifiée.

## Windows {#windows}

Décompressez le zip. Il contient deux fichiers qui doivent rester dans le même répertoire : `hecate.exe` et
`lua55.dll`. Placez ce répertoire dans votre `PATH` (par exemple `C:\Program Files\hecate`) :

```powershell
Expand-Archive hecate-0.1.0-1-windows-x86_64.zip -DestinationPath "C:\Program Files\hecate"
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\Program Files\hecate", "User")
hecate version
```

Ouvrez un nouveau terminal après avoir modifié `Path`.

## Linux et glibc {#linux-and-glibc}

L’exécutable Linux est lié dynamiquement à glibc et exige glibc 2.28 ou plus récente : il fonctionne sur RHEL 8 et
suivantes, Debian 10 et suivantes, Ubuntu 20.04 et suivantes, et les distributions de cet âge. Pour tenir ce plancher,
la publication le construit dans un conteneur AlmaLinux 8 (glibc 2.28), et l’étape d’empaquetage refuse un exécutable
qui exige une glibc plus récente. Le workflow de publication installe les paquets dans Debian 12, Ubuntu 22.04,
AlmaLinux 9, Fedora, Arch Linux et Alpine 3.20 et lance `hecate version` dans chacun avant de créer la version.

## Versions préliminaires {#pre-release-versions}

Une version préliminaire est la version suivie de `alpha`, `beta`, `rc` ou `pre` et d’un nombre : `0.4.2rc1` ; sa
publication est `0.4.2rc1-1`, et GitHub la marque comme préliminaire. Les archives gardent cette écriture. Chaque
format de paquet écrit la version préliminaire comme son outil le veut, de sorte qu’elle se classe avant la version
finale là où le format sait le dire :

| Publication | deb | rpm | Arch | Alpine |
|---|---|---|---|---|
| `0.4.2-1` | `0.4.2-1` | `0.4.2`, release `1` | `0.4.2-1` | `0.4.2-r1` |
| `0.4.2rc1-1` | `0.4.2~rc1-1` | `0.4.2~rc1`, release `1` | `0.4.2rc1-1` | `0.4.2_rc1-r1` |

La version à l’intérieur du paquet est celle du tableau ; les noms de fichiers ne portent pas le tilde (GitHub le
réécrit dans le nom d’un fichier) : les fichiers de `0.4.2rc1-1` sont `hecate_0.4.2rc1-1_amd64.deb`,
`hecate-0.4.2rc1-1.x86_64.rpm`, `hecate-0.4.2rc1-1-x86_64.pkg.tar.zst` et `hecate-0.4.2_rc1-r1.x86_64.apk`.

## Ce qui viendra plus tard {#what-comes-later}

C’est la première façon d’installer hecate, et elle est volontairement simple. Pas encore disponibles :

- des paquets pour arm64 (les paquets Linux et l’archive ne sont construits que pour x86_64) ;
- des dépôts apt, dnf, pacman et apk, qui donneraient des mises à jour par le système et des paquets signés ;
- Homebrew, Scoop, winget, l’AUR et un installateur macOS ;
- la signature : les paquets et les archives sont vérifiés par leur `.sha256` et leur attestation, pas par la
  signature d’une clé.

Pour installer `hecate` dans un workflow de CI de votre projet, utilisez plutôt l’action d’installation ; voir
[Livrer sur un serveur](deliver-to-a-server.md).
