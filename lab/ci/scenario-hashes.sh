#!/bin/sh
# Each scenario, a line: the hash of what `lab run` prints, of what `lab save`
# prints, and the state hash it ends in. The simulation is deterministic on
# every platform, so these are the same everywhere; ci/scenario-hashes.txt
# holds them, and `make check` compares. A change that means to change a
# scenario regenerates the file: make scenarios > ci/scenario-hashes.txt
#
#   sh ci/scenario-hashes.sh ./build/<platform>/lab
LAB=${1:-./build/lab}

if command -v sha256sum >/dev/null 2>&1; then
    SHA="sha256sum"
else
    SHA="shasum -a 256"
fi

# A save's `content` line names the content it was made with, which any
# change to the content changes; loading skips it, and so does the hash.
# Everything else is by name, so content that only adds types leaves the
# hashes as they were.
#
# Windows prints \r\n: the hashes are of the text, not its line endings
hash() {
    tr -d '\r' | $SHA | cut -c1-16
}

for s in marked-nail marked-nail-a marked-nail-b cistern cistern-b cistern-d cistern-e village; do
    run=$("$LAB" run "$s" 2>&1 | tr -d '\r')
    printf '%-14s run %s save %s %s\n' "$s" \
        "$(printf '%s\n' "$run" | hash)" \
        "$("$LAB" save "$s" 2>&1 | grep -v '^content ' | hash)" \
        "$(printf '%s\n' "$run" | grep -o 'state hash [0-9a-f]*' | tail -1)"
done
