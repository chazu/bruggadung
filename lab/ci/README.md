# Building on each platform

The lab is Objective-C with manual retain/release, built with clang and the
lab's `Makefile`: Apple's Foundation on the Mac, GNUstep's (the libobjc2
runtime and gnustep-base) on Linux and Windows. Triangle is C11. The same
checks pass on all three, and every scenario ends in the same state on each:
`make check` compares them against `scenario-hashes.txt`.

| Platform | What to install | Then |
| --- | --- | --- |
| macOS | Xcode's command line tools | `make -C lab check` |
| Linux | clang, and libobjc2 2.3 with gnustep-make and gnustep-base 1.31.1 built from source: `linux/Dockerfile` does it, or is the image to build in | `docker build -t bruggadung-lab lab/ci/linux`, then `docker run --rm -v "$PWD":/repo -w /repo/lab bruggadung-lab make check` |
| Windows | MSYS2, then `sh lab/ci/windows/setup-msys2.sh` in an MSYS2 shell (clang, GNUstep, make, git, Python, into clang64) | in a CLANG64 shell, `make -C lab check` |

Triangle's suites, on any of them: `make -C triangle test cli-test lsp-test`
(on Linux and Windows, `CC=clang`).

`.github/workflows/build.yml` runs all of this on each push.

Notes:
- Distributions' GNUstep packages are built for GCC's Objective-C runtime;
  the lab uses libobjc2's, so Linux builds GNUstep from source.
- Blocks are off outside the Mac (`-fno-blocks`): the lab uses none, and with
  them on, clang 20 and later reject a block-scoped instance variable in
  gnustep-base 1.31's headers.
- UBSan on Linux needs compiler-rt's builtins (`--rtlib=compiler-rt`), which
  `make asan` passes; the image installs them.
- A toolchain whose linker can't read the SDK it finds (as when the command
  line tools are older than the SDK) can be pointed at another one:
  `make XFLAGS="-isysroot <an older SDK>"`.
