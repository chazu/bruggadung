Language: Objective-C, with manual retain/release, built with clang: Apple's
Foundation on macOS, GNUstep's (the libobjc2 runtime, gnustep-base) on Linux
and on Windows (MSYS2's clang64). Triangle is C11. Tessera is Odin (the release
pinned in lab/ci/odin), and the lab is to follow it (see the Odin spike,
lab/odin).

The lab used mulle-objc and mulle-sde until 2026-11; it left for clang and
GNUstep to build on Linux and Windows with standard tools (lab/ci/README.md).
