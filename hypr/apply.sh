#!/usr/bin/env bash
# Copy this starter config over an existing ~/.config/hypr, substituting the
# shell name as bootstrap.sh does.
#
# bootstrap.sh refuses to touch a ~/.config/hypr that already exists, so
# updating it afterwards means copying by hand -- and a plain cp leaves the
# @SHELL_NAME@ placeholders in, which makes Hyprland exec `qs -c @SHELL_NAME@`
# and leaves you with a bare compositor.
#
#   ./hypr/apply.sh [config-name]     (default: ii)

set -euo pipefail
NAME="${1:-ii}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.config/hypr"

[ -d "$DEST" ] || { echo "no $DEST — run bootstrap.sh instead" >&2; exit 1; }

cp -r "$SRC/." "$DEST/"
grep -rl '@SHELL_NAME@' "$DEST" 2>/dev/null \
    | while IFS= read -r f; do sed -i "s/@SHELL_NAME@/$NAME/g" "$f"; done

remaining=$(grep -rl '@SHELL_NAME@' "$DEST" 2>/dev/null | wc -l)
[ "$remaining" -eq 0 ] || { echo "warn: $remaining file(s) still hold @SHELL_NAME@" >&2; }

echo "applied to $DEST as '$NAME'"
command -v hyprctl >/dev/null && hyprctl reload >/dev/null 2>&1 && hyprctl configerrors
