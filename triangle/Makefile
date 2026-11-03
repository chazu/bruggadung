CC      ?= cc
CFLAGS  ?= -std=c11 -O2 -g -Wall -Wextra -Wno-unused-parameter
CPPFLAGS = -Iinclude -D_DEFAULT_SOURCE
SRC      = $(wildcard src/*.c)
OBJ      = $(SRC:src/%.c=build/%.o)
TESTS    = $(wildcard tests/*.c)
LDLIBS   =
ifeq ($(OS),Windows_NT)
# MinGW: clock_gettime is winpthreads'
LDLIBS  += -lpthread
endif

# Foundation for the Objective-C wrapper: Apple's on the Mac, GNUstep's
# elsewhere (blocks off: see lab/Makefile)
ifeq ($(shell uname -s),Darwin)
OBJC_FLAGS =
OBJC_LIBS  = -framework Foundation
else
OBJC_FLAGS = $(shell gnustep-config --objc-flags) -fno-blocks
OBJC_LIBS  = $(shell gnustep-config --base-libs) -fno-blocks $(LDLIBS)
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

test: build/test leakcheck
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

# The Objective-C wrapper, built with the platform's compiler and Foundation
# (manual retain/release).
objc: build/libtriangle.a
	$(CC) $(CPPFLAGS) $(OBJC_FLAGS) -Iobjc -fno-objc-arc -Wall objc/BGContent.m objc/test_objc.m build/libtriangle.a \
	    $(OBJC_LIBS) -o build/test_objc
	./build/test_objc

clean:
	rm -rf build

.PHONY: cli-test all test asan objc leakcheck game clean lsp-test emacs-test install examples
