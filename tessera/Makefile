# Tessera, an Odin package (this directory). The Odin release is pinned in
# ../ci (install-odin.sh, Dockerfile).
#
#   make test     the tests (tests/), with Odin's leak tracking
#   make check    the Odin package checked, as the tests build it

ODIN  ?= odin
FLAGS  = -vet -strict-style

test:
	$(ODIN) test tests $(FLAGS)

check:
	$(ODIN) check . $(FLAGS) -no-entry-point

.PHONY: test check
