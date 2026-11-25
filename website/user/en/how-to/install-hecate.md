---
description: Install the hecate executable from a release - the archives and how to verify their checksum, the Linux packages (deb, rpm, Arch, Alpine), the Windows zip, the macOS archive, the glibc floor and pre-release versions.
hecate: "0.x"
lua: "5.5"
order: 5
---

# Install hecate

This guide installs the `hecate` executable from a GitHub release. It is written for hecate 0.x and Lua 5.5. The
executable is self-contained: it carries Lua 5.5, LuaRocks and the native modules, so nothing else has to be installed to
run it. Once it is on your `PATH`, [create a project](create-and-run-a-project.md).

Every release has the same assets, on `https://github.com/hecate-framework/hecate/releases`. A release is named
`<version>-<revision>` with no `v`: `0.1.0-1`. `<version>` is what `hecate version` prints; the revision counts the
releases of the same version. The assets of release `0.1.0-1` (the Linux packages are for x86_64):

| Platform | Asset |
|---|---|
| Linux, any distribution | `hecate-0.1.0-1-linux-x86_64.tar.gz` |
| Debian, Ubuntu | `hecate_0.1.0-1_amd64.deb` |
| Fedora, RHEL and its derivatives | `hecate-0.1.0-1.x86_64.rpm` |
| Arch Linux | `hecate-0.1.0-1-x86_64.pkg.tar.zst` |
| Alpine Linux | `hecate-0.1.0-r1.x86_64.apk` |
| macOS (Apple silicon) | `hecate-0.1.0-1-darwin-aarch64.tar.gz` |
| Windows (x86_64) | `hecate-0.1.0-1-windows-x86_64.zip` |

Each asset has a file of the same name with `.sha256` added.

## Verify a download

The `.sha256` file holds the digest and the file name, in the format of `sha256sum`. Put both files in the same directory
and check:

```sh
sha256sum -c hecate-0.1.0-1-linux-x86_64.tar.gz.sha256    # Linux
shasum -a 256 -c hecate-0.1.0-1-darwin-aarch64.tar.gz.sha256    # macOS
```

On Windows, compare the digest by hand:

```powershell
(Get-FileHash hecate-0.1.0-1-windows-x86_64.zip -Algorithm SHA256).Hash
Get-Content hecate-0.1.0-1-windows-x86_64.zip.sha256
```

Release builds also carry a build provenance attestation, which proves that the file was built by the release workflow
of the repository from the tagged commit:

```sh
gh attestation verify hecate-0.1.0-1-linux-x86_64.tar.gz --repo hecate-framework/hecate
```

## Linux archive

The archive holds `hecate` at its root. Unpack it where your `PATH` looks:

```sh
sudo tar -xzf hecate-0.1.0-1-linux-x86_64.tar.gz -C /usr/local/bin hecate
hecate version
```

## Linux packages

The packages install from a file with the tool of the system. There is no repository to add and no key to import. Every
package puts the same files on the system:

- `/usr/bin/hecate`
- the completions for bash (`/usr/share/bash-completion/completions/hecate`), zsh (`/usr/share/zsh/site-functions/_hecate`)
  and fish (`/usr/share/fish/vendor_completions.d/hecate.fish`)
- the licence, in `/usr/share/doc/hecate/copyright` (deb) or `/usr/share/licenses/hecate/LICENSE` (the others)

Verify the file first, then install it as root.

### Debian and Ubuntu

```sh
sudo apt install ./hecate_0.1.0-1_amd64.deb
```

`dpkg -i hecate_0.1.0-1_amd64.deb` does the same without resolving dependencies; the only one is `libc6 (>= 2.28)`. Remove
the package with `sudo apt remove hecate`.

### Fedora, RHEL, AlmaLinux and Rocky Linux

```sh
sudo dnf install ./hecate-0.1.0-1.x86_64.rpm
```

Remove it with `sudo dnf remove hecate`. The package is not signed: `dnf` does not check a signature for a local file, and
`rpm -K` reports none.

### Arch Linux

```sh
sudo pacman -U ./hecate-0.1.0-1-x86_64.pkg.tar.zst
```

