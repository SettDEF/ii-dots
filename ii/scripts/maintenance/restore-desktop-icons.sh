#!/usr/bin/env bash
# Put the Icon= line back into local .desktop files that lost it.
#
# A file in ~/.local/share/applications shadows the system one completely, so
# a local override written without Icon= leaves the app with no icon at all —
# which is why Blender and a pile of Lutris games render as a crossed circle.
#
#   restore-desktop-icons.sh --dry-run    show what would change
#   restore-desktop-icons.sh              write the lines
#   restore-desktop-icons.sh --undo <dir> restore from a backup directory
#
# Sources, in order:
#   1. the system .desktop of the same name, if it has an Icon=
#   2. lutris_<slug> in the icon theme, for lutris-<slug>.desktop
#   3. Lutris cover art or banner on disk, by slug, as an absolute path
# Anything with no source is left alone and reported at the end.
set -euo pipefail

APPS="${II_APPS_DIR:-$HOME/.local/share/applications}"
LUTRIS="${II_LUTRIS_DIR:-$HOME/.local/share/lutris}"
HICOLOR="$HOME/.local/share/icons/hicolor"
DRY=0

case "${1:-}" in
    --help|-h) sed -n '2,18p' "$0" | sed 's/^# \?//'; exit 0 ;;
    --dry-run) DRY=1 ;;
    --undo)
        [ -d "${2:-}" ] || { echo "restore-desktop-icons: --undo needs a backup dir" >&2; exit 2; }
        n=0; for f in "$2"/*.desktop; do /usr/bin/cp -- "$f" "$APPS/$(basename "$f")"; n=$((n+1)); done
        echo "restored $n file(s) from $2"; exit 0 ;;
esac

[ -d "$APPS" ] || { echo "no $APPS" >&2; exit 1; }

BACKUP=""
if [ "$DRY" = 0 ]; then
    BACKUP="$APPS/../desktop-icon-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"
fi

icon_for() {   # $1 = basename of the .desktop
    local base=$1 slug sys ico
    sys="/usr/share/applications/$base"
    if [ -f "$sys" ]; then
        ico=$(grep -m1 '^Icon=' "$sys" | cut -d= -f2-)
        [ -n "$ico" ] && { printf '%s' "$ico"; return; }
    fi
    case "$base" in lutris-*)
        slug=${base#lutris-}; slug=${slug%.desktop}
        [ -f "$HICOLOR/128x128/apps/lutris_$slug.png" ] && { printf 'lutris_%s' "$slug"; return; }
        for art in "$LUTRIS/coverart/$slug".*; do
            [ -f "$art" ] && { printf '%s' "$art"; return; }
        done
        for art in "$LUTRIS/banners/$slug".*; do
            [ -f "$art" ] && { printf '%s' "$art"; return; }
        done ;;
    esac
    return 0
}

fixed=0; unresolved=0; unresolved_list=""
for f in "$APPS"/*.desktop; do
    base=$(basename "$f")
    grep -q '^Icon=' "$f" && continue
    grep -q '^Type=Application' "$f" || continue
    # icon_for ends on a failing test when it finds nothing, and set -e
    # would take that as a fatal error for the whole run.
    ico=$(icon_for "$base") || true
    if [ -z "$ico" ]; then
        unresolved=$((unresolved+1)); unresolved_list="$unresolved_list  $base"$'\n'; continue
    fi
    if [ "$DRY" = 1 ]; then
        printf '%-50s Icon=%s\n' "$base" "$ico"
    else
        /usr/bin/cp -- "$f" "$BACKUP/$base"
        # Insert directly after [Desktop Entry] so it lands in the right group.
        awk -v ico="$ico" '
            !done && /^\[Desktop Entry\]/ { print; print "Icon=" ico; done=1; next } { print }
        ' "$f" > "$f.tmp" && /usr/bin/mv "$f.tmp" "$f"
    fi
    fixed=$((fixed+1))
done

if [ "$DRY" = 1 ]; then echo "would fix $fixed; $unresolved have no icon anywhere"
else
    echo "fixed $fixed; $unresolved have no icon anywhere"
    echo "backup: $BACKUP  (undo with --undo \"$BACKUP\")"
fi
[ "$unresolved" -gt 0 ] && { echo "no source for:"; printf '%s' "$unresolved_list" | head -12; }
exit 0
