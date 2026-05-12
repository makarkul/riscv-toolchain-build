#!/usr/bin/env bash
# Build the RISC-V GNU toolchain from source repos mounted into the container.
#
# Sources are bind-mounted read-only at /src/ by docker-compose:
#   /src/riscv-gnu-toolchain  — build framework (Makefile, configure, scripts)
#   /src/gcc                  — GCC sources
#   /src/binutils             — Binutils sources
#   /src/newlib               — Newlib sources
#   /src/gdb                  — GDB sources
#   /src/spike                — Spike simulator sources
#   /src/patches              — psimd-gcc.patch, psimd-binutils.patch
#
# This script:
#   1. Copies sources into a writable workspace (/build, a docker named volume).
#   2. Applies the psimd patches to gcc and binutils.
#   3. Configures riscv-gnu-toolchain with full multilib (per temp_config.yaml)
#      and static-links host libgmp/mpfr/mpc/libstdc++/libgcc so the produced
#      binaries are forward-compatible across distros.
#   4. Builds `make newlib` (gcc + binutils + newlib + multilibs), gdb, spike.
#   5. Strips host binaries.
#   6. Verifies that every dynamic glibc symbol is <= GLIBC_2.35.

set -euo pipefail

PREFIX="/opt/riscv-toolchain"
JOBS="$(nproc)"
WORKSPACE="/build"
PATCHES_DIR="/src/patches"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)    PREFIX="$2";    shift 2 ;;
        --jobs)      JOBS="$2";      shift 2 ;;
        --workspace) WORKSPACE="$2"; shift 2 ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--prefix <path>] [--jobs <n>] [--workspace <path>]"
            exit 1
            ;;
    esac
done

echo "==> Build configuration:"
echo "    PREFIX     : $PREFIX"
echo "    JOBS       : $JOBS"
echo "    WORKSPACE  : $WORKSPACE"
echo "    PATCHES    : $PATCHES_DIR"
echo ""

SRC_FRAMEWORK="/src/riscv-gnu-toolchain"
SUBMODULES=(gcc binutils newlib gdb spike)

for dir in "$SRC_FRAMEWORK" "${SUBMODULES[@]/#//src/}"; do
    if [[ ! -d "$dir" ]]; then
        echo "ERROR: Source directory not found: $dir"
        echo "Are the source volumes mounted? Check docker-compose.yml"
        exit 1
    fi
done

if [[ ! -d "$PATCHES_DIR" ]]; then
    echo "ERROR: Patches directory not found: $PATCHES_DIR"
    exit 1
fi

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
# Stage sources into a writable workspace (the bind-mounts at /src are ro)
# ---------------------------------------------------------------------------
echo "==> Staging sources into $WORKSPACE ..."
mkdir -p "$WORKSPACE"
SRCDIR="$WORKSPACE/sources"
WORK="$WORKSPACE/work"

mkdir -p "$SRCDIR"
for mod in "${SUBMODULES[@]}"; do
    echo "    sync $mod"
    rsync -a --delete --exclude='.git' "/src/$mod/" "$SRCDIR/$mod/"
done

# ---------------------------------------------------------------------------
# Apply psimd patches (idempotent by checksum)
# ---------------------------------------------------------------------------
apply_patch_idempotent() {
    local target_dir="$1"
    local patch_file="$2"
    local tag_file="$target_dir/.psimd-patched"
    local sum
    sum="$(sha256sum "$patch_file" | cut -d' ' -f1)"

    if [[ -f "$tag_file" ]] && [[ "$(cat "$tag_file")" == "$sum" ]]; then
        echo "    already patched: $(basename "$patch_file")"
        return 0
    fi

    echo "    applying: $(basename "$patch_file") -> $target_dir"
    (cd "$target_dir" && patch -p1 --forward --no-backup-if-mismatch < "$patch_file")
    echo "$sum" > "$tag_file"
}

echo "==> Applying patches ..."
apply_patch_idempotent "$SRCDIR/binutils" "$PATCHES_DIR/psimd-binutils.patch"
apply_patch_idempotent "$SRCDIR/gcc"      "$PATCHES_DIR/psimd-gcc.patch"

# ---------------------------------------------------------------------------
# Prepare build tree (framework + symlinks to patched sources)
# ---------------------------------------------------------------------------
echo "==> Preparing build tree at $WORK ..."
rm -rf "$WORK"
mkdir -p "$WORK"
rsync -a --exclude='.git' "$SRC_FRAMEWORK/" "$WORK/"

for mod in "${SUBMODULES[@]}"; do
    rm -rf "$WORK/$mod"
    ln -s "$SRCDIR/$mod" "$WORK/$mod"
done
ln -sf "$SRCDIR/gdb" "$WORK/riscv-gdb"

cd "$WORK"

