#!/usr/bin/env bash
# Build the RISC-V GNU toolchain inside an Ubuntu 22.04 container, package it
# as a Debian .deb, and (optionally) push to Gemfury.
#
# Usage:
#   ./docker-build.sh [--output <dir>] [--dist <dir>] [--jobs <n>]
#                     [--version <ver>] [--rebuild] [--push|--no-push]
#                     [--skip-build]
#
# Options:
#   --output <dir>    Toolchain install prefix on the host
#                     (default: ./toolchain-output)
#   --dist <dir>      Directory the .deb is written to (default: ./dist)
#   --jobs <n>        Parallel build jobs (default: nproc)
#   --version <ver>   Debian package version string (default: 13.4.0-1)
#   --rebuild         Force Docker image rebuild with --no-cache
#   --push            Push the resulting .deb to Gemfury after a successful
#                     build (requires FURY_TOKEN env var).
#   --no-push         Skip the Gemfury push (default).
#   --skip-build      Don't run the build/package step; only push (useful when
#                     re-uploading an already-built .deb).
#
# Example:
#   FURY_TOKEN=... ./docker-build.sh --jobs 8 --push

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/toolchain-output"
DIST_DIR="$SCRIPT_DIR/dist"
JOBS="$(nproc)"
REBUILD=false
PUSH=false
SKIP_BUILD=false
PKG_VERSION="${PKG_VERSION:-13.4.0-1}"

usage() {
    sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)     OUTPUT_DIR="$(realpath -m "$2")"; shift 2 ;;
        --dist)       DIST_DIR="$(realpath -m "$2")"; shift 2 ;;
        --jobs)       JOBS="$2"; shift 2 ;;
        --version)    PKG_VERSION="$2"; shift 2 ;;
        --rebuild)    REBUILD=true; shift ;;
        --push)       PUSH=true; shift ;;
        --no-push)    PUSH=false; shift ;;
        --skip-build) SKIP_BUILD=true; shift ;;
        --help|-h)    usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
    echo "Error: docker not found. Install Docker and ensure you are in the 'docker' group."
    exit 1
fi

if ! docker info &>/dev/null; then
    echo "Error: cannot connect to Docker daemon."
    exit 1
fi

if ! docker compose version &>/dev/null 2>&1; then
    echo "Error: 'docker compose' (v2) not found."
    exit 1
fi

SOURCES_DIR="$SCRIPT_DIR/sources"
REQUIRED_SUBS=(riscv-gnu-toolchain gcc binutils newlib gdb spike)

if ! $SKIP_BUILD; then
    MISSING=()
    for sub in "${REQUIRED_SUBS[@]}"; do
        if [[ ! -d "$SOURCES_DIR/$sub/.git" ]] && [[ ! -f "$SOURCES_DIR/$sub/.git" ]]; then
            MISSING+=("$sub")
        fi
    done
    if [[ ${#MISSING[@]} -gt 0 ]]; then
        echo "Error: The following source submodules are not initialized:"
        for m in "${MISSING[@]}"; do echo "  - sources/$m"; done
        echo ""
        echo "Run 'git submodule update --init --recursive' first."
        exit 1
    fi
fi

mkdir -p "$OUTPUT_DIR" "$DIST_DIR"

export HOST_UID="$(id -u)"
export HOST_GID="$(id -g)"
export OUTPUT_DIR
export DIST_DIR
export PKG_VERSION

echo "==> Configuration:"
echo "    Output dir : $OUTPUT_DIR"
echo "    Dist dir   : $DIST_DIR"
echo "    Jobs       : $JOBS"
echo "    Version    : $PKG_VERSION"
echo "    Rebuild    : $REBUILD"
echo "    Push       : $PUSH"
echo "    Skip build : $SKIP_BUILD"
echo ""

if ! $SKIP_BUILD; then
    BUILD_ARGS=(--file "$SCRIPT_DIR/docker-compose.yml" build)
    if $REBUILD; then
        BUILD_ARGS+=(--no-cache)
    fi

    echo "==> Building Docker image (ubuntu:22.04 + toolchain deps)..."
    docker compose "${BUILD_ARGS[@]}"

    echo ""
    echo "==> Starting toolchain build + .deb packaging inside container..."
    echo "    Expect 4-8 hours of wall time on a 4-core host. Coffee time."
    echo ""

    docker compose \
        --file "$SCRIPT_DIR/docker-compose.yml" \
        run --rm \
        toolchain-builder \
        --prefix /opt/riscv-toolchain \
        --jobs "$JOBS"

    echo ""
    echo "==> Toolchain build complete."
    echo "    Install tree : $OUTPUT_DIR"
    echo "    .deb         : $DIST_DIR"
fi

if $PUSH; then
    if [[ -z "${FURY_TOKEN:-}" ]]; then
        echo "ERROR: --push requested but FURY_TOKEN is not set."
        echo "  Export FURY_TOKEN before running, or run ./push-gemfury.sh manually."
        exit 1
    fi
    echo ""
    echo "==> Pushing .deb to Gemfury..."
    cd "$SCRIPT_DIR"
    ./push-gemfury.sh
fi

echo ""
echo "==> All done."
