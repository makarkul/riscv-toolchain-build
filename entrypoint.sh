#!/usr/bin/env bash
# Runs the toolchain build then fixes ownership of the output directory
# so the host user (not root) owns the installed files.
set -euo pipefail

/usr/local/bin/build-toolchain.sh "$@"

# Fix ownership — HOST_UID/HOST_GID are passed in as env vars from docker compose
if [[ -n "${HOST_UID:-}" && -n "${HOST_GID:-}" ]]; then
    PREFIX="/riscv_toolchain"
    # Extract --prefix if passed explicitly
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prefix) PREFIX="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    echo "==> Fixing ownership of $PREFIX to $HOST_UID:$HOST_GID ..."
    chown -R "$HOST_UID:$HOST_GID" "$PREFIX"
fi
