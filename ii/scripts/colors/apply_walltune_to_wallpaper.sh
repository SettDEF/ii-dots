#!/usr/bin/env bash

# This script applies the active WallTune settings (sliders, curves, filters, remappings)
# from walltune-state.json to a newly selected wallpaper, processes it via ImageMagick,
# and triggers the standard Quickshell switchwall.sh theme application pipeline.

NEW_WALL="$1"
MODE="${2:-dark}"  # "dark" or "light"

if [ -z "$NEW_WALL" ]; then
    echo "Usage: $0 <new_wallpaper_path> [mode]"
    exit 1
fi

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$CONFIG_DIR/scripts/colors"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
STATE_FILE="$STATE_DIR/walltune-state.json"

if [ ! -f "$STATE_FILE" ]; then
    echo "No WallTune state file found. Running default switchwall..."
    "$SCRIPT_DIR/switchwall.sh" --image "$NEW_WALL" --mode "$MODE"
    exit 0
fi

# Load active configuration values
slVibrance=$(jq -r '.slVibrance // 50' "$STATE_FILE")
slContrast=$(jq -r '.slContrast // 50' "$STATE_FILE")
slTemperature=$(jq -r '.slTemperature // 50' "$STATE_FILE")
slBrightness=$(jq -r '.slBrightness // 50' "$STATE_FILE")
slSaturation=$(jq -r '.slSaturation // 50' "$STATE_FILE")
slHueShift=$(jq -r '.slHueShift // 50' "$STATE_FILE")
slHighlight=$(jq -r '.slHighlight // 50' "$STATE_FILE")
slShadow=$(jq -r '.slShadow // 50' "$STATE_FILE")
slGrain=$(jq -r '.slGrain // 0' "$STATE_FILE")
slSharpness=$(jq -r '.slSharpness // 50' "$STATE_FILE")
selectedTheory=$(jq -r '.selectedTheory // ""' "$STATE_FILE")
selectedStyle=$(jq -r '.selectedStyle // ""' "$STATE_FILE")
selectedPractical=$(jq -r '.selectedPractical // ""' "$STATE_FILE")
remapPalette=$(jq -r '.remapPalette // ""' "$STATE_FILE")
remapColors=$(jq -r '.remapColors // 32' "$STATE_FILE")
remapDither=$(jq -r '.remapDither // "FloydSteinberg2x2"' "$STATE_FILE")
selectedMode=$(jq -r '.selectedMode // ""' "$STATE_FILE")
lastSlot=$(jq -r '.lastProcessedSlot // "a"' "$STATE_FILE")
curvePoints=$(jq -r '.curvePoints // "[[0,0],[1,1]]"' "$STATE_FILE")
# Draggable "Active mix" chip order, e.g. ["remap","theory","style"] -> CSV.
mixOrder=$(jq -r '(.mixOrder // []) | join(",")' "$STATE_FILE")

# Toggle processed slots to trigger QML Image reloads
if [ "$lastSlot" = "a" ]; then
    slot="b"
else
    slot="a"
fi

tmp="$CACHE_DIR/processed-$slot.png"

# Map sliders to the adjust values (ImageMagick's scale)
brightness=$((slBrightness + 50))
saturation=$((slSaturation * 2))
hue=$((slHueShift * 2))
contrast=$(( (slContrast - 50) * 2 ))
sharpness="0"
if [ "$slSharpness" -gt 50 ]; then
    sharpness=$(echo "scale=1; ($slSharpness - 50) / 10" | bc)
fi
blur="0"
if [ "$slSharpness" -lt 50 ]; then
    blur=$(echo "scale=1; (50 - $slSharpness) / 20" | bc)
fi
grain=$((slGrain * 4 / 10))
temp=$((slTemperature - 50))
tBoost=$(( (temp < 0 ? -temp : temp) * 8 / 10 ))

# Palette remap runs FIRST — quantise the source onto the chosen palette,
# then the adjustments below run on top so the sliders/curve stay
# visible. (A quantise-last order snapped every pixel back to a fixed swatch
# and wiped the adjustments — popular palettes "didn't support" them.)
adjustSrc="$NEW_WALL"
if [ -n "$remapPalette" ] && [ "$remapPalette" != "null" ]; then
    rdmc="$HOME/.scripts/rdmcpape"
    if [ -f "$rdmc" ]; then
        if [ "$remapPalette" = "matugen" ]; then
            palArg="--matugen"
        else
            palArg="--palette $remapPalette"
        fi
        mkdir -p "$CACHE_DIR"
        "$rdmc" $palArg --colors "$remapColors" --dither "$remapDither" --output "$tmp" "$NEW_WALL"
        adjustSrc="$tmp"
    fi
