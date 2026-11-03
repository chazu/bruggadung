# The lab's build: clang, with Apple's Foundation on the Mac, and GNUstep's
# (libobjc2, gnustep-base) on Linux and on Windows under MSYS2's clang64.
# What each platform needs installed is in ci/README.md.
#
#   make              build/<platform>/lab: darwin, linux or windows (lab.exe)
#   make test         the tests; TEST=name runs those whose names contain it
#   make check        warnings as errors, the tests, and every scenario's
#                     hashes against ci/scenario-hashes.txt
#   make asan         the tests under AddressSanitizer and UBSan (.../asan)
#   make scenarios    each scenario's hashes, for ci/scenario-hashes.txt
#   make gen          src/generated/BGComponents.h, from content/
#   make clean
#
# XFLAGS adds flags to every compile and link (an -isysroot, say).

TRIANGLE ?= ../triangle
XFLAGS   ?=
SANITIZE ?=
TEST     ?=

ifeq ($(origin CC),default)
CC = clang
endif

ifeq ($(OS),Windows_NT)
PLATFORM = windows
EXE      = .exe
else
PLATFORM = $(shell uname -s | tr A-Z a-z)
EXE      =
endif

ifeq ($(PLATFORM),darwin)
OBJC_FLAGS =
OBJC_LIBS  = -framework Foundation
ASAN       = -fsanitize=address,undefined
else
# GNUstep's flags, then blocks off: the lab uses none, and with them on,
# clang 20 and later reject a block-scoped ivar in gnustep-base's headers.
# --base-libs turns them on again, so -fno-blocks comes last there too.
OBJC_FLAGS = $(shell gnustep-config --objc-flags) -fno-blocks
OBJC_LIBS  = $(shell gnustep-config --base-libs) -fno-blocks
ASAN       = -fsanitize=address,undefined --rtlib=compiler-rt -unwindlib=libgcc -Wno-unused-command-line-argument
endif
ifeq ($(PLATFORM),windows)
# clock_gettime is winpthreads'
OBJC_LIBS += -lpthread
endif

# one build directory per platform, so a tree shared with a container or
# another machine never links another platform's objects
BUILD    ?= build/$(PLATFORM)

WARN     = -Wall -Wextra -Wno-unused-parameter
FLAGS    = -std=gnu11 -g -O1 $(WARN) -DTRI_NO_TDL $(SANITIZE) $(XFLAGS)
INCLUDES = $(addprefix -I,$(shell find src -type d)) -I$(TRIANGLE)/include -I$(TRIANGLE)/objc

LAB_SRC  = $(shell find src -name '*.m')
TRI_SRC  = $(wildcard $(TRIANGLE)/src/*.c)
OBJ      = $(LAB_SRC:%.m=$(BUILD)/obj/%.o) $(BUILD)/obj/triangle/BGContent.o \
           $(TRI_SRC:$(TRIANGLE)/src/%.c=$(BUILD)/obj/triangle/%.o)
LAB      = $(BUILD)/lab$(EXE)

.PHONY: all test check asan scenarios gen clean

all: $(LAB)

$(LAB): $(OBJ)
	$(CC) $(FLAGS) $(OBJ) $(OBJC_LIBS) -o $@

$(BUILD)/obj/%.o: %.m
	@mkdir -p $(dir $@)
	$(CC) $(OBJC_FLAGS) $(FLAGS) -fno-objc-arc $(INCLUDES) -MMD -MP -c $< -o $@

$(BUILD)/obj/triangle/BGContent.o: $(TRIANGLE)/objc/BGContent.m
	@mkdir -p $(dir $@)
	$(CC) $(OBJC_FLAGS) $(FLAGS) -fno-objc-arc $(INCLUDES) -MMD -MP -c $< -o $@

$(BUILD)/obj/triangle/%.o: $(TRIANGLE)/src/%.c
	@mkdir -p $(dir $@)
	$(CC) $(FLAGS) -I$(TRIANGLE)/include -MMD -MP -c $< -o $@

-include $(OBJ:.o=.d)

test: $(LAB)
	./$(LAB) test $(TEST)

scenarios: $(LAB)
	@sh ci/scenario-hashes.sh ./$(LAB)

check:
	$(MAKE) BUILD=$(BUILD)/check XFLAGS="$(XFLAGS) -Werror" test
	sh ci/scenario-hashes.sh ./$(BUILD)/check/lab$(EXE) | diff ci/scenario-hashes.txt - && echo "scenarios: as expected"

asan:
	$(MAKE) BUILD=$(BUILD)/asan SANITIZE="$(ASAN)" test

gen:
	$(MAKE) -C $(TRIANGLE) build/tri-components
	$(TRIANGLE)/build/tri-components BG $$(find content -name '*.tri' -not -path '*/.*' | sort) > src/generated/BGComponents.h

clean:
	rm -rf $(BUILD)
