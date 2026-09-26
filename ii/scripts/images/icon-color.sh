#!/usr/bin/env bash
# Average colour of an app icon, printed as #rrggbb. Nothing on stdout when
# the icon cannot be found, so the caller keeps its own fallback.
#
# Quickshell.iconPath() hands back an "image://icon/<name>" URL and
# ColorQuantizer can only read real files, so the name is resolved on disk.
#
# The CONFIGURED THEME IS SEARCHED FIRST. Sampling hicolor/Papirus instead
# meant the colour came from a different file than the one on screen — Dolphin
# is blue in Papirus and yellow in Reversal, and the dock draws the yellow one.
set -u
shopt -s nullglob
name="${1:-}"
[ -n "$name" ] || exit 1

icon_theme() {
    local t
    t=$(sed -n 's/^Theme=//p' "${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals" 2>/dev/null | head -1)
    [ -n "$t" ] || t=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
    printf '%s' "${t:-hicolor}"
}

# Themes lay icons out as <theme>/<size>/apps or <theme>/apps/<size>; scalable
# goes by either name. Try the lot rather than guess.
theme_dirs() {
    local t=$1
    for root in "$HOME/.local/share/icons/$t" "$HOME/.icons/$t" "/usr/share/icons/$t"; do
        [ -d "$root" ] || continue
        printf '%s\n' "$root/apps/scalable" "$root/scalable/apps" \
            "$root/256x256/apps" "$root/128x128/apps" "$root/64x64/apps" \
            "$root/48x48/apps" "$root/apps/64" "$root/apps/48" "$root/apps"
    done
}

resolve() {
    case "$1" in
        /*) [ -f "$1" ] && { printf '%s' "$1"; return 0; }; return 1 ;;
    esac
    local d e
    # 1. the theme the desktop is actually using, 2. hicolor, 3. anything.
    for d in $(theme_dirs "$(icon_theme)") $(theme_dirs hicolor) \
             "$HOME/.local/share/icons/hicolor"/{256x256,128x128,64x64,48x48,scalable}/apps \
             /usr/share/icons/hicolor/{256x256,128x128,64x64,48x48,scalable}/apps \
             /usr/share/pixmaps; do
        [ -d "$d" ] || continue
        for e in svg png svgz xpm; do
            [ -f "$d/$1.$e" ] && { printf '%s' "$d/$1.$e"; return 0; }
        done
    done
    local f
    for f in /usr/share/icons/*/*/apps/"$1".* "$HOME"/.local/share/icons/*/*/apps/"$1".*; do
        [ -f "$f" ] && { printf '%s' "$f"; return 0; }
    done
    return 1
}

file=$(resolve "$name") || exit 1
# -resize 1x1 weights by alpha, so transparent padding doesn't drag every
# icon towards black.
hex=$(magick "$file" -background none -resize '1x1!' -alpha off \
        -format '%[hex:p{0,0}]' info: 2>/dev/null) || exit 1
[ -n "$hex" ] && printf '#%s' "$hex"
