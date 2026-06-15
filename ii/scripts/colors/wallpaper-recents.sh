#!/bin/bash
# Wallpaper-recents helpers.
#
# Subcommands:
#   list           Print up to 40 valid wallpaper paths (newest first).
#                  For entries whose original path no longer exists, search
#                  $WALLPAPER_ROOTS for a file with the same basename and
#                  emit the first match. Unresolvable entries are dropped.
#
#   repair         Rewrite the JSONL file in place: drop unresolvable entries,
#                  rewrite stale paths to their relocated counterparts.
#
# Why: paths drift over time (re-org into subfolders, downloads renamed,
# files moved between machines). The file should self-heal so the popup
# stays useful.

set -e

RECENTS="${RECENTS_FILE:-$HOME/.local/state/quickshell/wallpaper-recents.jsonl}"

# Common roots to search by basename when a recents path is dead.
# Order matters — prefer Wallpapers/ over generic Pictures/.
WALLPAPER_ROOTS=(
    "$HOME/Pictures/Wallpapers"
    "$HOME/.wallpapers"
    "$HOME/Pictures"
    "$HOME/Downloads"
    "$HOME/.cache/quickshell/walltune"
)

# Resolve a possibly-stale path. Echoes the resolved path on stdout, or
# nothing if unrecoverable.
resolve() {
    local p="$1"
    [[ -f "$p" ]] && { echo "$p"; return; }
    local bn; bn="$(basename "$p")"
    [[ -z "$bn" ]] && return
    local root found
    for root in "${WALLPAPER_ROOTS[@]}"; do
        [[ -d "$root" ]] || continue
        found="$(find "$root" -maxdepth 5 -type f -name "$bn" 2>/dev/null | head -n 1)"
        if [[ -n "$found" ]]; then echo "$found"; return; fi
    done
}

cmd_list() {
    [[ -f "$RECENTS" ]] || return 0
    # Newest first, dedupe by raw stored path, then resolve & dedupe by resolved path.
    tac "$RECENTS" \
        | jq -r 'select(.path != null) | .path' 2>/dev/null \
        | awk '!seen[$0]++' \
        | while IFS= read -r p; do
            r="$(resolve "$p")"
            [[ -n "$r" ]] && echo "$r"
          done \
        | awk '!seen[$0]++' \
        | head -n 40
}

cmd_repair() {
    [[ -f "$RECENTS" ]] || return 0
    local tmp; tmp="$(mktemp)"
    # Walk in chronological order so latest entry stays last.
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local p ts r
        p="$(echo "$line" | jq -r '.path // empty')"
        ts="$(echo "$line" | jq -r '.ts // empty')"
        [[ -z "$p" ]] && continue
        r="$(resolve "$p")"
        [[ -z "$r" ]] && continue
        jq -cn --arg p "$r" --argjson t "${ts:-0}" '{type:"recent",path:$p,ts:$t}' >> "$tmp"
    done < "$RECENTS"
    # Cap at 40
    if [[ $(wc -l < "$tmp") -gt 40 ]]; then
        local tmp2; tmp2="$(mktemp)"
        tail -n 40 "$tmp" > "$tmp2"
        mv "$tmp2" "$tmp"
    fi
    mv "$tmp" "$RECENTS"
    echo "Repaired: $(wc -l < "$RECENTS") entries"
}

case "${1:-}" in
    list)   cmd_list ;;
    repair) cmd_repair ;;
    *)      echo "Usage: $0 {list|repair}" >&2; exit 2 ;;
esac
