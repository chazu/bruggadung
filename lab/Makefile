# The lab's build: Odin (src/, one package), with Triangle's C library linked
# in, built by ../triangle's Makefile (odin-lib). The Odin release is pinned
# in ../ci (install-odin.sh, Dockerfile); ../ci/README.md says what each
# platform needs.
#
#   make              build/<platform>/lab: darwin or linux
#   make watcher      build/<platform>/watcher: a world in a window
#                     (watcher/, with raylib; the lab never links it)
#   make test         the tests; TEST=name runs those whose names contain it
#   make check        the tests, every scenario's hashes against
#                     ci/scenario-hashes.txt, and the watcher type-checked;
#                     on a lab built -o:speed (.../speed), which ends in the
#                     same hashes in half the time (PERFORMANCE.md decision 5)
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
CHECKED   = $(BUILD)/speed/lab
WATCHER   = $(BUILD)/watcher

# Odin's vet and strict style, on every build: what `make check` asks of a
# change is that it builds this way.
FLAGS     = -vet -strict-style $(ODINFLAGS)

.PHONY: all watcher test check asan scenarios gen triangle clean

all: $(LAB)

triangle:
	@$(MAKE) -s --no-print-directory -C $(TRIANGLE) odin-lib

$(LAB): $(wildcard src/*.odin) $(wildcard ../tessera/*.odin) | triangle
	@mkdir -p $(BUILD)
	$(ODIN) build src $(FLAGS) -out:$@

$(CHECKED): $(wildcard src/*.odin) $(wildcard ../tessera/*.odin) | triangle
	@mkdir -p $(BUILD)/speed
	$(ODIN) build src $(FLAGS) -o:speed -out:$@

watcher: $(WATCHER)

$(WATCHER): $(wildcard watcher/*.odin src/*.odin ../tessera/*.odin ../tessera/raylib/*.odin) | triangle
	@mkdir -p $(BUILD)
	$(ODIN) build watcher $(FLAGS) -out:$@

test: $(LAB)
	./$(LAB) test $(TEST)

scenarios: $(LAB)
	@sh ci/scenario-hashes.sh ./$(LAB)

check: $(CHECKED)
	$(MAKE) -s --no-print-directory -C $(TRIANGLE) build/triangle
	$(TRIANGLE)/build/triangle fmt --check content && echo "content: as fmt writes it"
	./$(CHECKED) test
	sh ci/scenario-hashes.sh ./$(CHECKED) | diff ci/scenario-hashes.txt - && echo "scenarios: as expected"
	$(ODIN) check watcher $(FLAGS) && echo "watcher: checked"

asan: triangle
	@mkdir -p $(BUILD)/asan
	$(ODIN) build src $(FLAGS) -debug -sanitize:address -out:$(BUILD)/asan/lab
	./$(BUILD)/asan/lab test $(TEST)

gen:
	$(MAKE) -C $(TRIANGLE) build/tri-components
	$(TRIANGLE)/build/tri-components -odin lab ../../triangle/odin/triangle \
	    $$(find content -name '*.tri' -not -path '*/.*' | sort) > src/components.odin.new
	mv src/components.odin.new src/components.odin

clean:
	rm -rf $(BUILD)
