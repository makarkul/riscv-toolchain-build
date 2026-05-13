#!/usr/bin/env bash
# Assemble a Debian .deb from the built toolchain tree.
#
# Runs inside the build container after build-toolchain.sh completes.
# Produces: <out>/riscv-toolchain_<version>_amd64.deb
#
# The package installs the entire toolchain payload under /opt/riscv-toolchain.
# Depends are scoped so the .deb installs cleanly on both Ubuntu 22.04 jammy
# and 24.04 noble.

set -euo pipefail

PREFIX="/opt/riscv-toolchain"
VERSION="${PKG_VERSION:-13.4.0-1}"
OUT="/dist"
PKG_NAME="riscv-toolchain"
ARCH="amd64"
MAINTAINER="sampigesemi <ops@sampigesemi.local>"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)  PREFIX="$2";  shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --out)     OUT="$2";     shift 2 ;;
        --name)    PKG_NAME="$2"; shift 2 ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ ! -d "$PREFIX" ]] || [[ -z "$(ls -A "$PREFIX" 2>/dev/null || true)" ]]; then
    echo "ERROR: install prefix $PREFIX is empty — build did not produce output"
    exit 1
fi

mkdir -p "$OUT"

# Strip the leading '/' from the install path so we get pkgroot/opt/riscv-toolchain
INSTALL_REL="${PREFIX#/}"
PKGROOT="$(mktemp -d -t riscv-deb-XXXX)"
trap 'rm -rf "$PKGROOT"' EXIT

mkdir -p "$PKGROOT/DEBIAN" "$PKGROOT/$(dirname "$INSTALL_REL")"

echo "==> Copying toolchain payload to $PKGROOT/$INSTALL_REL ..."
cp -a "$PREFIX" "$PKGROOT/$INSTALL_REL"

# Drop a profile.d snippet so users on PATH get /opt/riscv-toolchain/bin
mkdir -p "$PKGROOT/etc/profile.d"
cat > "$PKGROOT/etc/profile.d/riscv-toolchain.sh" <<'EOF'
# Added by the riscv-toolchain Debian package
if [ -d /opt/riscv-toolchain/bin ]; then
    case ":$PATH:" in
        *":/opt/riscv-toolchain/bin:"*) ;;
        *) export PATH="/opt/riscv-toolchain/bin:$PATH" ;;
    esac
fi
EOF
chmod 0644 "$PKGROOT/etc/profile.d/riscv-toolchain.sh"

# Compute installed size in KB (per Debian Policy 5.6.20).
INSTALLED_SIZE=$(du -sk "$PKGROOT" | cut -f1)

cat > "$PKGROOT/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${VERSION}
Section: devel
Priority: optional
Architecture: ${ARCH}
Installed-Size: ${INSTALLED_SIZE}
Maintainer: ${MAINTAINER}
Depends: libc6 (>= 2.34), libexpat1, zlib1g, libtinfo6, libncurses6
Recommends: make, gdb-multiarch
Description: RISC-V GNU cross-toolchain with InCore P-extension support
 Full multilib RISC-V GNU toolchain bundling:
   - gcc 13.4.0
   - binutils 2.40
   - newlib 4.5.0
   - gdb 16.3 (cross gdb for riscv targets)
   - spike (riscv-isa-sim, incoresemi fork)
 .
 Built with the InCore Semi psimd patches enabled (zpn, zpsf, zbpbo). Host
 helper libs (libgmp, libmpfr, libmpc, libstdc++) are statically linked so the
 same .deb installs cleanly on Ubuntu 22.04 jammy and 24.04 noble.
 .
 Installs to /opt/riscv-toolchain. A /etc/profile.d snippet prepends
 /opt/riscv-toolchain/bin to PATH for interactive shells.
EOF

# Optional postinst: nothing to ldconfig since everything is self-contained
# under /opt, but write a minimal one that prints a hint on first install.
cat > "$PKGROOT/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
case "$1" in
    configure)
        echo "riscv-toolchain: installed to /opt/riscv-toolchain"
        echo "  Log in a fresh shell or run: export PATH=/opt/riscv-toolchain/bin:\$PATH"
        ;;
esac
exit 0
EOF
chmod 0755 "$PKGROOT/DEBIAN/postinst"

# All files must be owned by root in the .deb
chown -R 0:0 "$PKGROOT"
find "$PKGROOT" -type d -exec chmod 0755 {} +

DEB_PATH="$OUT/${PKG_NAME}_${VERSION}_${ARCH}.deb"
echo "==> Building $DEB_PATH ..."
dpkg-deb -Zxz -z9 --build "$PKGROOT" "$DEB_PATH"

echo ""
echo "==> Package summary:"
dpkg-deb -I "$DEB_PATH"
echo ""
echo "==> Package contents (top 20):"
dpkg-deb -c "$DEB_PATH" | head -20
echo "    ..."
echo "    ($(dpkg-deb -c "$DEB_PATH" | wc -l) total entries)"

echo ""
echo "==> .deb produced: $DEB_PATH"
echo "    Size: $(du -h "$DEB_PATH" | cut -f1)"
