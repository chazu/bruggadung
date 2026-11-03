# Linux for the Odin spike: clang (Triangle's C, and Odin's linker driver),
# make, and Odin's release, pinned.
#
#   docker build -t bruggadung-odin lab/ci/odin
#   docker run --rm -v "$PWD":/repo -w /repo/lab bruggadung-odin make odin-spike
FROM ubuntu:24.04

ARG ODIN=dev-2026-10
ARG TARGETARCH

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        clang lld make ca-certificates curl python3 \
    && rm -rf /var/lib/apt/lists/*

RUN arch=$([ "$TARGETARCH" = arm64 ] && echo arm64 || echo amd64) \
    && curl -fsSL "https://github.com/odin-lang/Odin/releases/download/$ODIN/odin-linux-$arch-$ODIN.tar.gz" \
       | tar -xz -C /opt \
    && ln -s /opt/odin-linux-$arch-*/odin /usr/local/bin/odin \
    && odin version

ENV CC=clang
WORKDIR /repo
