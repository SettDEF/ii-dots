#!/usr/bin/env bash
# Copilot backend — voice transcription, translation, screen/image vision, OCR.
# Cloud via OpenAI or Gemini, whichever key is available (keys come from the
# same gnome-keyring the AI chat uses, falling back to ~/.secure/apikeys / env).
#
#   copilot.sh record-start              begin mic recording (backgrounded)
#   copilot.sh record-stop               stop; prints the WAV path
#   copilot.sh recording?                prints "yes"/"no"
#   copilot.sh transcribe [file] [lang]  audio -> text (default file = last rec)
#   copilot.sh translate <target> [txt]  text (arg or stdin) -> translation
#   copilot.sh voice-translate <target>  last recording -> {transcript, translation} JSON
#   copilot.sh dictate [lang]            last recording -> transcript -> type into focused app
#   copilot.sh vision [prompt]           pick a screen region -> vision-model answer
#   copilot.sh ocr                       pick a screen region -> text -> clipboard
set -uo pipefail

STATE="${XDG_RUNTIME_DIR:-/tmp}/quickshell-copilot"; mkdir -p "$STATE"
WAV="$STATE/rec.wav"; PIDF="$STATE/rec.pid"
GEMINI_MODEL="${COPILOT_GEMINI_MODEL:-gemini-2.5-flash}"
OPENAI_CHAT_MODEL="${COPILOT_OPENAI_CHAT_MODEL:-gpt-4o-mini}"
OPENAI_STT_MODEL="${COPILOT_OPENAI_STT_MODEL:-whisper-1}"

die() { echo "copilot: $*" >&2; exit 1; }

# --- keys: env > flat file > gnome-keyring (the AI chat's store) -----------
load_keys() {
    set -a; . "$HOME/.secure/apikeys" 2>/dev/null; set +a
    if [ -z "${OPENAI_API_KEY:-}" ] || [ -z "${GEMINI_API_KEY:-}" ]; then
        local blob; blob=$(secret-tool lookup application illogical-impulse 2>/dev/null)
        if [ -n "$blob" ]; then
            [ -z "${OPENAI_API_KEY:-}" ]    && OPENAI_API_KEY=$(printf '%s' "$blob"    | jq -r '(.apiKeys.openai    // .openai    // empty)' 2>/dev/null)
            [ -z "${GEMINI_API_KEY:-}" ]    && GEMINI_API_KEY=$(printf '%s' "$blob"    | jq -r '(.apiKeys.gemini    // .gemini    // empty)' 2>/dev/null)
            export OPENAI_API_KEY GEMINI_API_KEY
        fi
    fi
}
provider() {
    [ -n "${COPILOT_PROVIDER:-}" ] && { echo "$COPILOT_PROVIDER"; return; }
    [ -n "${OPENAI_API_KEY:-}" ] && { echo openai; return; }
    [ -n "${GEMINI_API_KEY:-}" ] && { echo gemini; return; }
    echo none
}

# --- recording ------------------------------------------------------------
record_start() { record_stop >/dev/null 2>&1 || true; parecord --file-format=wav "$WAV" >/dev/null 2>&1 & echo $! > "$PIDF"; }
record_stop()  { [ -r "$PIDF" ] || { [ -f "$WAV" ] && echo "$WAV"; return 0; }; kill "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null; rm -f "$PIDF"; sleep 0.2; [ -f "$WAV" ] && echo "$WAV"; }
recording_q()  { [ -r "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null && echo yes || echo no; }

# --- transcription --------------------------------------------------------
transcribe() {
    local file="${1:-$WAV}" lang="${2:-}"; [ -f "$file" ] || die "no audio file: $file"
    load_keys
    case "$(provider)" in
        openai)
            local a=(-F file=@"$file" -F model="$OPENAI_STT_MODEL" -F response_format=json); [ -n "$lang" ] && a+=(-F language="$lang")
            curl -fsS https://api.openai.com/v1/audio/transcriptions -H "Authorization: Bearer $OPENAI_API_KEY" "${a[@]}" | jq -r '.text // empty' ;;
        gemini)
            local b64; b64=$(base64 -w0 "$file")
            local p; p=$(jq -n --arg d "$b64" '{contents:[{parts:[{text:"Transcribe this audio verbatim. Output only the transcript."},{inline_data:{mime_type:"audio/wav",data:$d}}]}]}')
            curl -fsS "https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}" \
                -H "Content-Type: application/json" -d "$p" | jq -r '.candidates[0].content.parts[0].text // empty' ;;
        *) die "no OPENAI/GEMINI key found (checked env, ~/.secure/apikeys, keyring)";;
    esac
}

