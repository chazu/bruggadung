#!/bin/sh
# Windows: run in an MSYS2 shell (any environment) to install what the lab
# and Triangle build with, into MSYS2's clang64 environment. Then build from
# a CLANG64 shell: make -C lab check
set -e
pacman -S --needed --noconfirm $(cat "$(dirname "$0")/packages.txt")
