#!/usr/bin/env bash

get_pictures_dir() {
    if command -v xdg-user-dir &> /dev/null; then
        xdg-user-dir PICTURES
        return
    fi

    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
    if [ -f "$config_file" ]; then
        local pictures_path
        pictures_path=$(source "$config_file" >/dev/null 2>&1; echo "$XDG_PICTURES_DIR")
        echo "${pictures_path/#\$HOME/$HOME}"
        return
    fi

    echo "$HOME/Pictures"
}

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
PICTURES_DIR=$(get_pictures_dir)
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Quarry 2026-10-20+ has an osu! seasonal source: go through it, and fall back
# to downloading directly below if it cannot answer.
quarry_bin=$(command -v quarry || true)
if [[ -n "$quarry_bin" ]] && grep -q 'wallpaper --random' "$quarry_bin" 2>/dev/null; then
    QUARRY_WALL_QUIET=1 "$SCRIPT_DIR/random_quarry_wall.sh" osu_seasonal 2>/dev/null && exit 0
fi

mkdir -p "$PICTURES_DIR/Wallpapers"

response=$(curl "https://osu.ppy.sh/api/v2/seasonal-backgrounds")
images=$(echo "$response" | jq '.backgrounds | length' -r);
randomIndex=$((RANDOM % images));
link=$(echo "$response" | jq ".backgrounds[$randomIndex].url" -r)
ext=$(echo "$link" | awk -F. '{print $NF}')
downloadPath="$PICTURES_DIR/Wallpapers/random_wallpaper.$ext"
illogicalImpulseConfigPath="$HOME/.config/illogical-impulse/config.json"
currentWallpaperPath=$(jq -r '.background.wallpaperPath' $illogicalImpulseConfigPath)
if [ "$downloadPath" == "$currentWallpaperPath" ]; then
    downloadPath="$PICTURES_DIR/Wallpapers/random_wallpaper-1.$ext"
fi
curl "$link" -o "$downloadPath"
"$SCRIPT_DIR/../switchwall.sh" --image "$downloadPath"
