#!/usr/bin/env bash
# Title-bar button images for ii-decor's "images" style (a compositor plugin
# draws PNGs only). Breeze-like: a thin glyph; hover/pressed add a filled
# circle, red for close. Args: <theme> <glyph #rrggbb> <hover-fill #rrggbb>
# <close-fill #rrggbb>. Prints JSON {button: {normal, hover, pressed}}.
set -u
theme="$1"; fg="$2"; hv="$3"; cl="$4"
dir="${XDG_CACHE_HOME:-$HOME/.cache}/ii-decor/themes/$theme"; mkdir -p "$dir"
size=64
glyph() { # button -> SVG path data on a 24 grid
    case "$1" in
        minimize)   echo 'M7 10l5 5 5-5' ;;
        maximize)   echo 'M7 14l5-5 5 5' ;;
        close)      echo 'M8 8l8 8M16 8l-8 8' ;;
        pin)        echo 'M12 4v9M8 13h8M12 13v7' ;;
        float)      echo 'M7 7h10v10H7z' ;;
        fullscreen) echo 'M5 9V5h4M15 5h4v4M19 15v4h-4M9 19H5v-4' ;;
    esac
}
svg() { # button state -> svg
    local b="$1" s="$2" bg="none" g="$fg" a=0
    if [ "$s" != normal ]; then
        a=$([ "$s" = hover ] && echo 0.9 || echo 0.7)
        if [ "$b" = close ]; then bg="$cl"; g="#ffffff"; else bg="$hv"; fi
    fi
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 24 24">' $size $size
    [ "$bg" != none ] && printf '<circle cx="12" cy="12" r="11" fill="%s" fill-opacity="%s"/>' "$bg" "$a"
    printf '<path d="%s" fill="none" stroke="%s" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>' "$(glyph "$b")" "$g"
}
out="{"; first=1
for b in minimize maximize close pin float fullscreen; do
    [ $first -eq 1 ] || out+=","; first=0
    out+="\"$b\":{"
    for s in normal hover pressed; do
        f="$dir/$b-$s.png"
        svg "$b" "$s" | rsvg-convert -w $size -h $size -o "$f" 2>/dev/null
        out+="\"$s\":\"$f\""; [ $s != pressed ] && out+=","
    done
    out+="}"
done
echo "$out}"
