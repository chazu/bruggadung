#!/bin/sh
# The revision of Triangle's sources: the last commit that changed what the
# library and the tool are built from (src, include, tools, Makefile), its
# first 12 hex digits, with "+" when those files have changes not committed.
# "unknown" when git can't say. The build stamps it into the library
# (tri_revision) and `triangle version`, and the Emacs mode compares the
# installed tool with it.
#
#   sh tools/revision.sh        (from any directory)
cd "$(dirname "$0")/.." || exit 1
paths="src include tools Makefile"
rev=$(git log -1 --format=%H -- $paths 2>/dev/null | cut -c1-12)
if [ -z "$rev" ]; then echo unknown; exit 0; fi
if [ -n "$(git status --porcelain -- $paths 2>/dev/null)" ]; then rev="$rev+"; fi
echo "$rev"
