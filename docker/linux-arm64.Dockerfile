FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

# Native build tools
RUN apt-get update && apt-get install -y \
    build-essential \
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
    && rm -rf /var/lib/apt/lists/*

# ARM64 cross toolchain (separate step to isolate failures)
RUN dpkg --add-architecture arm64 && \
    apt-get update && apt-get install -y \
    crossbuild-essential-arm64 \
    libglib2.0-dev:arm64 \
    libmount-dev:arm64 \
    libselinux1-dev:arm64 \
    zlib1g-dev:arm64 \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --upgrade pip && pip3 install 'meson>=1.4'

ENV ARCH=aarch64
ENV CROSS_COMPILE=aarch64-linux-gnu-
ENV PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig

WORKDIR /workspace
