#!/usr/bin/env bash
# Build the RISC-V GNU toolchain from source repos mounted into the container.
#
# Sources are bind-mounted at /src/ by docker-compose:
#   /src/riscv-gnu-toolchain  — build framework (Makefile, configure, scripts)
#   /src/gcc                  — GCC sources
#   /src/binutils             — Binutils sources
#   /src/newlib               — Newlib sources
#   /src/gdb                  — GDB sources
#   /src/spike                — Spike simulator sources
#
# Usage:
#   ./build-toolchain.sh [--prefix <path>] [--jobs <n>]
#
# Defaults:
#   --prefix  /riscv_toolchain
#   --jobs    nproc

set -euo pipefail

PREFIX="/riscv_toolchain"
JOBS="$(nproc)"
WORKSPACE="/tmp/riscv-build"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2 ;;
        --jobs)   JOBS="$2";   shift 2 ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--prefix <path>] [--jobs <n>]"
            exit 1
            ;;
    esac
done

echo "==> Build configuration:"
echo "    PREFIX    : $PREFIX"
echo "    JOBS      : $JOBS"
echo "    WORKSPACE : $WORKSPACE"
echo ""

# ---------------------------------------------------------------------------
# Verify source mounts
# ---------------------------------------------------------------------------
SRC_FRAMEWORK="/src/riscv-gnu-toolchain"
SUBMODULES=(gcc binutils newlib gdb spike)

for dir in "$SRC_FRAMEWORK" "${SUBMODULES[@]/#//src/}"; do
    if [[ ! -d "$dir" ]]; then
        echo "ERROR: Source directory not found: $dir"
        echo "Are the source volumes mounted? Check docker-compose.yml"
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# Multilib generator (from temp_config.yaml)
# ---------------------------------------------------------------------------
MULTILIB_GENERATOR="\
rv32imfc_zba_zbb_zbc_zbpbo_zbs_zicsr_zifencei_zpn_zpsf-ilp32f--;\
rv32imc_zba_zbb_zbc_zbpbo_zbs_zicsr_zifencei_zpn_zpsf-ilp32--;\
rv32imf_zba_zbb_zbc_zbpbo_zbs_zicsr_zifencei_zpn_zpsf-ilp32f--;\
rv32im_zba_zbb_zbc_zbpbo_zbs_zicsr_zifencei_zpn_zpsf-ilp32--;\
rv64im_zba_zbb_zbc_zbpbo_zbs_zicsr_zifencei_zpn_zpsf-lp64--;\
rv64imf_zba_zbb_zbc_zbpbo_zbs_zicsr_zifencei_zpn_zpsf-lp64f--;\
rv64imc_zba_zbb_zbc_zbpbo_zbs_zicsr_zifencei_zpn_zpsf-lp64--;\
rv64imfc_zba_zbb_zbc_zbpbo_zbs_zicsr_zifencei_zpn_zpsf-lp64f--;\
rv64i_zicsr_zifencei-lp64--"

# ---------------------------------------------------------------------------
# Prepare build workspace
# ---------------------------------------------------------------------------
echo "==> Preparing build workspace..."
rm -rf "$WORKSPACE"
mkdir -p "$WORKSPACE"

# Copy the framework (Makefiles, configure, scripts — small, no source trees)
cp -a "$SRC_FRAMEWORK"/. "$WORKSPACE/"

# Remove any empty submodule dirs from the framework copy
# and replace with symlinks to our mounted sources
for mod in "${SUBMODULES[@]}"; do
    rm -rf "$WORKSPACE/$mod"
    ln -s "/src/$mod" "$WORKSPACE/$mod"
done

# Also create riscv-gdb symlink for older framework compatibility
ln -sf "/src/gdb" "$WORKSPACE/riscv-gdb"

cd "$WORKSPACE"

# ---------------------------------------------------------------------------
# Configure + build
# ---------------------------------------------------------------------------
echo ""
echo "==> Configuring..."
mkdir -p "$PREFIX"

./configure \
    --prefix="$PREFIX" \
    --with-arch=rv64im_zicsr_zifencei \
    --with-abi=lp64 \
    --with-cmodel=medany \
    --with-multilib-generator="$MULTILIB_GENERATOR"

echo ""
echo "==> Building with -j$JOBS ..."
make newlib -j"$JOBS"

echo ""
echo "==> Done. Toolchain installed to $PREFIX"
echo "    Add to PATH: export PATH=\"$PREFIX/bin:\$PATH\""
