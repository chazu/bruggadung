# Linux, to build and test everything: clang (Triangle's C, and Odin's
# linker driver), make, Python (Triangle's tool tests), git (the revision
# Triangle's build stamps), and Odin's release, pinned (as in install-odin.sh).
# The repository is mounted from the host, owned by another user, so git is
# told to trust it.
#
#   docker build -t bruggadung ci
#   docker run --rm -v "$PWD":/repo -w /repo bruggadung make check-lab
FROM ubuntu:24.04

ARG ODIN=dev-2026-10
ARG TARGETARCH

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        clang lld make ca-certificates curl git python3 \
    && rm -rf /var/lib/apt/lists/* \
    && git config --system --add safe.directory '*'

RUN arch=$([ "$TARGETARCH" = arm64 ] && echo arm64 || echo amd64) \
    && curl -fsSL "https://github.com/odin-lang/Odin/releases/download/$ODIN/odin-linux-$arch-$ODIN.tar.gz" \
       | tar -xz -C /opt \
    && ln -s /opt/odin-linux-$arch-*/odin /usr/local/bin/odin \
    && odin version

ENV CC=clang
WORKDIR /repo
