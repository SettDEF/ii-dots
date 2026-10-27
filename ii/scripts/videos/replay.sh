#!/usr/bin/env bash
# Instant replay: gpu-screen-recorder keeps the last 60 s of the focused monitor
# (with desktop audio) in RAM; "save" writes them to a file.
#
#   replay.sh           start the buffer, or stop it if it is running
#   replay.sh save      save the last 60 s (starts the buffer if it is off)

DIR=/mnt/storage/Videos/Replays
SECONDS_KEPT=60
PATTERN='^gpu-screen-recorder .* -r '

notify() { notify-send "$1" "$2" -a 'Replay' & disown; }

start() {
    mkdir -p "$DIR"
    local mon
    mon=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')
    setsid gpu-screen-recorder -w "$mon" -f 60 -k h264 -q high -cursor yes \
        -a default_output -c mp4 -r "$SECONDS_KEPT" -replay-storage ram \
        -o "$DIR" >/dev/null 2>&1 &
    notify "Replay buffer on" "Alt+F10 saves the last ${SECONDS_KEPT}s of $mon"
}

case "${1:-toggle}" in
    save)
        if pgrep -f "$PATTERN" >/dev/null; then
            pkill -USR1 -f "$PATTERN"
            notify "Replay saved" "Last ${SECONDS_KEPT}s -> $DIR"
        else
            start
        fi ;;
    *)
        if pgrep -f "$PATTERN" >/dev/null; then
            pkill -INT -f "$PATTERN"
            notify "Replay buffer off" ""
        else
            start
        fi ;;
esac
