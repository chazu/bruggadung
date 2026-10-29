# The mulle-sde build is the real one: mulle-sde craft, then mulle-sde run.
# This Makefile regenerates the component header from content, and builds the
# same sources with Apple clang and Foundation as a quick second check.

TRIANGLE = ../triangle
SOURCES  = $(shell find src -name '*.m' -not -path 'src/triangle/*' -not -path 'src/reflect/*') src/triangle/BGContent.m
CSOURCES = $(wildcard $(TRIANGLE)/src/*.c)
INCLUDES = $(addprefix -I,$(shell find src -type d -not -path 'src/triangle*' -not -path 'src/reflect*' -not -path 'src/generic*')) \
           -I$(TRIANGLE)/include -I$(TRIANGLE)/objc

.PHONY: gen apple test-apple asan

SANITIZE ?=

gen:
	$(MAKE) -C $(TRIANGLE) build/tri-components
	$(TRIANGLE)/build/tri-components BG content/*.tri > src/generated/BGComponents.h

build/apple/lab: $(SOURCES) $(CSOURCES) $(shell find src -name '*.h')
	mkdir -p build/apple
	clang -std=gnu11 -g -O1 -Wall -Wextra -Wno-unused-parameter -fno-objc-arc -DTRI_NO_TDL $(SANITIZE) $(INCLUDES) \
	    $(SOURCES) $(CSOURCES) -framework Foundation -o $@

apple: build/apple/lab

test-apple: build/apple/lab
	./build/apple/lab test

# AddressSanitizer and UBSan, on the Apple build
asan:
	rm -f build/apple/lab
	$(MAKE) SANITIZE="-fsanitize=address,undefined" test-apple
	rm -f build/apple/lab
