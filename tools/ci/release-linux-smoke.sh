#!/bin/sh
# Installs a release package with the tool of the distribution, INSIDE a container of that distribution, and runs it
# (run by .github/workflows/release.yml with `docker run`, the packages mounted read-only at /packages and this
# directory at /ci):
#
#   docker run --rm -v "$PWD/dist:/packages:ro" -v "$PWD/tools/ci:/ci:ro" -e HECATE_VERSION=0.1.0 debian:12 sh /ci/release-linux-smoke.sh deb
#
# The format is deb, rpm, archlinux or apk. HECATE_VERSION is `X.Y.Z[pre]`, the content of the VERSION file: `hecate
# version` must print `Hecate <HECATE_VERSION> (...)`. Checks: the install, `hecate version`, `hecate completion bash`, the
# three completion files, and the removal. Exit status 0 when all of that works.
set -eu

format="${1:?usage: release-linux-smoke.sh deb|rpm|archlinux|apk}"
: "${HECATE_VERSION:?HECATE_VERSION is required}"
cd /packages

case "$format" in
  deb)
    package=$(ls hecate_*.deb)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y "./$package"
    dpkg -s hecate
    dpkg -L hecate
    remove() { apt-get remove -y hecate; }
    ;;
  rpm)
    package=$(ls hecate-*.rpm)
    dnf -y install "./$package"
    rpm -qi hecate
    rpm -ql hecate
    remove() { dnf -y remove hecate; }
    ;;
  archlinux)
    package=$(ls hecate-*.pkg.tar.zst)
    pacman -U --noconfirm "./$package"
    pacman -Qi hecate
    pacman -Ql hecate
    remove() { pacman -R --noconfirm hecate; }
    ;;
  apk)
    package=$(ls hecate-*.apk)
    # Unsigned: there is no project key yet.
    apk add --no-cache --allow-untrusted "./$package"
    apk info -L hecate
    remove() { apk del hecate; }
    ;;
  *) echo "unknown format: $format" >&2; exit 2 ;;
esac

hecate version
version=$(hecate version | head -n 1)
case "$version" in
  "Hecate $HECATE_VERSION ("*) echo "version ok: $version" ;;
  *) echo "expected 'Hecate $HECATE_VERSION (...)', got '$version'" >&2; exit 1 ;;
esac

script=$(hecate completion bash)
if [ -z "$script" ]; then echo "hecate completion bash printed nothing" >&2; exit 1; fi
hecate completion zsh >/dev/null
hecate completion fish >/dev/null

for file in /usr/share/bash-completion/completions/hecate /usr/share/zsh/site-functions/_hecate /usr/share/fish/vendor_completions.d/hecate.fish; do
  if [ ! -s "$file" ]; then echo "missing or empty: $file" >&2; exit 1; fi
done
if command -v bash >/dev/null 2>&1; then bash -n /usr/share/bash-completion/completions/hecate; fi
test -x /usr/bin/hecate

remove
hash -r 2>/dev/null || true
if command -v hecate >/dev/null 2>&1; then echo "hecate is still installed after the removal" >&2; exit 1; fi
if [ -e /usr/share/bash-completion/completions/hecate ]; then echo "the completion file is still there after the removal" >&2; exit 1; fi
echo "smoke test passed: $package ($format)"
