# Tessera, an Odin package (this directory). The Odin release is pinned in
# ../lab/ci/odin.
#
#   make test     the tests (tests/), with Odin's leak tracking
#   make check    the package checked, as the tests build it

ODIN  ?= odin
FLAGS  = -vet -strict-style

test:
	$(ODIN) test tests $(FLAGS)

check:
	$(ODIN) check . $(FLAGS) -no-entry-point

.PHONY: test check
