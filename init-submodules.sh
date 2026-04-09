#!/usr/bin/env bash
# One-time setup: add git submodules for all toolchain source repos
# and pin each to the exact version from temp_config.yaml.
#
# After running this script, commit the result:
#   git add .gitmodules sources/
#   git commit -m "Add toolchain source submodules"
#
# Subsequent clones only need:
#   git submodule update --init

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ---------------------------------------------------------------------------
# Ensure we are in a git repository
# ---------------------------------------------------------------------------
if [[ ! -d .git ]]; then
    echo "Error: not a git repository. Run 'git init' first."
    exit 1
fi

mkdir -p sources

# ---------------------------------------------------------------------------
# Helper: add a submodule if not already present, then checkout the exact ref
# ---------------------------------------------------------------------------
add_submodule() {
    local path="$1"
    local url="$2"
    local ref="$3"
    local name
    name="$(basename "$path")"

    echo ""
    echo "==> Setting up submodule: $path @ $ref"

    if [[ -f "$path/.git" ]] || [[ -d "$path/.git" ]]; then
        echo "    Already exists, checking out $ref"
    else
        git submodule add --name "$name" "$url" "$path"
    fi

    git -C "$path" fetch --all --tags
    git -C "$path" checkout "$ref"
}

# ---------------------------------------------------------------------------
# Pinned versions (from temp_config.yaml)
# ---------------------------------------------------------------------------

# Build framework
add_submodule sources/riscv-gnu-toolchain \
    https://github.com/riscv-software-src/riscv-gnu-toolchain.git \
    master

# GCC
add_submodule sources/gcc \
    https://gcc.gnu.org/git/gcc.git \
    releases/gcc-13.4.0

# Binutils (pinned to a specific commit on binutils-2_40-branch)
add_submodule sources/binutils \
    https://sourceware.org/git/binutils-gdb.git \
    e05406c548867d6467d47564f8f9d7cd338532a4

# Newlib
add_submodule sources/newlib \
    https://sourceware.org/git/newlib-cygwin.git \
    newlib-4.5.0

# GDB
add_submodule sources/gdb \
    https://sourceware.org/git/binutils-gdb.git \
    gdb-16.3-release

# Spike (InCore Semi fork)
add_submodule sources/spike \
    https://github.com/incoresemi/riscv-isa-sim.git \
    incoresemi

# ---------------------------------------------------------------------------
# Stage everything
# ---------------------------------------------------------------------------
echo ""
echo "==> Staging submodule changes..."
git add .gitmodules sources/

echo ""
echo "==> Done. Submodules initialized and pinned."
echo "    Review with: git submodule status"
echo "    Then commit: git commit -m 'Add toolchain source submodules'"
