FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture arm64 && \
    apt-get update && apt-get install -y \
    build-essential \
    meson \
    ninja-build \
    cmake \
    pkg-config \
    python3 \
    python3-pip \
    git \
    curl \
    ca-certificates \
    nasm \
    yasm \
    bison \
    flex \
    crossbuild-essential-arm64 \
    libglib2.0-dev:arm64 \
    libzstd-dev:arm64 \
    libffi-dev:arm64 \
    libmount-dev:arm64 \
    libselinux1-dev:arm64 \
    zlib1g-dev:arm64 \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --upgrade pip && pip3 install 'meson>=1.4'

# ARM64 cross-compilation toolchain
ENV ARCH=aarch64
ENV CROSS_COMPILE=aarch64-linux-gnu-
ENV PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig

WORKDIR /workspace
