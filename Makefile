# The whole project from its root: each part has its own Makefile
# (triangle/, tessera/, lab/), and this one only sends targets to them.
#
#   make              the lab (and Triangle's library, which it links)
#   make watcher      the watcher: a lab world in a window
#   make watch        builds the watcher and runs it: WHAT=village by
#                     default; ARGS adds its flags (ARGS="--from 7 --pane log")
#   make test         every part's tests; TEST=name narrows the lab's
#   make check        what CI runs, a part at a time
#   make gen          lab/src/components.odin, from the content
#   make scenarios    each scenario's hashes, for lab/ci/scenario-hashes.txt
#   make clean

PLATFORM = $(shell uname -s | tr A-Z a-z)
WHAT    ?= village
ARGS    ?=

.PHONY: all watcher watch test check gen scenarios clean

all:
	@$(MAKE) --no-print-directory -C lab

watcher gen scenarios:
	@$(MAKE) --no-print-directory -C lab $@

watch: watcher
	cd lab && ./build/$(PLATFORM)/watcher $(WHAT) $(ARGS)

test:
	@$(MAKE) --no-print-directory -C triangle test
	@$(MAKE) --no-print-directory -C tessera test
	@$(MAKE) --no-print-directory -C lab test

check:
	@$(MAKE) --no-print-directory -C triangle test cli-test lsp-test odin
	@$(MAKE) --no-print-directory -C tessera test check
	@$(MAKE) --no-print-directory -C lab check

clean:
	@$(MAKE) --no-print-directory -C triangle clean
	@$(MAKE) --no-print-directory -C lab clean
