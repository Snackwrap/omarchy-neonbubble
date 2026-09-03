#!/usr/bin/env bash
set -euo pipefail

ID="com.leafbox.neonbubble"
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.config/omarchy/plugins/$ID"

if [[ -e "$DEST" && ! -L "$DEST" ]]; then
  echo "Refusing to overwrite $DEST (exists and is not a symlink)." >&2
  exit 1
fi

ln -sfn "$SRC" "$DEST"
echo "Linked $DEST -> $SRC"

omarchy plugin validate "$SRC" || true

cat <<EOF

Next steps:
  omarchy plugin enable $ID right
  omarchy restart shell

Remove with:
  omarchy plugin disable $ID
  rm "$DEST"
EOF
