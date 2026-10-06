#!/usr/bin/env bash
# Turn Windows/WSL symlink stubs back into real symlinks.
#
# A symlink copied through a filesystem that cannot store one (NTFS, a zip made
# on Windows, DrvFs) arrives as a small file beginning "IntxLNK" followed by
# the target in UTF-16LE. It is not a symlink and not an icon, so everything
# that pointed through it renders as missing.
#
#   fix-wsl-symlinks.sh --dry-run <dir>    list what would change
#   fix-wsl-symlinks.sh <dir>              convert them
#
# Only files under 64 bytes that actually start with the marker and decode to
# a non-empty target are touched. Anything else is left alone.
set -euo pipefail

DRY=0
[ "${1:-}" = "--dry-run" ] && { DRY=1; shift; }
DIR=${1:-}
[ -n "$DIR" ] && [ -d "$DIR" ] || { sed -n '2,13p' "$0" | sed 's/^# \?//'; exit 2; }

fixed=0; skipped=0
while IFS= read -r -d '' f; do
    head -c 7 "$f" 2>/dev/null | grep -q 'IntxLNK' || continue
    target=$(tail -c +9 "$f" | iconv -f UTF-16LE -t UTF-8 2>/dev/null | tr -d '\0')
    if [ -z "$target" ]; then skipped=$((skipped+1)); continue; fi
    if [ "$DRY" = 1 ]; then
        printf '%s -> %s\n' "$f" "$target"
    else
        rm -f -- "$f"
        ln -s -- "$target" "$f"
    fi
    fixed=$((fixed+1))
done < <(find "$DIR" -type f -size -64c -print0 2>/dev/null)

if [ "$DRY" = 1 ]; then echo "would convert $fixed stub(s); $skipped undecodable"
else echo "converted $fixed stub(s); $skipped undecodable"; fi
