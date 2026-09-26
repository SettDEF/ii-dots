#!/usr/bin/env bash

# Check if process is running
PID=$(pgrep -ix minimeters | head -1)

# Check if mapped as a window
CLIENT_INFO=$(hyprctl clients -j | jq '.[] | select(.class | match("minimeters"; "i"))' 2>/dev/null)

if [ -z "$PID" ]; then
    OPTIONS="▶ Start MiniMeters"
elif [ -n "$CLIENT_INFO" ]; then
    ADDRESS=$(echo "$CLIENT_INFO" | jq -r '.address')
    PINNED=$(echo "$CLIENT_INFO" | jq -r '.pinned')
    FLOATING=$(echo "$CLIENT_INFO" | jq -r '.floating')
    
    PIN_STATUS="Unpinned"
    [[ "$PINNED" == "true" ]] && PIN_STATUS="Pinned"
    
    FLOAT_STATUS="Tiled"
    [[ "$FLOATING" == "true" ]] && FLOAT_STATUS="Floating"
    
    OPTIONS="📌 Toggle Pin (Follow Workspaces) | [Currently: $PIN_STATUS]
🖥️ Toggle Floating Mode | [Currently: $FLOAT_STATUS]
🔝 Bring to Front / Focus
🔄 Restart MiniMeters
🛑 Stop MiniMeters"
else
    # Running, but no window client found (likely in Stick/Layer mode)
    OPTIONS="💡 Disable Stick Mode (Inside MiniMeters Settings) to allow dragging/pinning
🔄 Restart MiniMeters
🛑 Stop MiniMeters"
fi

CHOICE=$(echo -e "$OPTIONS" | fuzzel -d -p "MiniMeters Control" --width=55 --lines=6)

case "$CHOICE" in
    *Start*)
        "$HOME/Applications/MiniMeters-x86_64.AppImage" &
        ;;
    *Pin*)
        hyprctl dispatch "hl.dsp.window.pin({ window = \"address:$ADDRESS\" })"
        ;;
    *Floating*)
        hyprctl dispatch "hl.dsp.window.float({ action = \"toggle\", window = \"address:$ADDRESS\" })"
        ;;
    *Front*)
        hyprctl dispatch "hl.dsp.focus({ window = \"address:$ADDRESS\" })"
        ;;
    *Restart*)
        pkill -ix minimeters
        sleep 0.4
        nohup "$HOME/Applications/MiniMeters-x86_64.AppImage" >/dev/null 2>&1 &
        ;;
    *Stop*)
        pkill -ix minimeters
        ;;
esac
