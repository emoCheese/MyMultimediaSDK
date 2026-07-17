FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
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
    libglib2.0-dev \
    libmount-dev \
    libselinux1-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --upgrade pip && pip3 install 'meson>=1.4'

WORKDIR /workspace
