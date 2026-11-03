#!/bin/sh
# Odin's release, pinned (as in the Dockerfile), into a directory (default
# ./.odin), for the Mac and for Windows under MSYS2; Linux uses this
# directory's Dockerfile. Prints the directory that holds the odin
# executable, to put on PATH.
#
#   sh ci/install-odin.sh [dir]
set -eu
ODIN=dev-2026-10
DIR=${1:-.odin}

case "$(uname -s)" in
    Darwin)                 asset=odin-macos-arm64-$ODIN.tar.gz ;;
    MINGW*|MSYS*|CYGWIN*)   asset=odin-windows-amd64-$ODIN.zip ;;
    *) echo "install-odin: on Linux, use ci/Dockerfile" >&2; exit 1 ;;
esac

mkdir -p "$DIR"
curl -fsSL -o "$DIR/$asset" "https://github.com/odin-lang/Odin/releases/download/$ODIN/$asset"
case "$asset" in
    *.zip) (cd "$DIR" && unzip -q -o "$asset") ;;
    *)     tar -xzf "$DIR/$asset" -C "$DIR" ;;
esac
dirname "$(find "$DIR" -name 'odin' -type f -perm -u+x -o -name 'odin.exe' -type f | head -1)"
