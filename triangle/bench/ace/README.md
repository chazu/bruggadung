# Checking Triangle against ACE

These files compare Triangle with ACE 0.9.34 on the English Resource Grammar.
The results are in the main README.

| File | Purpose |
| --- | --- |
| `ace-0.9.34-macos.patch` | Builds ACE natively on Apple silicon, and adds a glb dump |
| `glbdump.c` | Prints each Triangle glb as its sorted set of declared supertypes |
| `workload.c` | Times Triangle on the bench workload, without failure paths, and writes the names it used |
| `ace_workload.c` | Runs the same unifications in ACE, on its compiled image |

## Building ACE on Apple silicon

The prebuilt macOS binary is x86-64 ACE 0.9.31. Under Rosetta it loads the
grammar but cannot save the image. The image holds raw pointers, so it must
be mapped at a fixed address, and Rosetta ignores the address requested.

ACE uses GCC nested functions, so Apple clang can't build it. Use Homebrew
`gcc` and `boost`. The patch:

- sets the macOS build variables
- compiles as `gnu17` with `-fpermissive` and `-fcommon`, since the code
  predates GCC 14's stricter defaults
- declares four functions that ACE calls without a prototype, which would
  otherwise truncate their results to `int`
- ends the variadic `walk_dg` calls with `NULL` instead of `0`. Apple's arm64
  ABI puts each variadic argument in its own 8-byte stack slot, so an `int`
  `0` leaves the top half of the slot as garbage. The sentinel then never
  reads as NULL, and ACE crashed whenever address randomisation was on.
- maps the image at `0x200000000000`, because `0x6000000000` is in use on
  macOS
- adds `ACE_GLB_DUMP=file`, which writes each glb's declared supertypes

```sh
curl -O https://sweaglesw.org/linguistics/ace/download/ace-0.9.34.tar.gz
curl -O https://sweaglesw.org/linguistics/repp-0.2.2.tar.gz
tar xzf ace-0.9.34.tar.gz && tar xzf repp-0.2.2.tar.gz
(cd repp-0.2.2/librepp && for f in load_repp preprocessor unicode; do
   gcc-16 -O2 -c -I../include -I. -I/opt/homebrew/include $f.c; done &&
 ar rcs ../librepp.a load_repp.o preprocessor.o unicode.o)
cd ace-0.9.34 && patch -p1 < .../bench/ace/ace-0.9.34-macos.patch
make ace REPP_DIR=$PWD/../repp-0.2.2
```

## Meet types

ACE reads `mtr.tdl` as types before the grammar, so Triangle loads it too:

```sh
cd erg && ACE_GLB_DUMP=ace-glbs.txt ace -g ace/config.tdl -G erg.dat
printf ':begin :type.\n:include "mtr".\n:end :type.\n:include "english".\n' > with-mtr.tdl
cc -std=c11 -O2 -Iinclude bench/ace/glbdump.c build/libtriangle.a -o build/glbdump
build/glbdump erg/with-mtr.tdl > tri-glbs.txt
norm() { sed -E 's/(^| )\*top\*( |$)/\1/; s/  */ /g; s/^ //; s/ $//' "$1" | sort; }
cmp <(norm ace-glbs.txt) <(norm tri-glbs.txt)
```

## Unification

```sh
cc -std=c11 -O2 -Iinclude bench/ace/workload.c build/libtriangle.a -o build/workload
build/workload erg/english.tdl 1000 names.txt tri-pairs.txt
# in ace-0.9.34, with the CFLAGS from its Makefile:
gcc-16 $CFLAGS -c libace.c && gcc-16 $CFLAGS -I. .../ace_workload.c -o ace_workload \
  $OBJ libace.o timer.o post/post.o -lutil $REPP_DIR/librepp.a -lpthread -lm \
  /opt/homebrew/lib/libboost_regex.a -lc++ -ldl
./ace_workload erg.dat names.txt ace-pairs.txt
cmp tri-pairs.txt ace-pairs.txt
```