# ---------------------------------------------------------------------------
# Configure
# ---------------------------------------------------------------------------
# Static-link host helper libs so the cross binaries don't depend on
# distro-specific libstdc++ / libgmp / libmpc / libmpfr. glibc stays dynamic
# (full-static glibc breaks gcc's dlopen-based plugins and NSS).
HOST_STATIC_LDFLAGS="-static-libgcc -static-libstdc++ -Wl,-Bstatic -lmpc -lmpfr -lgmp -Wl,-Bdynamic"
HOST_LIBSTDCXX='-static-libstdc++ -static-libgcc -Wl,-Bstatic -lstdc++ -Wl,-Bdynamic'

echo ""
echo "==> Configuring ..."
mkdir -p "$PREFIX"

./configure \
    --prefix="$PREFIX" \
    --with-arch=rv64im_zicsr_zifencei \
    --with-abi=lp64 \
    --with-cmodel=medany \
    --with-host-libstdcxx="$HOST_LIBSTDCXX" \
    --with-multilib-generator="$MULTILIB_GENERATOR"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
echo ""
echo "==> Building newlib + multilibs with -j$JOBS ..."
make newlib -j"$JOBS" \
    LDFLAGS_FOR_HOST="$HOST_STATIC_LDFLAGS" \
    LDFLAGS_FOR_BUILD="$HOST_STATIC_LDFLAGS"

# gdb (cross gdb for riscv targets) — the framework exposes a `gdb` target on
# recent revisions; if not present, skip with a warning.
if grep -q '^gdb:' Makefile 2>/dev/null; then
    echo ""
    echo "==> Building gdb with -j$JOBS ..."
    make gdb -j"$JOBS" \
        LDFLAGS_FOR_HOST="$HOST_STATIC_LDFLAGS" \
        LDFLAGS_FOR_BUILD="$HOST_STATIC_LDFLAGS" || \
        echo "WARN: gdb build failed — continuing without gdb"
fi

# spike (riscv-isa-sim).
if grep -q '^spike:' Makefile 2>/dev/null; then
    echo ""
    echo "==> Building spike via framework target ..."
    make spike -j"$JOBS" || true
fi

if [[ ! -x "$PREFIX/bin/spike" ]]; then
    echo ""
    echo "==> Building spike directly ..."
    SPIKE_BUILD="$WORKSPACE/spike-build"
    rm -rf "$SPIKE_BUILD"
    mkdir -p "$SPIKE_BUILD"
    if [[ -x "$SRCDIR/spike/configure" ]]; then
        (
            cd "$SPIKE_BUILD"
            "$SRCDIR/spike/configure" --prefix="$PREFIX" \
                CXXFLAGS="-O2 -static-libstdc++ -static-libgcc" \
                LDFLAGS="-static-libstdc++ -static-libgcc"
            make -j"$JOBS"
            make install
        ) || echo "WARN: spike configure/build failed"
    elif [[ -f "$SRCDIR/spike/CMakeLists.txt" ]]; then
        (
            cmake -S "$SRCDIR/spike" -B "$SPIKE_BUILD" \
                -DCMAKE_INSTALL_PREFIX="$PREFIX" \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_EXE_LINKER_FLAGS="-static-libstdc++ -static-libgcc"
            cmake --build "$SPIKE_BUILD" -j"$JOBS"
            cmake --install "$SPIKE_BUILD"
        ) || echo "WARN: spike cmake build failed"
    fi
fi

# ---------------------------------------------------------------------------
# Strip host binaries (saves ~50% .deb size)
# ---------------------------------------------------------------------------
echo ""
echo "==> Stripping host binaries ..."
find "$PREFIX/bin" "$PREFIX/libexec" -type f 2>/dev/null | while read -r f; do
    if file -b "$f" | grep -q 'ELF .* x86-64'; then
        strip --strip-unneeded "$f" 2>/dev/null || true
    fi
done

# ---------------------------------------------------------------------------
# Verify glibc symbol versions on host binaries
# ---------------------------------------------------------------------------
echo ""
echo "==> Verifying glibc symbol versions <= 2.35 ..."
MAX_GLIBC="2.35"
FAIL=0
for bin in "$PREFIX"/bin/*; do
    [[ -f "$bin" ]] || continue
    file -b "$bin" 2>/dev/null | grep -q 'ELF .* x86-64' || continue
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        if [[ "$(printf '%s\n%s\n' "$MAX_GLIBC" "$v" | sort -V | tail -1)" != "$MAX_GLIBC" ]]; then
            echo "  FAIL: $bin needs GLIBC_$v"
            FAIL=1
        fi
    done < <(readelf -V "$bin" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sed 's/GLIBC_//' | sort -u)
done

if [[ "$FAIL" -ne 0 ]]; then
    echo "ERROR: at least one host binary references glibc > $MAX_GLIBC."
    echo "       The resulting .deb will not install on Ubuntu 22.04 jammy."
    exit 1
fi

echo "    OK — all host binaries reference at most GLIBC_$MAX_GLIBC"
echo ""
echo "==> Toolchain built and installed to $PREFIX"
echo "    Add to PATH: export PATH=\"$PREFIX/bin:\$PATH\""
