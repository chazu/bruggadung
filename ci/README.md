# Building on each platform

Triangle is C11. Tessera, Orogen and the lab are Odin, the release pinned here
(`install-odin.sh` and `Dockerfile`: change both together). The lab links
Triangle's C library, which `make -C triangle odin-lib` builds for the
platform. Every scenario ends in the same state on each platform: `make -C
lab check` compares them against `lab/ci/scenario-hashes.txt`.

| Platform | What to install | Then |
| --- | --- | --- |
| macOS | Xcode's command line tools, and Odin: `sh ci/install-odin.sh` (prints where; put it on PATH) | `make -C triangle test cli-test lsp-test odin`, `make -C tessera test check`, `make -C orogen test check`, `make -C lab check` |
| Linux | clang, make, Python 3 and Odin: `Dockerfile` does it, or is the image to build in | `docker build -t bruggadung ci`, then `docker run --rm -v "$PWD":/repo -w /repo bruggadung make -C lab check` (and the same for Triangle with `CC=clang`, Tessera and Orogen) |
| Windows | MSYS2, then `sh ci/windows/setup-msys2.sh` in an MSYS2 shell | Triangle only, in a CLANG64 shell: `make -C triangle CC=clang test cli-test lsp-test` |

`.github/workflows/build.yml` runs all of this on each push.

Notes:
- The watcher (`make -C lab watcher`) links raylib, which comes with Odin.
  On Linux it needs X11 and OpenGL's development libraries (`libx11-dev`,
  `libgl-dev`) too; the image and CI only type-check it (`make -C lab
  check` does).
- Odin links for the MSVC ABI on Windows, so the lab and Tessera need
  Visual Studio's C runtime and the Windows SDK there, and Triangle's
  library built by clang for that target (`make -C triangle odin-lib`
  has the rules, not yet tried). MSYS2's MinGW libraries won't link.
- A toolchain whose linker can't read the SDK it finds (as when the command
  line tools are older than the SDK) can be pointed at another one for
  Triangle's C: `make -C triangle CFLAGS="... -isysroot <an older SDK>"`.
- The lab was Objective-C until 2026-11, built against GNUstep from source
  on Linux and MSYS2's GNUstep on Windows; the history of this file has how.
