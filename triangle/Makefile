CC      ?= cc
CFLAGS  ?= -std=c11 -O2 -g -Wall -Wextra -Wno-unused-parameter
CPPFLAGS = -Iinclude
SRC      = $(wildcard src/*.c)
OBJ      = $(SRC:src/%.c=build/%.o)
TESTS    = $(wildcard tests/*.c)

all: build/libtriangle.a build/test build/tri-components

build/%.o: src/%.c src/internal.h include/triangle.h | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

build/libtriangle.a: $(OBJ)
	ar rcs $@ $^

build/test: $(TESTS) build/libtriangle.a tests/test.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(TESTS) build/libtriangle.a -o $@

build/tri-components: tools/tri-components.c build/libtriangle.a
	$(CC) $(CPPFLAGS) $(CFLAGS) $< build/libtriangle.a -o $@

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
	$(CC) $(CPPFLAGS) $(CFLAGS) tests/leakcheck/main.c tests/leakcheck/counting.c $(LEAKOBJ) -o $@

leakcheck: build/leakcheck
	./build/leakcheck

asan:
	$(MAKE) clean
	$(MAKE) CFLAGS="-std=c11 -O1 -g -Wall -Wextra -Wno-unused-parameter -fsanitize=address,undefined" test

# The Objective-C wrapper, built with the platform's compiler and Foundation
# (manual retain/release, so it also suits mulle-objc).
objc: build/libtriangle.a
	$(CC) $(CPPFLAGS) -Iobjc -fno-objc-arc -Wall objc/BGContent.m objc/test_objc.m build/libtriangle.a \
	    -framework Foundation -o build/test_objc
	./build/test_objc

clean:
	rm -rf build

.PHONY: all test asan objc leakcheck game clean
