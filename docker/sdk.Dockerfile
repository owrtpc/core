# SPDX-License-Identifier: Apache-2.0
# The official SDK contains x86_64 host tools, even for ARM targets.
FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
    gettext git libncurses-dev libssl-dev python3-setuptools rsync swig \
    unzip zlib1g-dev file wget zstd ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
