CC      ?= cc
CFLAGS  ?= -std=c11 -O2 -g -Wall -Wextra -Wno-unused-parameter
CPPFLAGS = -Iinclude -Ibuild -D_DEFAULT_SOURCE
SRC      = $(wildcard src/*.c)
OBJ      = $(SRC:src/%.c=build/%.o)
TESTS    = $(wildcard tests/*.c)
LDLIBS   =
ifeq ($(OS),Windows_NT)
# MinGW: clock_gettime is winpthreads'
LDLIBS  += -lpthread
endif

all: build/libtriangle.a build/test build/tri-components build/triangle

build/%.o: src/%.c src/internal.h include/triangle.h | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

build/libtriangle.a: $(OBJ)
	ar rcs $@ $^

build/test: $(TESTS) build/libtriangle.a tests/test.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(TESTS) build/libtriangle.a $(LDLIBS) -o $@

build/tri-components: tools/tri-components.c build/libtriangle.a
	$(CC) $(CPPFLAGS) $(CFLAGS) $< build/libtriangle.a $(LDLIBS) -o $@

# The command-line tool, with the language server.
TOOLSRC = tools/triangle.c tools/lsp.c tools/json.c tools/export.c tools/fmt.c tools/paths.c

build/triangle: $(TOOLSRC) tools/json.h tools/export.h tools/fmt.h tools/paths.h build/libtriangle.a
	$(CC) $(CPPFLAGS) $(CFLAGS) $(TOOLSRC) build/libtriangle.a $(LDLIBS) -o $@

# The language server driven over stdio, the command line, and the Emacs mode's tests.
lsp-test: build/triangle
	python3 tests/lsp_test.py build/triangle

cli-test: build/triangle
	python3 tests/cli_test.py build/triangle

emacs-test:
	emacs -Q --batch -L emacs -l emacs/triangle-mode-test.el -f ert-run-tests-batch-and-exit

# The guide's content as files, by topic: examples/workshop.
examples:
	python3 tools/guide-examples.py

PREFIX ?= $(HOME)/.local

install: build/triangle
	install -d $(PREFIX)/bin
	install build/triangle $(PREFIX)/bin/triangle

# What `make install` installs, tested: it installs into build/prefix, and
# the command-line tests run on that tool. They include that its `triangle
# version` names this tree's revision.
installed-test:
	$(MAKE) --no-print-directory install PREFIX=$(CURDIR)/build/prefix
	python3 tests/cli_test.py build/prefix/bin/triangle

# The triangle on PATH, which the Emacs mode runs, against this tree. It
# only warns: what a developer has installed is theirs.
installed-check:
	@t=$$(command -v triangle) || { echo "triangle: none on PATH"; exit 0; }; \
	v=$$("$$t" version 2>/dev/null); \
	case "$$v" in \
	*" $(REVISION)") echo "$$t: $$v, as this tree" ;; \
	*) echo "warning: $$t is \"$$v\", but this tree's revision is $(REVISION):" \
	        "make -C triangle install" ;; \
	esac

# The sources' revision (tools/revision.sh), for tri_revision and `triangle
# version`. The file is written only when the revision changes, so that only
# then does the library rebuild.
REVISION := $(shell sh tools/revision.sh)

build/revision.h: FORCE | build
	@echo '#define TRI_REVISION "$(REVISION)"' > $@.new
	@if cmp -s $@.new $@; then rm -f $@.new; else mv $@.new $@; fi

FORCE:

# The library for the game: without the TDL front end, which stays a test oracle.
GAMEOBJ = $(filter-out build/game/tdl.o,$(SRC:src/%.c=build/game/%.o))

build/game/%.o: src/%.c src/internal.h include/triangle.h
	@mkdir -p build/game
	$(CC) $(CPPFLAGS) $(CFLAGS) -DTRI_NO_TDL -c $< -o $@

build/libtriangle-game.a: $(GAMEOBJ)
	ar rcs $@ $^

game: build/libtriangle-game.a

build:
	mkdir -p build

# (all, so that build/triangle is never older than the library it links)
test: all leakcheck
	./build/test

# The library built against a counting allocator: everything must be freed.
LEAKOBJ = $(SRC:src/%.c=build/leak/%.o)

build/leak/%.o: src/%.c src/internal.h include/triangle.h tests/leakcheck/counting.h
	@mkdir -p build/leak
	$(CC) $(CPPFLAGS) $(CFLAGS) -include tests/leakcheck/counting.h -c $< -o $@

build/leakcheck: $(LEAKOBJ) tests/leakcheck/main.c tests/leakcheck/counting.c
	$(CC) $(CPPFLAGS) $(CFLAGS) tests/leakcheck/main.c tests/leakcheck/counting.c $(LEAKOBJ) $(LDLIBS) -o $@

leakcheck: build/leakcheck
	./build/leakcheck

asan:
	$(MAKE) clean
	$(MAKE) CFLAGS="-std=c11 -O1 -g -Wall -Wextra -Wno-unused-parameter -fsanitize=address,undefined" test

# The game's library for Odin (odin/triangle), in a directory per platform:
# an ar archive on the Mac and Linux; on Windows, a COFF library for the MSVC
# ABI, the only one Odin links with there, compiled by clang for that target
# against the Visual Studio and Windows SDK it finds (not yet tried).
ifeq ($(OS),Windows_NT)
ODIN_PLATFORM = windows
ODIN_LIB      = build/windows/triangle.lib
# (the CRT hides POSIX names such as strdup from strict C unless asked)
ODIN_CC       = clang --target=x86_64-pc-windows-msvc -D_CRT_SECURE_NO_WARNINGS \
                -D_CRT_DECLARE_NONSTDC_NAMES=1 -D_CRT_NONSTDC_NO_WARNINGS
else
ODIN_PLATFORM = $(shell uname -s | tr A-Z a-z)
ODIN_LIB      = build/$(ODIN_PLATFORM)/libtriangle.a
ODIN_CC       = $(CC)
endif
ODINOBJ = $(filter-out build/$(ODIN_PLATFORM)/obj/tdl.o,$(SRC:src/%.c=build/$(ODIN_PLATFORM)/obj/%.o))

build/$(ODIN_PLATFORM)/obj/%.o: src/%.c src/internal.h include/triangle.h
	@mkdir -p $(dir $@)
	$(ODIN_CC) $(CPPFLAGS) $(CFLAGS) -DTRI_NO_TDL -c $< -o $@

$(ODIN_LIB): $(ODINOBJ)
ifeq ($(OS),Windows_NT)
	llvm-lib /out:$@ $^
else
	ar rcs $@ $^
endif

odin-lib: $(ODIN_LIB)

# The Odin wrapper's tests.
odin: $(ODIN_LIB)
	odin test odin/test -vet -strict-style

clean:
	rm -rf build

# Each build of revision.c, in every variant of the library, reads the stamp.
$(filter %/revision.o,$(OBJ) $(GAMEOBJ) $(LEAKOBJ) $(ODINOBJ)): build/revision.h

.PHONY: cli-test all test asan odin odin-lib leakcheck game clean lsp-test emacs-test install \
        installed-test installed-check examples FORCE
