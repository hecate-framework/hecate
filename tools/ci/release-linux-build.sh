#!/bin/sh
# Builds and packages the Linux release INSIDE a container (run by .github/workflows/release.yml with `docker run`, the
# checkout mounted at /work; it also runs on a developer machine with docker, same result):
#
#   docker run --rm -v "$PWD:/work" -w /work -e CI=true -e RELEASE_VERSION=0.1.0-1 almalinux:8 sh tools/ci/release-linux-build.sh glibc
#   docker run --rm -v "$PWD:/work" -w /work -e CI=true -e RELEASE_VERSION=0.1.0-1 alpine:3.20  sh tools/ci/release-linux-build.sh musl
#
# glibc (AlmaLinux 8, glibc 2.28, the floor of the release: older than every supported Debian, Ubuntu and RHEL): the
#   dynamic executable, then the archive, the .deb, the .rpm and the Arch package, all of that one executable.
# musl (Alpine 3.20): the executable linked statically (`build-cli --static`), then the .apk.
#
# The logic is in the tasks (`build-cli`, `package-cli`); this script only provisions the container. Output:
# .hecate/release/dist-<flavour>/ (the packages and their .sha256). Environment: RELEASE_VERSION (X.Y.Z[pre]-R, required),
# HOST_UID and HOST_GID (optional: who owns the files written under .hecate/ when the script ends).
set -eu

flavour="${1:?usage: release-linux-build.sh glibc|musl}"
: "${RELEASE_VERSION:?RELEASE_VERSION is required}"
root=$(pwd)
toolchain="$root/.hecate/toolchain-$flavour"
build="$root/.hecate/release/build-$flavour"
dist="$root/.hecate/release/dist-$flavour"

if [ -n "${HOST_UID:-}" ]; then
  # The mounted checkout belongs to the runner user, the container runs as root: give the new files back.
  trap 'chown -R "$HOST_UID:${HOST_GID:-$HOST_UID}" "$root/.hecate" 2>/dev/null || true' EXIT
fi

case "$flavour" in
  glibc)
    # `--allowerasing`: the image may carry curl-minimal, which conflicts with curl.
    dnf -y install --allowerasing gcc make cmake git curl tar gzip unzip which binutils findutils diffutils zstd rpm-build ca-certificates
    ;;
  musl)
    # bash: the bootstrap script is a bash script; linux-headers: libuv.
    apk add --no-cache build-base cmake git curl tar gzip unzip bash binutils zstd linux-headers ca-certificates coreutils findutils
    # The Rust encoder is linked into a static executable together with the system musl: it must not carry its own
    # libc (rustc's musl targets default to crt-static, which bundles one into a staticlib).
    export RUSTFLAGS="-C target-feature=-crt-static"
    ;;
  *) echo "unknown flavour: $flavour" >&2; exit 2 ;;
esac

# The checkout is owned by another user than root.
git config --global --add safe.directory '*'

echo "::group::Lua toolchain"
if [ ! -x "$toolchain/bin/lua" ]; then
  bash tools/bootstrap/bootstrap.sh --prefix "$toolchain"
fi
export PATH="$toolchain/bin:$PATH"
export LUA_DIR="$toolchain"
echo "::endgroup::"

echo "::group::Rust toolchain"
if ! command -v rustup >/dev/null 2>&1 && [ ! -x "$HOME/.cargo/bin/rustup" ]; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain none
fi
. "$HOME/.cargo/env"
# The toolchain pinned by rust-toolchain.toml, which cargo would not pick up from the repository root.
(cd packages/json/native && rustup toolchain install)
RUSTUP_TOOLCHAIN=$(sed -n 's/^channel *= *"\(.*\)"/\1/p' packages/json/native/rust-toolchain.toml)
export RUSTUP_TOOLCHAIN
cargo --version
echo "::endgroup::"

cc --version | head -n 1

echo "::group::build-cli"
static=""
if [ "$flavour" = musl ]; then static="--static"; fi
# shellcheck disable=SC2086
lua tools/run.lua build-cli --strict $static "--output=$build/hecate"
echo "::endgroup::"

# The executable must run in the container that built it (package-cli runs it to print the completions).
"$build/hecate" version
if command -v readelf >/dev/null 2>&1; then readelf -d "$build/hecate" | grep NEEDED || echo "no shared library needed"; fi

rm -rf "$dist"
if [ "$flavour" = glibc ]; then
  # The default of --max-glibc is the floor (2.28): a newer symbol version fails the task.
  lua tools/run.lua package-cli "--version=$RELEASE_VERSION" "--exe=$build/hecate" "--out=$dist"
  for format in deb rpm archlinux; do
    lua tools/run.lua package-cli "--version=$RELEASE_VERSION" "--exe=$build/hecate" "--out=$dist" "--format=$format"
  done
  rpm -qp --info "$dist"/*.rpm
  rpm -qp --list "$dist"/*.rpm
  rpm -qp --requires "$dist"/*.rpm
else
  lua tools/run.lua package-cli "--version=$RELEASE_VERSION" "--exe=$build/hecate" "--out=$dist" --format=apk --max-glibc=none
fi
ls -l "$dist"
