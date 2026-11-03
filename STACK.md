Language: Odin for the lab and Tessera, the release pinned in ci/
(install-odin.sh, Dockerfile); C11 for Triangle, which the lab links as a
library (triangle/odin/triangle). Built with make and clang, on macOS and
Linux; Triangle on Windows too (ci/README.md).

The lab was Objective-C until 2026-11: with mulle-objc and mulle-sde, then
with clang and Apple's or GNUstep's Foundation, to build on Linux and
Windows with standard tools. It moved to Odin for a smaller toolchain (one
compiler download, in place of GNUstep built from source), for allocators in
place of reference counts, and for Odin's vendor packages for Tessera's
windows. The port kept every test's checks and every scenario's hashes.
