#!/usr/bin/env bash
# Build the RISC-V GNU toolchain inside an Ubuntu 24.04 container.
# No sudo required on the host — only docker group membership needed.
#
# Usage:
#   ./docker-build.sh [--output <dir>] [--jobs <n>] [--rebuild]
#
# Options:
#   --output <dir>   Where to install the toolchain on the host
#                    (default: ./toolchain-output)
#   --jobs <n>       Parallel build jobs (default: nproc)
#   --rebuild        Force rebuild of the Docker image (no cache)
#
# Example:
#   ./docker-build.sh --output /opt/riscv --jobs 8

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/toolchain-output"
JOBS="$(nproc)"
REBUILD=false

usage() {
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)  OUTPUT_DIR="$(realpath -m "$2")"; shift 2 ;;
        --jobs)    JOBS="$2"; shift 2 ;;
        --rebuild) REBUILD=true; shift ;;
        --help|-h) usage ;;
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
    echo "  - Is Docker running?"
    echo "  - Are you in the 'docker' group? (run: newgrp docker)"
    exit 1
fi

if ! docker compose version &>/dev/null 2>&1; then
    echo "Error: 'docker compose' (v2) not found. Update Docker Desktop or install the compose plugin."
    exit 1
fi

# ---------------------------------------------------------------------------
# Verify source submodules are initialized
# ---------------------------------------------------------------------------
SOURCES_DIR="$SCRIPT_DIR/sources"
REQUIRED_SUBS=(riscv-gnu-toolchain gcc binutils newlib gdb spike)
MISSING=()

for sub in "${REQUIRED_SUBS[@]}"; do
    if [[ ! -d "$SOURCES_DIR/$sub/.git" ]] && [[ ! -f "$SOURCES_DIR/$sub/.git" ]]; then
        MISSING+=("$sub")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "Error: The following source submodules are not initialized:"
    for m in "${MISSING[@]}"; do
        echo "  - sources/$m"
    done
    echo ""
    echo "Run './init-submodules.sh' first to clone all source dependencies."
    exit 1
fi

echo "==> All source submodules found."

# ---------------------------------------------------------------------------
# Prepare output directory
# ---------------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR"

echo "==> Configuration:"
echo "    Output dir : $OUTPUT_DIR"
echo "    Jobs       : $JOBS"
echo "    Rebuild    : $REBUILD"
echo ""

# ---------------------------------------------------------------------------
# Build the Docker image
# ---------------------------------------------------------------------------
BUILD_ARGS=(--file "$SCRIPT_DIR/docker-compose.yml" build)
if $REBUILD; then
    BUILD_ARGS+=(--no-cache)
fi

export HOST_UID="$(id -u)"
export HOST_GID="$(id -g)"
export OUTPUT_DIR

echo "==> Building Docker image (ubuntu:24.04 + toolchain deps)..."
docker compose "${BUILD_ARGS[@]}"

# ---------------------------------------------------------------------------
# Run the toolchain build inside the container
# ---------------------------------------------------------------------------
echo ""
echo "==> Starting toolchain build inside container..."
echo "    This will take a while (GCC build). Go get a coffee."
echo ""

docker compose \
    --file "$SCRIPT_DIR/docker-compose.yml" \
    run --rm \
    toolchain-builder \
    --prefix /riscv_toolchain \
    --jobs "$JOBS"

echo ""
echo "==> Toolchain built successfully."
echo "    Installed to: $OUTPUT_DIR"
echo ""
echo "    Add to PATH:"
echo "      export PATH=\"$OUTPUT_DIR/bin:\$PATH\""
