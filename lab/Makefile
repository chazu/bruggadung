# The lab's build: Odin (src/, one package), with Triangle's C library linked
# in, built by ../triangle's Makefile (odin-lib). The Odin release is pinned
# in ../ci (install-odin.sh, Dockerfile); ../ci/README.md says what each
# platform needs.
#
#   make              build/<platform>/lab: darwin or linux
#   make test         the tests; TEST=name runs those whose names contain it
#   make check        the tests, and every scenario's hashes against
#                     ci/scenario-hashes.txt
#   make asan         the tests under AddressSanitizer (.../asan; Linux)
#   make scenarios    each scenario's hashes, for ci/scenario-hashes.txt
#   make gen          src/components.odin, from content/
#   make clean
#
# ODINFLAGS adds flags to `odin build` (-o:speed, say).

TRIANGLE  ?= ../triangle
ODIN      ?= odin
ODINFLAGS ?=
TEST      ?=

PLATFORM  = $(shell uname -s | tr A-Z a-z)
BUILD    ?= build/$(PLATFORM)
LAB       = $(BUILD)/lab

# Odin's vet and strict style, on every build: what `make check` asks of a
# change is that it builds this way.
FLAGS     = -vet -strict-style $(ODINFLAGS)

.PHONY: all test check asan scenarios gen triangle clean

all: $(LAB)

triangle:
	$(MAKE) -C $(TRIANGLE) odin-lib

$(LAB): $(wildcard src/*.odin) | triangle
	@mkdir -p $(BUILD)
	$(ODIN) build src $(FLAGS) -out:$@

test: $(LAB)
	./$(LAB) test $(TEST)

scenarios: $(LAB)
	@sh ci/scenario-hashes.sh ./$(LAB)

check: $(LAB)
	./$(LAB) test
	sh ci/scenario-hashes.sh ./$(LAB) | diff ci/scenario-hashes.txt - && echo "scenarios: as expected"

asan: triangle
	@mkdir -p $(BUILD)/asan
	$(ODIN) build src $(FLAGS) -debug -sanitize:address -out:$(BUILD)/asan/lab
	./$(BUILD)/asan/lab test $(TEST)

gen:
	$(MAKE) -C $(TRIANGLE) build/tri-components
	$(TRIANGLE)/build/tri-components -odin lab ../../triangle/odin/triangle \
	    $$(find content -name '*.tri' -not -path '*/.*' | sort) > src/components.odin

clean:
	rm -rf $(BUILD)