Remove it with `sudo pacman -R hecate`. Arch has no way to write "before the release" in a version, so a pre-release
`0.4.2rc1` sorts after `0.4.2` for `pacman`: remove a pre-release before you install the final version.

### Alpine Linux

```sh
apk add --allow-untrusted ./hecate-0.1.0-r1.x86_64.apk
```

The package is not signed, because the project has no signing key yet: that is why `apk` needs `--allow-untrusted`, and why
you should verify the `.sha256` first. Remove it with `apk del hecate`.

The Alpine package holds an executable that is linked statically against musl, so it needs nothing else from the system.
A static executable cannot load shared libraries: the Lua modules of your project and the native modules built into
`hecate` work, but a dependency with C code that `hecate install` compiles cannot be loaded by it on Alpine.

### Updating

A package is an update when it has a higher version: install the newer file the same way. The versions of the releases and
of the packages are written in [Pre-release versions](#pre-release-versions).

## macOS

Unpack the archive and put `hecate` on your `PATH`:

```sh
sudo tar -xzf hecate-0.1.0-1-darwin-aarch64.tar.gz -C /usr/local/bin hecate
hecate version
```

The executable is not signed or notarized. A browser marks a downloaded file as quarantined, and Gatekeeper then refuses
to run it; `curl -LO` does not mark it. If you downloaded it with a browser, remove the mark with
`xattr -d com.apple.quarantine /usr/local/bin/hecate`, once you have verified the checksum.

## Windows

Unpack the zip. It holds two files that must stay in the same directory: `hecate.exe` and `lua55.dll`. Put that directory on
your `PATH` (for example `C:\Program Files\hecate`):

```powershell
Expand-Archive hecate-0.1.0-1-windows-x86_64.zip -DestinationPath "C:\Program Files\hecate"
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\Program Files\hecate", "User")
hecate version
```

Open a new terminal after you change `Path`.

## Linux and glibc

The Linux executable links dynamically against glibc, and needs glibc 2.28 or later: it runs on RHEL 8 and later, Debian
10 and later, Ubuntu 20.04 and later, and the distributions of that age. To keep that floor, the release builds it in an
AlmaLinux 8 container (glibc 2.28), and the packaging step refuses an executable that needs a newer glibc. The release
workflow installs the packages in Debian 12, Ubuntu 22.04, AlmaLinux 9, Fedora, Arch Linux and Alpine 3.20 and runs
`hecate version` in each of them before the release is created.

## Pre-release versions

A pre-release is the version followed by `alpha`, `beta`, `rc` or `pre` and a number: `0.4.2rc1`; its release is
`0.4.2rc1-1`, and GitHub marks it as a pre-release. The archives keep that spelling. Each package format spells the
pre-release as its own tool wants, so that it sorts before the final version where the format can say it:

| Release | deb | rpm | Arch | Alpine |
|---|---|---|---|---|
| `0.4.2-1` | `0.4.2-1` | `0.4.2`, release `1` | `0.4.2-1` | `0.4.2-r1` |
| `0.4.2rc1-1` | `0.4.2~rc1-1` | `0.4.2~rc1`, release `1` | `0.4.2rc1-1` | `0.4.2_rc1-r1` |

The version inside the package is the one of the table; the file names do not carry the tilde (GitHub rewrites it in the
name of an asset): the files for `0.4.2rc1-1` are `hecate_0.4.2rc1-1_amd64.deb`, `hecate-0.4.2rc1-1.x86_64.rpm`,
`hecate-0.4.2rc1-1-x86_64.pkg.tar.zst` and `hecate-0.4.2_rc1-r1.x86_64.apk`.

## What comes later

This is the first way to install hecate, and it is deliberately plain. Not available yet:

- packages for arm64 (the Linux packages and the archive are built for x86_64 only);
- apt, dnf, pacman and apk repositories, which would give updates through the system and signed packages;
- Homebrew, Scoop, winget, the AUR and a macOS installer;
- signing: the packages and the archives are checked by their `.sha256` and their attestation, not by a signature of a key.

To install `hecate` in a CI workflow of your project, use the setup action instead; see
[Deliver to a server](deliver-to-a-server.md).
