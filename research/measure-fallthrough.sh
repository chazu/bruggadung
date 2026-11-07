#!/bin/sh
# The measurements in METHODS.md, from a village run logging every agent:
#   lab run village --days 21 $(for i in $(seq 1 600); do printf ' --log %s' $i; done) 2> trace
#   sh research/measure-fallthrough.sh trace
# Until METHODS.md decision 6 counts fall-through in the engine.
trace=${1:?usage: measure-fallthrough.sh trace}

echo "== after a failed buy, the buyer's next way"
awk '
{ a=$1; line=$0; sub(/^[0-9]+ d[0-9]+ t=[0-9]+ms /,"",line) }
line ~ /^\[buy [a-z]+\] buy [a-z]+: (it knows no stall|nobody minds|.*dearer|it hasn.t the coins|it has no hand)/ {
  r=line; sub(/^\[[^]]*\] buy [a-z]+: /,"",r); gsub(/venison|grain|firewood|[0-9]+/,"X",r); pend[a]=r; next }
pend[a]!="" && line ~ /^\[buy [a-z]+\] / && line !~ /scoring|no longer holds|weighing/ {
  n=line; sub(/^\[[^]]*\] /,"",n); sub(/:.*/,"",n); t[pend[a] " => " n]++; pend[a]="" }
END { for (k in t) print t[k], k }' "$trace" | sort -rn

echo "== coin fetches, and second fetches in one buying"
awk '{ a=$1
  if ($0 ~ /\[buy [a-z]+\] fetch the coins: take/) { tot++; if (++n[a]==2) dbl++ }
  if ($0 ~ /\] done$/ || $0 ~ /impossible for now/) n[a]=0 }
END { print tot+0, "fetches,", dbl+0, "a second" }' "$trace"

echo "== after an act that could not be done, the next way of the same goal"
awk '
{ a=$1; line=$0; sub(/^[0-9]+ d[0-9]+ t=[0-9]+ms /,"",line) }
line ~ /^\[[^]]*\] [^:]+: could not [a-z_]+: / {
  g=line; sub(/\] .*/,"",g); w=line; sub(/^\[[^]]*\] /,"",w); sub(/: could not.*/,"",w)
  r=line; sub(/.*could not /,"",r); sub(/ in reach.*/,"",r); pend[a]=g "] " w " (" r ")"; pg[a]=g; next }
pend[a]!="" && index(line, pg[a] "]")==1 && line !~ /scoring|no longer holds|weighing|first$|back to it/ {
  n=line; sub(/^\[[^]]*\] /,"",n); sub(/:.*/,"",n); t[pend[a] " => " n]++; pend[a]="" }
END { for (k in t) print t[k], k }' "$trace" | sort -rn | head -20
