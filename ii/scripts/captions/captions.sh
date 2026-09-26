#!/usr/bin/env bash
# Live captions: listen to an audio node, print what is said, one JSON line each.
#
# WHY A SCRIPT AND NOT QML
#   This is a pipeline — record a chunk, transcribe it, maybe translate it,
#   repeat — and a pipeline is what a shell is for. QML runs this once and reads
#   stdout; it never has to know how whisper is invoked.
#
# WHERE THE AUDIO GOES
#   Nowhere. Transcription is local (whisper.cpp). Only if you ask for a target
#   language other than English does any TEXT leave the machine, and then it is
#   text only — the recording never does. That distinction matters here: the
#   voices being captioned are usually other people's.
#
# Usage:
#   captions.sh --target <node> [--model PATH] [--chunk SECONDS]
#               [--lang auto] [--translate-to English]
#
# Emits one JSON object per line: {"t":<epoch>,"text":"…","translation":"…"}
set -uo pipefail

TARGET=""
MODEL="${WHISPER_MODEL:-$HOME/.local/share/whisper/ggml-base.bin}"
CHUNK=5
LANG_IN="auto"
TRANSLATE_TO=""
COPILOT="$HOME/.config/quickshell/ii/scripts/copilot/copilot.sh"

while [ $# -gt 0 ]; do
    case "$1" in
        --target)       TARGET="$2"; shift 2 ;;
        --model)        MODEL="$2"; shift 2 ;;
        --chunk)        CHUNK="$2"; shift 2 ;;
        --lang)         LANG_IN="$2"; shift 2 ;;
        --translate-to) TRANSLATE_TO="$2"; shift 2 ;;
        -h|--help)      sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

emit_err() { printf '{"error":%s}\n' "$(printf '%s' "$1" | jq -Rs .)"; }

# Find the whisper binary. The Arch package has renamed this more than once,
# so probe rather than hardcode one name and fail confusingly.
WHISPER=""
for c in whisper-cli whisper-cpp whisper main; do
    command -v "$c" >/dev/null 2>&1 && { WHISPER="$c"; break; }
done
[ -n "$WHISPER" ] || { emit_err "no whisper binary found — install whisper-cpp"; exit 1; }
[ -f "$MODEL" ]   || { emit_err "no model at $MODEL"; exit 1; }
[ -n "$TARGET" ]  || { emit_err "no --target given"; exit 2; }

WORK="${XDG_RUNTIME_DIR:-/tmp}/quickshell-captions.$$"
mkdir -p "$WORK"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

# English is special: whisper translates to it ITSELF, with no network and no
# second pass. Any other target needs the text sent to a translator.
WHISPER_TR=""
[ "$TRANSLATE_TO" = "English" ] && WHISPER_TR="--translate"

while :; do
    WAV="$WORK/chunk.wav"
    timeout "$CHUNK" pw-record --target "$TARGET" \
        --rate 16000 --channels 1 --format s16 "$WAV" >/dev/null 2>&1
    [ -s "$WAV" ] || continue

    # Skip silence before paying for inference: whisper will happily hallucinate
    # a sentence out of room tone, and on a quiet VRChat lobby that means a
    # steady trickle of invented captions.
    PEAK=$(ffmpeg -hide_banner -nostats -i "$WAV" -af volumedetect -f null - 2>&1 \
           | sed -n 's/.*max_volume: \(-\?[0-9.]*\) dB.*/\1/p')
    case "$PEAK" in ''|*[!0-9.-]*) PEAK=-99 ;; esac
    awk -v p="$PEAK" 'BEGIN{exit !(p < -45)}' && continue

    TEXT=$("$WHISPER" -m "$MODEL" -f "$WAV" -l "$LANG_IN" $WHISPER_TR \
             --no-timestamps --no-prints 2>/dev/null \
           | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # whisper marks non-speech with bracketed tags; they are not captions.
    TEXT=$(printf '%s' "$TEXT" | sed 's/\[[^]]*\]//g; s/([^)]*)//g' \
           | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$TEXT" ] || continue

    TRANS=""
    if [ -n "$TRANSLATE_TO" ] && [ "$TRANSLATE_TO" != "English" ] && [ -x "$COPILOT" ]; then
        TRANS=$("$COPILOT" translate "$TRANSLATE_TO" "$TEXT" 2>/dev/null | tr '\n' ' ')
    fi

    jq -nc --arg t "$TEXT" --arg tr "$TRANS" --argjson ts "$(date +%s)" \
        '{t:$ts, text:$t, translation:$tr}'
done
