#!/usr/bin/env bash
# A random SFW wallpaper from one of Quarry's sources, saved to ~/Pictures/Wallpapers and applied.
#   random_quarry_wall.sh konachan        any Quarry source id (quarry's `sources` request lists them)
#   random_quarry_wall.sh --print konachan   saves it and prints the path, without applying it
# Talks to quarryd over its socket (PROTOCOL.md): search a random page of the source, pick a
# random still picture of it from the catalogue, export it whole, then switchwall.sh, which also
# regenerates the colours.
set -euo pipefail

apply=1
if [[ "${1:-}" == --print ]]; then apply=0; shift; fi
source_id="${1:?usage: random_quarry_wall.sh [--print] SOURCE}"
sock="${QUARRY_SOCK:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quarry/sock}"
pictures=$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
switchwall="$script_dir/../switchwall.sh"
filter="kind:wallpaper -nsfw -video"

fail() { [[ -n "${QUARRY_WALL_QUIET:-}" ]] || notify-send -a Wallpaper "No wallpaper from $source_id" "$1" 2>/dev/null || true; echo "random_quarry_wall: $1" >&2; exit 1; }

# Quarry 2026-10-20+: one command does all of it (fresh random order, the file as it is).
quarry_bin=$(command -v quarry || true)
if [[ -n "$quarry_bin" ]] && grep -q 'wallpaper --random' "$quarry_bin" 2>/dev/null; then
    mkdir -p "$pictures/Wallpapers"
    if ! path=$("$quarry_bin" wallpaper --random --source "$source_id" --query "$filter" \
            --path "$pictures/Wallpapers/{slug}.{ext}" 2>&1); then
        fail "${path#quarry wallpaper: }"
    fi
    [[ -f "$path" ]] || fail "The export did not write a file."
    (( apply )) || { echo "$path"; exit 0; }
    exec "$switchwall" --image "$path"
fi
# Older quarry: the four-request way below.
[[ -S "$sock" ]] || fail "Quarry's daemon is not running (no $sock)."

# one connection for every request (a query's result belongs to it): socat between two fifos
tmp=$(mktemp -d); trap 'rm -rf "$tmp"; kill $(jobs -p) 2>/dev/null || true' EXIT
mkfifo "$tmp/in" "$tmp/out"
socat -t 60 - UNIX-CONNECT:"$sock" <"$tmp/in" >"$tmp/out" 2>/dev/null &
exec 3>"$tmp/in" 4<"$tmp/out"
n=0
# one request; its response's payload goes to $answer (events and other answers are skipped)
answer=""
ask() {
    n=$((n + 1))
    jq -cn --argjson id "$n" --arg m "$1" --argjson p "$2" '{t: "req", id: $id, m: $m, p: $p}' >&3
    local line
    while IFS= read -r -t 60 line <&4; do
        [[ $(jq -r 'select(.t == "res") | .id' <<<"$line") == "$n" ]] || continue
        [[ $(jq -r .ok <<<"$line") == true ]] || fail "$(jq -r '.err // "the daemon said no"' <<<"$line")"
        answer=$(jq -c .p <<<"$line")
        return 0
    done
    fail "Quarry did not answer in time."
}

# fresh rows: a random page among the first ten (the site's newest are the same every time)
ask search "$(jq -cn --arg s "$source_id" --arg q "$filter" --argjson page $((RANDOM % 10 + 1)) '{source: $s, q: $q, page: $page}')"
ask query "$(jq -cn --arg q "source:$source_id $filter" '{q: $q}')"; qid=$(jq -r .queryId <<<"$answer")
# a random place in it (quarry's sort:random has a fixed seed: always the same first picture)
count=$(jq -r '.count // 0' <<<"$answer")
(( count > 0 )) || fail "Quarry has no still wallpaper from $source_id yet."
offset=$(( (RANDOM * 32768 + RANDOM) % count ))
ask items "$(jq -cn --argjson q "$qid" --argjson o "$offset" '{queryId: $q, offset: $o, limit: 1}')"; item=$(jq -c '.items[0] // {}' <<<"$answer"); id=$(jq -r '.id // empty' <<<"$item")
[[ -n "$id" ]] || fail "Quarry has no still wallpaper from $source_id yet."

mkdir -p "$pictures/Wallpapers"
# whole: its own size and format (a recipe always names a size)
recipe=$(jq -c '{width: .w, height: .h, fit: "none", gravity: "center", format: ((.ext // "png") | if . == "jpeg" then "jpg" else . end), quality: 95, radius: 0, background: "#00000000"}' <<<"$item")
ask export "$(jq -cn --arg id "$id" --arg p "$pictures/Wallpapers/{slug}.{ext}" --argjson r "$recipe" '{id: $id, recipe: $r, path: $p}')"; path=$(jq -r .path <<<"$answer")
[[ -f "$path" ]] || fail "The export did not write a file."
(( apply )) || { echo "$path"; exit 0; }
exec "$switchwall" --image "$path"
