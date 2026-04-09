FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Build dependencies from riscv-gnu-toolchain README (Ubuntu)
RUN apt-get update && apt-get install -y \
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
    libncurses-dev \
    python-is-python3 \
    && rm -rf /var/lib/apt/lists/*

# Build args — used to fix file ownership on the mounted output volume
ARG HOST_UID=1000
ARG HOST_GID=1000
ENV HOST_UID=${HOST_UID}
ENV HOST_GID=${HOST_GID}

COPY build-toolchain.sh /usr/local/bin/build-toolchain.sh
RUN chmod +x /usr/local/bin/build-toolchain.sh

# Wrapper: run the build then fix ownership so the host user owns the output
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
