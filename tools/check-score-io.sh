#!/usr/bin/env bash
# Exercises the score helpers as they are shipped in Panel.qml, against a
# throwaway HOME. Every case here is one a reviewer raised or one that would
# have caught a real regression; each is written so it FAILS if the guard it
# names is removed.
set -uo pipefail

cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ID="$(python3 tools/extract-helpers.py Panel.qml "$WORK/read.pl" "$WORK/write.pl")"
STATE=".local/state/omarchy/plugins/$ID"
READ="$(cat "$WORK/read.pl")"
WRITE="$(cat "$WORK/write.pl")"
fails=0

w() { HOME="$WORK/hb" /usr/bin/perl -e "$WRITE" -- "$1" >/dev/null 2>&1; }
r() { HOME="$WORK/hb" /usr/bin/perl -e "$READ" 2>/dev/null; }
fresh() { rm -rf "$WORK/hb" "$WORK/away"; mkdir -p "$WORK/hb"; }
ok() { printf '  ok    %s\n' "$1"; }
no() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
is() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (got '$2', want '$3')"; fi; }

echo "score I/O boundary — $ID"

/usr/bin/perl -c "$WORK/write.pl" >/dev/null 2>&1 && ok "write helper parses" || no "write helper parses"
/usr/bin/perl -c "$WORK/read.pl"  >/dev/null 2>&1 && ok "read helper parses"  || no "read helper parses"

fresh
w '{"best":7}'; is "round trip" "$(r)" '{"best":7}'
is "state dir is 0700" "$(stat -c %a "$WORK/hb/$STATE")" 700
is "score file is 0600" "$(stat -c %a "$WORK/hb/$STATE/scores.json")" 600

# The finding this walk exists for: a pathname stat() follows symlinks, so an
# ancestor pointing at another directory you own passes an owner/mode check and
# the write lands outside the state tree.
fresh; mkdir -p "$WORK/hb/.local/state/omarchy" "$WORK/away/plugins"; chmod 700 "$WORK/away/plugins"
ln -s "$WORK/away/plugins" "$WORK/hb/.local/state/omarchy/plugins"
w '{"best":1}'
[ -e "$WORK/away/plugins/$ID/scores.json" ] && no "symlinked ancestor is refused" || ok "symlinked ancestor is refused"

fresh; mkdir -p "$WORK/hb/.local/state/omarchy/plugins" "$WORK/away/t"; chmod 700 "$WORK/away/t"
ln -s "$WORK/away/t" "$WORK/hb/.local/state/omarchy/plugins/$ID"
w '{"best":1}'
[ -e "$WORK/away/t/scores.json" ] && no "symlinked state dir is refused" || ok "symlinked state dir is refused"

fresh; mkdir -p "$WORK/hb/$STATE"; echo private > "$WORK/hb/victim"
ln -s "$WORK/hb/victim" "$WORK/hb/$STATE/scores.json"
is "symlinked score file is not read" "$(r)" ""

fresh; mkdir -p "$WORK/hb/.local/state/omarchy/plugins"; chmod 777 "$WORK/hb/.local/state/omarchy"
w '{"best":1}'
[ -e "$WORK/hb/$STATE/scores.json" ] && no "world-writable ancestor is refused" || ok "world-writable ancestor is refused"

# Capped before the walk, so an oversized payload creates nothing at all.
fresh
w "$(head -c 5000 /dev/zero | tr '\0' a)"
[ -e "$WORK/hb/.local" ] && no "oversize payload creates nothing" || ok "oversize payload creates nothing"

fresh
r >/dev/null
[ -e "$WORK/hb/.local" ] && no "reader creates nothing" || ok "reader creates nothing"

# perl consumes the -- itself, so a payload opening with a dash is data.
fresh
w '-e print "pwned"'; is "dash-leading payload is data" "$(r)" '-e print "pwned"'

fresh
w '{"best":1}'; w '{"best":2}'
is "replace is atomic" "$(r)" '{"best":2}'
is "no temp files left behind" "$(ls -a "$WORK/hb/$STATE" | grep -c tmp)" 0
is "score file still has one link" "$(stat -c %h "$WORK/hb/$STATE/scores.json")" 1

# The common real-world case: ~/.local already exists at 0755.
fresh; mkdir -p "$WORK/hb/.local"; chmod 755 "$WORK/hb/.local"
w '{"best":5}'; is "pre-existing 0755 ~/.local is accepted" "$(r)" '{"best":5}'

if [ "$fails" -eq 0 ]; then echo "all checks passed"; else echo "$fails check(s) failed"; fi
exit $((fails > 0))
