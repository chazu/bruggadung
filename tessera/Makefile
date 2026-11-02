CC      ?= cc
CFLAGS  ?= -std=c11 -O2 -g -Wall -Wextra -Wshadow -Wno-unused-parameter
CPPFLAGS = -Iinclude
SRC      = $(wildcard src/*.c)
OBJ      = $(SRC:src/%.c=build/%.o)

all: build/libtessera.a build/test

build:
	mkdir -p build

build/%.o: src/%.c src/internal.h include/tessera.h | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

build/libtessera.a: $(OBJ)
	ar rcs $@ $^

build/test: tests/test.c build/libtessera.a
	$(CC) $(CPPFLAGS) $(CFLAGS) $< build/libtessera.a -o $@

test: build/test
	./build/test

# UBSan (AddressSanitizer can't start with this machine's clang; leaks covers memory)
ubsan:
	$(MAKE) clean
	$(MAKE) CFLAGS="-std=c11 -O1 -g -Wall -Wextra -Wshadow -Wno-unused-parameter -fsanitize=undefined -fno-sanitize-recover=undefined" test
	$(MAKE) clean

leaks: build/test
	leaks --atExit -- ./build/test

clean:
	rm -rf build

.PHONY: all test ubsan leaks clean