fi

args=("$HOME/.local/bin/tinct" image adjust --brightness "$brightness" --saturation "$saturation" --hue "$hue" --contrast "$contrast")
if [ "$temp" -gt 0 ]; then
    args+=(--temperature "$tBoost")
elif [ "$temp" -lt 0 ]; then
    args+=(--temperature "-$tBoost")
fi
[ "$(echo "$sharpness > 0" | bc)" -eq 1 ] && args+=(--sharpen "$sharpness")
[ "$(echo "$blur > 0" | bc)" -eq 1 ] && args+=(--blur "$blur")
[ "$grain" -gt 0 ] && args+=(--grain "$(echo "scale=2; $grain / 100" | bc)")
if [ "$curvePoints" != "[[0,0],[1,1]]" ] && [ -n "$curvePoints" ] && [ "$curvePoints" != "null" ]; then
    args+=(--curve "$(echo "$curvePoints" | jq -r 'map(join(",")) | join(";")')")
fi

args+=("$adjustSrc" "$tmp")

mkdir -p "$CACHE_DIR"
"${args[@]}"

# Call switchwall to rebuild the palette and update running apps
switchwall="$SCRIPT_DIR/switchwall.sh"
theoryArg=""; [ -n "$selectedTheory" ] && [ "$selectedTheory" != "null" ] && theoryArg="--theory $selectedTheory"
styleArg=""; [ -n "$selectedStyle" ] && [ "$selectedStyle" != "null" ] && styleArg="--style $selectedStyle"
practicalArg=""; [ -n "$selectedPractical" ] && [ "$selectedPractical" != "null" ] && practicalArg="--practical $selectedPractical"
remapArg=""; [ -n "$remapPalette" ] && [ "$remapPalette" != "matugen" ] && [ "$remapPalette" != "null" ] && remapArg="--remap $remapPalette"

typeArg=""; [ -n "$selectedMode" ] && [ "$selectedMode" != "null" ] && typeArg="--type $selectedMode"
mixOrderArg=""; [ -n "$mixOrder" ] && [ "$mixOrder" != "null" ] && mixOrderArg="--mix-order $mixOrder"

"$switchwall" --image "$tmp" --mode "$MODE" --no-wallpaper-update $typeArg $theoryArg $styleArg $practicalArg $remapArg $mixOrderArg

# Update configuration file: wallpaperPath = processed slot;
# wallpaperSourcePath = original source (the slot alternates between
# processed-a/b, so per-file crop must key by the un-edited source).
jq --arg p "$tmp" --arg src "$NEW_WALL" '.background.wallpaperPath = $p | .background.wallpaperSourcePath = $src' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"

# Save the updated sourceWall and slot state to walltune-state.json
jq --arg w "$NEW_WALL" --arg s "$slot" '.sourceWall = $w | .lastProcessedSlot = $s' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

# Append to history
hist="$STATE_DIR/walltune-history.jsonl"
cj="$STATE_DIR/user/generated/colors.json"
if [ -f "$cj" ]; then
    pri=$(jq -r '.primary // ""' "$cj")
    sec=$(jq -r '.secondary // ""' "$cj")
    ter=$(jq -r '.tertiary // ""' "$cj")
    snapJson=$(cat "$STATE_FILE")
    ts=$(date +%s)
    thumb_dir="$CACHE_DIR/walltune/thumbs"
    mkdir -p "$thumb_dir"
    thumb_path="$thumb_dir/$ts.png"
    
    # Generate visual thumbnail of the processed wallpaper
    "$HOME/.local/bin/tinct" image thumb --size 160 --jobs 1 "$tmp" "$thumb_path"
    
    jq -cn --arg p "$pri" --arg s "$sec" --arg t "$ter" --arg w "$NEW_WALL" \
          --arg th "$thumb_path" --argjson st "$snapJson" --argjson ts "$ts" \
          '{ts:$ts, primary:$p, secondary:$s, tertiary:$t, wallpaper:$w, thumbnail:$th, state:$st}' >> "$hist"

    if [ $(wc -l < "$hist") -gt 40 ]; then
        tmp_hist=$(mktemp) && tail -n 40 "$hist" > "$tmp_hist" && mv "$tmp_hist" "$hist"
    fi
fi

echo "WallTune adjustments successfully applied to new wallpaper!"

