FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Base image is ubuntu:22.04 (jammy, glibc 2.35) so the toolchain host binaries
# we produce reference at most GLIBC_2.35 — the resulting .deb is then
# installable on both Ubuntu 22.04 (jammy) and 24.04 (noble, glibc 2.39).
RUN apt-get update && apt-get install -y \
    autoconf \
    automake \
    autotools-dev \
    curl \
    python3 \
    python3-dev \
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
    xz-utils \
    dpkg-dev \
    file \
    rsync \
    && rm -rf /var/lib/apt/lists/*

ARG HOST_UID=1000
ARG HOST_GID=1000
ENV HOST_UID=${HOST_UID}
ENV HOST_GID=${HOST_GID}

COPY build-toolchain.sh /usr/local/bin/build-toolchain.sh
COPY package-deb.sh     /usr/local/bin/package-deb.sh
RUN chmod +x /usr/local/bin/build-toolchain.sh /usr/local/bin/package-deb.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