# --- text/vision chat -----------------------------------------------------
# $1 system, $2 user; optional image path in $COPILOT_IMG
chat() {
    local sys="$1" user="$2"; load_keys
    case "$(provider)" in
        openai)
            local payload
            if [ -n "${COPILOT_IMG:-}" ] && [ -f "${COPILOT_IMG:-}" ]; then
                local b; b=$(base64 -w0 "$COPILOT_IMG")
                payload=$(jq -n --arg m "$OPENAI_CHAT_MODEL" --arg s "$sys" --arg u "$user" --arg i "data:image/png;base64,$b" \
                    '{model:$m,messages:[{role:"system",content:$s},{role:"user",content:[{type:"text",text:$u},{type:"image_url",image_url:{url:$i}}]}]}')
            else
                payload=$(jq -n --arg m "$OPENAI_CHAT_MODEL" --arg s "$sys" --arg u "$user" \
                    '{model:$m,messages:[{role:"system",content:$s},{role:"user",content:$u}]}')
            fi
            curl -fsS https://api.openai.com/v1/chat/completions -H "Authorization: Bearer $OPENAI_API_KEY" -H "Content-Type: application/json" -d "$payload" \
                | jq -r '.choices[0].message.content // empty' ;;
        gemini)
            local payload
            if [ -n "${COPILOT_IMG:-}" ] && [ -f "${COPILOT_IMG:-}" ]; then
                local b; b=$(base64 -w0 "$COPILOT_IMG")
                payload=$(jq -n --arg s "$sys" --arg u "$user" --arg d "$b" \
                    '{systemInstruction:{parts:[{text:$s}]},contents:[{parts:[{text:$u},{inline_data:{mime_type:"image/png",data:$d}}]}]}')
            else
                payload=$(jq -n --arg s "$sys" --arg u "$user" '{systemInstruction:{parts:[{text:$s}]},contents:[{parts:[{text:$u}]}]}')
            fi
            curl -fsS "https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}" \
                -H "Content-Type: application/json" -d "$payload" | jq -r '.candidates[0].content.parts[0].text // empty' ;;
        *) die "no OPENAI/GEMINI key found";;
    esac
}

translate() { local t="$1"; shift; local x="$*"; [ -n "$x" ] || x="$(cat)"; [ -n "$x" ] || die "nothing to translate"; chat "You are a translator. Translate the user's text into ${t}. Output ONLY the translation." "$x"; }

# --- screen helpers -------------------------------------------------------
grab_region() { local g; g=$(slurp 2>/dev/null) || return 1; [ -n "$g" ] || return 1; grim -g "$g" "$STATE/grab.png" >/dev/null 2>&1 && echo "$STATE/grab.png"; }
vision() { local pr="${*:-Describe this image. If it has text, transcribe and translate it to English.}"; local i; i=$(grab_region) || die "cancelled"; COPILOT_IMG="$i" chat "You are a concise visual assistant." "$pr"; }
ocr()    { local i; i=$(grab_region) || die "cancelled"; local t; t=$(tesseract "$i" - 2>/dev/null); [ -n "$t" ] && printf '%s' "$t" | wl-copy 2>/dev/null; printf '%s' "$t"; }
dictate(){ local t; t=$(transcribe "$WAV" "${1:-}"); [ -n "$t" ] || die "no transcript"; wtype "$t" 2>/dev/null || ydotool type "$t" 2>/dev/null; printf '%s' "$t"; }
voice_translate() { local t="$1" l="${2:-}"; local s; s=$(transcribe "$WAV" "$l"); [ -n "$s" ] || die "no transcript"; local o; o=$(translate "$t" "$s"); jq -n --arg s "$s" --arg t "$o" '{transcript:$s,translation:$t}'; }

cmd="${1:-}"; shift || true
case "$cmd" in
    record-start) record_start ;;
    record-stop)  record_stop ;;
    "recording?") recording_q ;;
    transcribe)   transcribe "$@" ;;
    translate)    translate "$@" ;;
    voice-translate) voice_translate "$@" ;;
    dictate)      dictate "$@" ;;
    vision)       vision "$@" ;;
    ocr)          ocr ;;
    provider)     load_keys; provider ;;
    *) die "usage: {record-start|record-stop|recording?|transcribe|translate|voice-translate|dictate|vision|ocr|provider}" ;;
esac
