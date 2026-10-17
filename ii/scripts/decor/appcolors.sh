#!/usr/bin/env bash
# Title-bar colours that follow each app's own theme. Args: pairs of
# <class> <pid>. Prints JSON {class: {bar: "#rrggbb", text: "#rrggbb"}} for
# apps whose toolkit is known; others are left to the global bar colour.
# Toolkit is read from the libraries the process has loaded.
set -u
ini() { awk -v s="[$1]" -v k="$2=" '$0==s{f=1;next} /^\[/{f=0} f&&index($0,k)==1{sub(k,"");print;exit}' "$3" 2>/dev/null; }
kde="$HOME/.config/kdeglobals"
qt_bar=$(ini Colors:Header BackgroundNormal "$kde"); qt_fg=$(ini Colors:Header ForegroundNormal "$kde")
# Translucent Qt styles paint their toolbars see-through on top of the window's
# own opacity; the bar has to match that, or it reads as a solid strip.
case "$(ini KDE widgetStyle "$kde")" in
    Darkly|Lightly) qt_alpha=0.6 ;;
    *) qt_alpha=1 ;;
esac
gtk_css="$HOME/.config/gtk-3.0/gtk.css"
gtk_bar=$(sed -n 's/^@define-color window_bg_color \(#[0-9a-fA-F]\{6\}\);.*/\1/p' "$gtk_css" 2>/dev/null | head -1)
gtk_fg=$(sed -n 's/^@define-color window_fg_color \(#[0-9a-fA-F]\{6\}\);.*/\1/p' "$gtk_css" 2>/dev/null | head -1)
term_bar=$(sed -n 's/^\s*background\s*=\s*"\(#[0-9a-fA-F]\{6\}\)".*/\1/p' "$HOME/.config/wezterm/tinct_colors.lua" 2>/dev/null | head -1)
term_fg=$(sed -n 's/^\s*foreground\s*=\s*"\(#[0-9a-fA-F]\{6\}\)".*/\1/p' "$HOME/.config/wezterm/tinct_colors.lua" 2>/dev/null | head -1)
kitty_bar=$(awk '$1=="background"{print $2;exit}' "$HOME/.local/state/quickshell/user/generated/terminal/kitty-theme.conf" 2>/dev/null)
kitty_fg=$(awk '$1=="foreground"{print $2;exit}' "$HOME/.local/state/quickshell/user/generated/terminal/kitty-theme.conf" 2>/dev/null)
# Konsole paints its terminal in its own colour scheme: the bar matches that.
konsole_color() { # Background|Foreground -> #rrggbb from the default profile's scheme
    local prof scheme f rgb
    prof=$(ini "Desktop Entry" DefaultProfile "$HOME/.config/konsolerc"); [ -n "$prof" ] || return
    scheme=$(ini Appearance ColorScheme "$HOME/.local/share/konsole/$prof"); [ -n "$scheme" ] || return
    for f in "$HOME/.local/share/konsole/$scheme.colorscheme" "/usr/share/konsole/$scheme.colorscheme"; do
        [ -f "$f" ] || continue
        rgb=$(ini "$1" Color "$f"); [ -n "$rgb" ] || return
        printf '#%02x%02x%02x' $(echo "$rgb" | tr ',' ' '); return
    done
}
out="{"; first=1
emit() { [ -n "$2" ] || return; [ $first -eq 1 ] || out+=","; first=0
    out+="$(printf '%s' "$1" | jq -R .):{\"bar\":\"$2\",\"text\":\"${3:-}\",\"alpha\":${4:-1}}"; }
# The KDE scheme on its own, for "KDE colours everywhere".
emit "__kde__" "$qt_bar" "$qt_fg"
while [ $# -ge 2 ]; do
    cls="$1"; pid="$2"; shift 2
    case "$cls" in
        org.wezfurlong.wezterm|zash) emit "$cls" "$term_bar" "$term_fg"; continue ;;
        kitty) emit "$cls" "$kitty_bar" "$kitty_fg"; continue ;;
        org.kde.konsole) emit "$cls" "$(konsole_color Background)" "$(konsole_color Foreground)"; continue ;;
    esac
    maps="/proc/$pid/maps"; [ -r "$maps" ] || continue
    if grep -qm1 'libQt[56]Core' "$maps"; then emit "$cls" "$qt_bar" "$qt_fg" "$qt_alpha"
    elif grep -qm1 'libgtk-[34]' "$maps"; then emit "$cls" "$gtk_bar" "$gtk_fg"
    fi
done
echo "$out}"
