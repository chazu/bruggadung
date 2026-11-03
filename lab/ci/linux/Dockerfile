# Linux: clang, and GNUstep's modern runtime (libobjc2) and Foundation
# (gnustep-base), from source, pinned. Distributions package GNUstep for GCC's
# runtime, which this build doesn't use.
#
#   docker build -t bruggadung-lab lab/ci/linux
#   docker run --rm -v "$PWD":/repo -w /repo/lab bruggadung-lab make check
FROM ubuntu:24.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        clang lld libclang-rt-18-dev cmake ninja-build git make pkg-config ca-certificates python3 \
        libffi-dev libxml2-dev libxslt1-dev libgnutls28-dev libicu-dev zlib1g-dev libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

ENV CC=clang CXX=clang++
WORKDIR /opt/src

RUN git clone --depth 1 --branch v2.3 https://github.com/gnustep/libobjc2.git \
    && cd libobjc2 && git submodule update --init --depth 1 \
    && cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DTESTS=OFF \
    && ninja -C build install && ldconfig

RUN git clone --depth 1 --branch make-2_9_3 https://github.com/gnustep/tools-make.git \
    && cd tools-make \
    && ./configure --with-library-combo=ng-gnu-gnu --with-runtime-abi=gnustep-2.2 \
    && make install

RUN . "$(gnustep-config --variable=GNUSTEP_MAKEFILES)/GNUstep.sh" \
    && git clone --depth 1 --branch base-1_31_1 https://github.com/gnustep/libs-base.git \
    && cd libs-base && ./configure && make -j"$(nproc)" && make install && ldconfig \
    && rm -rf /opt/src

WORKDIR /repo
