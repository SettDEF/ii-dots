#!/usr/bin/env bash
# Window class -> 64px PNG for the ii-decor title bars (a compositor plugin
# cannot read icon themes or SVGs). Args: pairs of <class> <icon-name>.
# Prints a JSON object {class: png}. Converted icons are cached.
set -u
cache="${XDG_CACHE_HOME:-$HOME/.cache}/ii-decor/icons"; mkdir -p "$cache"
theme=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
dirs=()
for base in "$HOME/.local/share/icons" /usr/share/icons; do
    for t in "$theme" hicolor Adwaita breeze; do [ -n "$t" ] && [ -d "$base/$t" ] && dirs+=("$base/$t"); done
done
resolve() { # icon name -> best file
    local n="$1" f
    [ -f "$n" ] && { echo "$n"; return; }
    for d in "${dirs[@]}"; do
        for sz in scalable 512x512 256x256 192x192 128x128 96x96 64x64 48x48; do
            for f in "$d/$sz/apps/$n.svg" "$d/$sz/apps/$n.png" "$d/apps/$sz/$n.svg" "$d/apps/$sz/$n.png"; do
                [ -f "$f" ] && { echo "$f"; return; }
            done
        done
    done
    for f in "/usr/share/pixmaps/$n.png" "/usr/share/pixmaps/$n.svg"; do [ -f "$f" ] && { echo "$f"; return; }; done
}
out="{"; first=1
while [ $# -ge 2 ]; do
    cls="$1"; name="$2"; shift 2
    dest="$cache/$(printf '%s' "$cls" | tr -c 'A-Za-z0-9._-' '_').png"
    if [ ! -s "$dest" ]; then
        src=$(resolve "$name")
        [ -z "$src" ] && continue
        case "$src" in
            *.svg) rsvg-convert -w 64 -h 64 -o "$dest" "$src" 2>/dev/null ;;
            *) magick "$src" -resize 64x64 "$dest" 2>/dev/null ;;
        esac
        [ -s "$dest" ] || continue
    fi
    [ $first -eq 1 ] || out+=","; first=0
    out+="$(printf '%s' "$cls" | jq -R .):$(printf '%s' "$dest" | jq -R .)"
done
echo "$out}"
