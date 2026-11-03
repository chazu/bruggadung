# The mulle-sde build is the real one: mulle-sde craft, then mulle-sde run.
# This Makefile regenerates the component header from content, and builds the
# same sources with Apple clang and Foundation as a quick second check.

TRIANGLE = ../triangle
SOURCES  = $(shell find src -name '*.m' -not -path 'src/triangle/*' -not -path 'src/reflect/*') src/triangle/BGContent.m
CSOURCES = $(wildcard $(TRIANGLE)/src/*.c)
INCLUDES = $(addprefix -I,$(shell find src -type d -not -path 'src/triangle*' -not -path 'src/reflect*' -not -path 'src/generic*')) \
           -I$(TRIANGLE)/include -I$(TRIANGLE)/objc

.PHONY: gen apple test-apple asan leaks check

SANITIZE ?=

gen:
	$(MAKE) -C $(TRIANGLE) build/tri-components
	$(TRIANGLE)/build/tri-components BG $$(find content -name '*.tri' -not -path '*/.*' | sort) > src/generated/BGComponents.h

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

# Leaks of objects, through mulle-testallocator, on the mulle build (mulle-sde craft first).
# It tracks mulle-allocated memory: objects, not the C malloc inside them.
leaks:
	MULLE_OBJC_PEDANTIC_EXIT=YES MULLE_TESTALLOCATOR=YES ./kitchen/Debug/lab test 2>&1 | \
	    grep -E '### leak|tests,' ; ! MULLE_OBJC_PEDANTIC_EXIT=YES MULLE_TESTALLOCATOR=YES ./kitchen/Debug/lab test 2>&1 | grep -q '### leak'

# The mulle build's tests, failing on any runtime warning (in mulle-objc a
# selector must have one signature in every class) and on object leaks.
check:
	mulle-sde craft
	mkdir -p build
	./kitchen/Debug/lab test > build/check.log 2>&1 ; status=$$? ; tail -1 build/check.log ; \
	    if grep -q 'varying signatures' build/check.log ; then grep -A1 'varying signatures' build/check.log ; exit 1 ; fi ; \
	    exit $$status
	$(MAKE) leaks
