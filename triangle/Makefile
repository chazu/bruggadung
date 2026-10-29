CC      ?= cc
CFLAGS  ?= -std=c11 -O2 -g -Wall -Wextra -Wno-unused-parameter
CPPFLAGS = -Iinclude
SRC      = $(wildcard src/*.c)
OBJ      = $(SRC:src/%.c=build/%.o)
TESTS    = $(wildcard tests/*.c)

all: build/libtriangle.a build/test

build/%.o: src/%.c src/internal.h include/triangle.h | build
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

build/libtriangle.a: $(OBJ)
	ar rcs $@ $^

build/test: $(TESTS) build/libtriangle.a tests/test.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(TESTS) build/libtriangle.a -o $@

build:
	mkdir -p build

test: build/test
	./build/test

asan:
	$(MAKE) clean
	$(MAKE) CFLAGS="-std=c11 -O1 -g -Wall -Wextra -Wno-unused-parameter -fsanitize=address,undefined" test

clean:
	rm -rf build

.PHONY: all test asan clean
