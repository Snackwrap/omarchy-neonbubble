#!/usr/bin/env bash
# Capture the popup, one PNG per scene, for the marketplace listing assets.
#
# A game is a bad screenshot subject: the interesting frames last a sixteenth
# of a second and the ball is somewhere else by the time grim fires. So the
# panel has a `debugPreviewScene` setting that freezes a composed state —
# mid-play, or the game-over card — and holds it while the shutter opens.
#
# Two things make the capture itself awkward:
#
#   * Clicking a terminal closes the popup, so it has to be driven over IPC
#     (`omarchy-shell shell summon`) rather than opened with the mouse.
#   * The popup is drawn inside a *fullscreen* layer surface, so the compositor
#     cannot tell anyone where it actually is — `hyprctl layers` reports the
#     whole screen.
#
# The second one has an exact answer: ask the panel. With `debugGeometry` on it
# prints its own frame on open, in screen coordinates, once the layout has
# settled. We read that back out of the journal and hand it to grim.
#
# Shooting the screen with the popup open and closed and diffing is the obvious
# alternative and it is a heuristic that loses to anything else that moves —
# an animated wallpaper, a playing video, a blinking cursor. Don't go back.
#
# Usage:  tools/capture-preview.sh [scene ...]     (default: all of them)
set -euo pipefail

ID="com.leafbox.neonbubble"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTDIR="$ROOT/assets/scenes"

SCENES=("$@")
[ ${#SCENES[@]} -eq 0 ] && SCENES=(off play chain gameover)

mkdir -p "$OUTDIR"

# There is no `omarchy bar get`, so read the current values straight out of the
# merged shell config in order to hand them back at the end.
read_setting() {
  python3 - "$ID" "$1" <<'PYEOF'
import json, os, sys
try:
    cfg = json.load(open(os.path.expanduser("~/.config/omarchy/shell.json")))
except Exception:
    sys.exit()
for slot in cfg.get("bar", {}).get("layout", {}).values():
    for w in slot:
        if w.get("id") == sys.argv[1] and sys.argv[2] in w:
            print(w[sys.argv[2]])
PYEOF
}

restore_scene=$(read_setting debugPreviewScene)
restore_geom=$(read_setting debugGeometry)

omarchy bar set "$ID" debugGeometry true

for scene in "${SCENES[@]}"; do
  omarchy bar set "$ID" debugPreviewScene "$scene"
  sleep 1.2                      # let the settings write land before the reread
  omarchy restart shell
  sleep 5                        # the shell needs a beat to come back up

  omarchy-shell shell summon "$ID"
  sleep 4                        # attract animation, then the geometry timer

  # A relative window, not an absolute timestamp: journalctl reads --since in
  # local time, and `date -u` hands it a time in the future on any machine
  # east of UTC, which matches nothing at all.
  geom=$(journalctl --user --since "12 seconds ago" --no-pager 2>/dev/null \
         | grep -oE 'NEON_BUBBLE_GEOMETRY [0-9-]+ [0-9-]+ [0-9]+ [0-9]+' | tail -1 || true)
  if [ -z "$geom" ]; then
    echo "!! $scene: the panel did not report its geometry, skipping" >&2
    omarchy-shell shell hide "$ID" 2>/dev/null || true
    continue
  fi

  read -r _ x y w h <<<"$geom"
  # The popup can lose focus and close between reporting its geometry and the
  # screenshot — and grim will happily photograph whatever is underneath it, so
  # the failure looks like a successful capture of the wrong window. Re-summon,
  # shoot immediately, then check the popup's own border really is in the shot.
  ok=""
  for attempt in 1 2 3 4; do
    omarchy-shell shell summon "$ID"
    sleep 1.4
    grim -g "${x},${y} ${w}x${h}" "$OUTDIR/$scene.png"
    if python3 "$ROOT/tools/verify-shot.py" "$OUTDIR/$scene.png" >/dev/null 2>&1; then
      ok=1
      break
    fi
    echo "   $scene: attempt $attempt caught the window underneath, retrying" >&2
  done
  omarchy-shell shell hide "$ID" 2>/dev/null || true
  if [ -z "$ok" ]; then
    echo "!! $scene: could not catch the popup open, skipping" >&2
    rm -f "$OUTDIR/$scene.png"
    continue
  fi
  echo "   $scene -> assets/scenes/$scene.png ($(magick identify -format '%wx%h' "$OUTDIR/$scene.png"))"
done

# Put the user's own settings back.
omarchy bar set "$ID" debugPreviewScene "${restore_scene:-off}"
omarchy bar set "$ID" debugGeometry "${restore_geom:-false}"
omarchy restart shell
echo "Done. Now run tools/build-preview.sh to compose preview.png."
