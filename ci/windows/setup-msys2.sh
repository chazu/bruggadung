#!/bin/sh
# Windows: run in an MSYS2 shell (any environment) to install what Triangle
# builds and tests with, into MSYS2's clang64 environment. Then, from a
# CLANG64 shell: make -C triangle CC=clang test cli-test lsp-test
#
# The lab and Tessera, in Odin, aren't built on Windows yet: Odin links for
# the MSVC ABI there (see triangle/Makefile's odin-lib).
set -e
pacman -S --needed --noconfirm $(cat "$(dirname "$0")/packages.txt")
