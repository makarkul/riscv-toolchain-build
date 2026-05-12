#!/usr/bin/env bash
# Container entrypoint:
#   1. Build the toolchain into the install prefix.
#   2. Assemble and emit the .deb to /dist.
#   3. Fix ownership of /opt/riscv-toolchain and /dist so the host user can
#      read the artefacts (the build itself ran as root).
set -euo pipefail

# Parse flags we care about (we forward everything to the build script).
PREFIX="/opt/riscv-toolchain"
SKIP_PKG=0
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --skip-package) SKIP_PKG=1 ;;
        *) ARGS+=("$arg") ;;
    esac
done

# Extract --prefix override if present (preserved in ARGS).
prev=""
for a in "${ARGS[@]:-}"; do
    if [[ "$prev" == "--prefix" ]]; then
        PREFIX="$a"
    fi
    prev="$a"
done

/usr/local/bin/build-toolchain.sh "${ARGS[@]:-}"

if [[ "$SKIP_PKG" -eq 0 ]]; then
    echo ""
    echo "==> Packaging into .deb ..."
    PKG_VERSION="${PKG_VERSION:-13.4.0-1}" \
    /usr/local/bin/package-deb.sh --prefix "$PREFIX" --version "$PKG_VERSION" --out /dist
fi

if [[ -n "${HOST_UID:-}" && -n "${HOST_GID:-}" ]]; then
    echo "==> Fixing ownership of $PREFIX, /build, /dist to $HOST_UID:$HOST_GID ..."
    chown -R "$HOST_UID:$HOST_GID" "$PREFIX" /build /dist 2>/dev/null || true
fi
