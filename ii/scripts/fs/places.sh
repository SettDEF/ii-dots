#!/usr/bin/env bash
# Prints the user's file-manager places as "path<TAB>name", one per line.
#
# Reads KDE's own bookmark file so the grid matches Dolphin's sidebar, topped
# up with the XDG folders. Only real existing local directories survive — the
# xbel also holds search queries, trash, network and application shortcuts,
# which a folder grid has no use for. Deduplicated by PATH, first name wins.
set -u
XBEL="${XDG_DATA_HOME:-$HOME/.local/share}/user-places.xbel"

{
    if [ -r "$XBEL" ]; then
        # href precedes its title inside each <bookmark>, so pair in order and
        # take only the first title after each href.
        sed -n 's/.*<bookmark href="\([^"]*\)".*/H\t\1/p; s@.*<title>\(.*\)</title>.*@T\t\1@p' "$XBEL" \
        | awk -F'\t' '
            $1=="H" { href=$2; next }
            $1=="T" && href!="" {
                if (href ~ /^file:\/\//) { p=substr(href,8); gsub(/%20/," ",p); print p "\t" $2 }
                href=""
            }'
    fi
    for pair in "$HOME:Home" "$HOME/Desktop:Desktop" "$HOME/Documents:Documents" \
                "$HOME/Downloads:Downloads" "$HOME/Pictures:Pictures" \
                "$HOME/Music:Music" "$HOME/Videos:Videos"; do
        printf '%s\t%s\n' "${pair%%:*}" "${pair##*:}"
    done
} | awk -F'\t' '!seen[$1]++ { print }' \
  | while IFS=$'\t' read -r p n; do [ -d "$p" ] && printf '%s\t%s\n' "$p" "$n"; done
