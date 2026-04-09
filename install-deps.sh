#!/usr/bin/env bash
# Install build dependencies for riscv-gnu-toolchain on Ubuntu 24.04 or Fedora.
set -euo pipefail

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

OS=$(detect_os)

case "$OS" in
    ubuntu|debian)
        echo "==> Detected Ubuntu/Debian — installing with apt..."
        sudo apt-get update
        sudo apt-get install -y \
            autoconf \
            automake \
            autotools-dev \
            curl \
            python3 \
            python3-pip \
            python3-tomli \
            libmpc-dev \
            libmpfr-dev \
            libgmp-dev \
            gawk \
            build-essential \
            bison \
            flex \
            texinfo \
            gperf \
            libtool \
            patchutils \
            bc \
            zlib1g-dev \
            libexpat-dev \
            ninja-build \
            git \
            cmake \
            libglib2.0-dev \
            libslirp-dev \
            libncurses-dev
        ;;

    fedora|rhel|centos)
        echo "==> Detected Fedora/RHEL/CentOS — installing with dnf..."
        sudo dnf install -y \
            autoconf \
            automake \
            python3 \
            python3-pip \
            libmpc-devel \
            mpfr-devel \
            gmp-devel \
            gawk \
            bison \
            flex \
            texinfo \
            patchutils \
            gcc \
            gcc-c++ \
            make \
            zlib-devel \
            expat-devel \
            libslirp-devel \
            ncurses-devel \
            ninja-build \
            git \
            cmake \
            glib2-devel \
            bc \
            libtool \
            gperf
        ;;

    *)
        echo "Error: Unsupported OS '$OS'."
        echo "Please install dependencies manually. See:"
        echo "  https://github.com/riscv-software-src/riscv-gnu-toolchain#prerequisites"
        exit 1
        ;;
esac

echo ""
echo "==> Dependencies installed. You can now run:"
echo "    ./build-toolchain.sh [--prefix <path>] [--jobs <n>]"
