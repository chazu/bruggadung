# Orogen, an Odin package (this directory). The Odin release is pinned in
# ../ci (install-odin.sh, Dockerfile).
#
#   make          build/orogen, the tool: a map printed as text
#   make test     the tests (tests/), with Odin's leak tracking
#   make check    the package and the tool checked, as the tests build them
#   make golden   tests/golden/, written again from the tool: after a
#                 change that moves a map (and so changes VERSION)

ODIN  ?= odin
FLAGS  = -vet -strict-style

build/orogen: *.odin cmd/*.odin
	@mkdir -p build
	$(ODIN) build cmd $(FLAGS) -out:$@

test:
	$(ODIN) test tests $(FLAGS)

check:
	$(ODIN) check . $(FLAGS) -no-entry-point
	$(ODIN) check cmd $(FLAGS)

golden: build/orogen
	build/orogen --seed 7 --wide 64 --high 24 > tests/golden/small.txt
	build/orogen --seed 7 --wide 64 --high 24 --elevations > tests/golden/small-elevations.txt

clean:
	rm -rf build

.PHONY: test check golden clean
