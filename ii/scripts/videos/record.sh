#!/usr/bin/env bash
# Screen recording with gpu-screen-recorder: encoded on the GPU (VAAPI), so it
# barely costs CPU even while gaming. Run again to stop; the file is finished
# on stop.
#
#   record.sh                         pick a region (slurp), no sound
#   record.sh --region 'X,Y WxH'      region in logical (scaled) pixels, as slurp prints it
#   record.sh --fullscreen            the focused monitor
#   record.sh --sound                 add desktop audio
#   record.sh --mic                   add the microphone (with or without --sound)
#   record.sh --gif                   also convert the finished file to a GIF (to-gif, beside the .mp4)
#
# The shell finds a running recording with: pgrep -f '^gpu-screen-recorder .* -o .*\.mp4$'
# (replay.sh's -o is a folder, not an .mp4, so the replay buffer does not count).

CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
RECORDING_DIR=$(jq -r '.screenRecord.savePath // empty' "$CONFIG_FILE" 2>/dev/null)
# The root disk is nearly full; never default to it.
[[ -z "$RECORDING_DIR" || "$RECORDING_DIR" == "$HOME" ]] && RECORDING_DIR=/mnt/storage/Videos/Recordings

notify() { notify-send "$1" "$2" -a 'Recorder' & disown; }

if pgrep -f '^gpu-screen-recorder .* -o .*\.mp4$' >/dev/null; then
    pkill -INT -f '^gpu-screen-recorder .* -o .*\.mp4$'
    notify "Recording stopped" "Saved to $RECORDING_DIR"
    exit 0
fi
if pgrep -x wf-recorder >/dev/null; then   # a recording started by the old script
    pkill -INT wf-recorder
    notify "Recording stopped" "Stopped"
    exit 0
fi

REGION="" SOUND=0 MIC=0 FULLSCREEN=0 GIF=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --region)
            [[ -n "$2" ]] || { notify "Recording cancelled" "No region specified for --region"; exit 1; }
            REGION="$2"; shift ;;
        --sound) SOUND=1 ;;
        --mic) MIC=1 ;;
        --fullscreen) FULLSCREEN=1 ;;
        --gif) GIF=1 ;;
    esac
    shift
done

mkdir -p "$RECORDING_DIR"
FILE="$RECORDING_DIR/recording_$(date '+%Y-%m-%d_%H.%M.%S').mp4"

if [[ $FULLSCREEN -eq 1 ]]; then
    TARGET=(-w "$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')")
else
    if [[ -z "$REGION" ]] && { ! REGION="$(slurp 2>/dev/null)" || [[ -z "$REGION" ]]; }; then
        notify "Recording cancelled" "Selection was cancelled"
        exit 1
    fi
    # slurp's "X,Y WxH" -> gpu-screen-recorder's "WxH+X+Y" (both logical pixels)
    read -r pos size <<< "$REGION"
    TARGET=(-w "${size}+${pos%,*}+${pos#*,}")
fi

AUDIO=()
if [[ $SOUND -eq 1 && $MIC -eq 1 ]]; then AUDIO=(-a "default_output|default_input")
elif [[ $SOUND -eq 1 ]]; then AUDIO=(-a default_output)
elif [[ $MIC -eq 1 ]]; then AUDIO=(-a default_input)
fi

notify "Recording started" "$(basename "$FILE")"
gpu-screen-recorder "${TARGET[@]}" -f 60 -k h264 -q very_high -fm cfr -cursor yes "${AUDIO[@]}" -o "$FILE"

# the GIF is made once the recording is finished; the .mp4 stays beside it
if [[ $GIF -eq 1 ]]; then
    if GIF_FILE="$("$(dirname "$0")/to-gif" "$FILE")"; then
        notify "GIF saved" "$(basename "$GIF_FILE")"
    else
        notify "GIF failed" "The recording is kept: $(basename "$FILE")"
    fi
fi
