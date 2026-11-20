# The whole project from its root: each part has its own Makefile
# (triangle/, tessera/, orogen/, lab/), and this one only sends targets to them.
#
#   make              the lab (and Triangle's library, which it links)
#   make watcher      the watcher: a lab world in a window
#   make watch        builds the watcher and runs it: WHAT=village by
#                     default; ARGS adds its flags (ARGS="--from 7 --pane log")
#   make test         every part's tests; TEST=name narrows the lab's
#   make check        what CI runs, a part at a time: check-triangle,
#                     check-tessera, check-orogen, check-lab, each a job
#                     of its own in CI (make -k check goes on past a
#                     failed part, as CI does)
#   make asan         Triangle's tests and the lab's under AddressSanitizer
#                     (the lab's on Linux only; CI runs it there)
#   make gen          lab/src/components.odin, from the content
#   make scenarios    each scenario's hashes, for lab/ci/scenario-hashes.txt
#   make clean

PLATFORM = $(shell uname -s | tr A-Z a-z)
WHAT    ?= village
ARGS    ?=

PARTS = triangle tessera orogen lab

.PHONY: all watcher watch test check $(PARTS:%=check-%) asan gen scenarios clean

all:
	@$(MAKE) --no-print-directory -C lab

watcher gen scenarios:
	@$(MAKE) --no-print-directory -C lab $@

watch: watcher
	cd lab && ./build/$(PLATFORM)/watcher $(WHAT) $(ARGS)

test:
	@$(MAKE) --no-print-directory -C triangle test
	@$(MAKE) --no-print-directory -C tessera test
	@$(MAKE) --no-print-directory -C orogen test
	@$(MAKE) --no-print-directory -C lab test

check: $(PARTS:%=check-%)

# Triangle's: its tests, the tool's, the server's, the Odin wrapper's, and
# what `make install` installs; then a word on the triangle on PATH.
check-triangle:
	@$(MAKE) --no-print-directory -C triangle test cli-test lsp-test odin installed-test
	@$(MAKE) --no-print-directory -C triangle installed-check

check-tessera:
	@$(MAKE) --no-print-directory -C tessera test check

check-orogen:
	@$(MAKE) --no-print-directory -C orogen test check

check-lab:
	@$(MAKE) --no-print-directory -C lab check

# The lab's first: Triangle's asan rebuilds triangle/build from clean.
asan:
ifeq ($(PLATFORM),linux)
	@$(MAKE) --no-print-directory -C lab asan
else
	@echo "lab: make asan is for Linux; Triangle's only, here"
endif
	@$(MAKE) --no-print-directory -C triangle asan

clean:
	@$(MAKE) --no-print-directory -C triangle clean
	@$(MAKE) --no-print-directory -C orogen clean
	@$(MAKE) --no-print-directory -C lab clean
