# Agent and AI information

## TRANSGRESSIONS PUNISHABLE BY DEATH

DO NOT `git revert` AND DO NOT clobber files with git `checkout`  or run
any other destructive git command. You will be shot and another better AI
will take your place.

## Building

The lab is Objective-C with manual retain/release (`-fno-objc-arc`), built
with clang and this directory's `Makefile`: Apple's Foundation on the Mac,
GNUstep's (libobjc2, gnustep-base) on Linux and on Windows under MSYS2's
clang64. ci/README.md says what each platform needs installed.

```sh
make              # build/<platform>/lab
make test         # the tests (TEST=name for those whose names contain it)
make check        # warnings as errors, the tests, every scenario's hashes
make asan         # the tests under AddressSanitizer and UBSan
make gen          # src/generated/BGComponents.h, after a content change to components
```

Run `make check` before committing a change to code. It must pass on every
platform: write only what clang, Apple's Foundation and GNUstep's all
accept.

## Writing portable code

- Foundation only: no Apple-only frameworks or API. Check that what you use
  exists in GNUstep's gnustep-base.
- No blocks: they are off outside the Mac (`-fno-blocks`, see ci/README.md).
- Print `int64_t` and `uint64_t` with a cast to `long long` or `unsigned
  long long` for `%lld` and `%llu`: `int64_t` is `long` on Linux.
- Never pass a null pointer to `memcpy`, `memset`, `qsort` and friends, even
  with a count of 0: glibc declares them nonnull, and UBSan says so.
- A `qsort` comparator orders ties fully (by ID, say): C libraries order
  ties differently, and the simulation must come out the same everywhere.
- Windows headers define macros with plain names (`near`, `far`, `min`,
  `max`, `_daylight`, `interface`, ...). `BGTypes.h` undefines the ones
  that collide; don't name things after the rest.
- A selector has one signature in every class: keep it so, though only
  mulle's runtime used to insist.
- In tests, prefer `rangeOfString:` to `hasSuffix:` and the like on long
  strings, and test under both Foundations when in doubt.

## The simulation is deterministic, everywhere

Every scenario must end in the same state on every platform.
`ci/scenario-hashes.txt` holds each scenario's hashes and `make check`
compares. A change meant to change a scenario regenerates it (`make
scenarios > ci/scenario-hashes.txt`) and says so in the commit.

## Content

Triangle content is laid out by topic: see content/README.md, and
../CLAUDE.md for the terminology rule.
