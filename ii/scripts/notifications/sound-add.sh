#!/usr/bin/env bash
# Add a notification sound from a URL (or a local file) to the shell's library.
#
#   sound-add.sh <url|file> [name]   fetch, validate, store; prints the path
#   sound-add.sh --list              one "name<TAB>path" per line
#   sound-add.sh --remove <name>
#   sound-add.sh --play <name|path>  preview it
#
# Downloads are validated with ffprobe before being kept: a 404 HTML page
# saved as notification.ogg is silent at the point of use, which is the worst
# place to find out.
set -euo pipefail

DIR="${II_SOUND_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/notification-sounds}"
MAX_BYTES=${II_SOUND_MAX:-10485760}   # 10 MB; a notification blip is ~20 KB

die() { echo "sound-add: $*" >&2; exit 1; }
usage() { sed -n '2,9p' "$0" | sed 's/^# \?//'; exit "${1:-0}"; }
mkdir -p "$DIR"

play() {   # $1 = name or path
    local p=$1
    [ -f "$p" ] || p="$DIR/$1"
    [ -f "$p" ] || { p=$(find "$DIR" -maxdepth 1 -name "$1.*" -print -quit 2>/dev/null); }
    [ -n "$p" ] && [ -f "$p" ] || die "no such sound: $1"
    pw-play "$p" 2>/dev/null || paplay "$p" 2>/dev/null || die "could not play $p"
}

case "${1:-}" in
    --help|-h|"") usage ;;
    --list)
        find "$DIR" -maxdepth 1 -type f 2>/dev/null | sort | while read -r f; do
            n=$(basename "$f"); printf '%s\t%s\n' "${n%.*}" "$f"
        done
        exit 0 ;;
    --remove)
        [ $# -eq 2 ] || die "--remove needs a name"
        f=$(find "$DIR" -maxdepth 1 -name "$2.*" -print -quit)
        [ -n "$f" ] || die "no such sound: $2"
        rm -f -- "$f"; echo "removed: $2"; exit 0 ;;
    --play)
        [ $# -eq 2 ] || die "--play needs a name or path"
        play "$2"; exit 0 ;;
esac

SRC=$1
NAME=${2:-}

tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT

if [ -f "$SRC" ]; then
    cp -- "$SRC" "$tmp"
    [ -n "$NAME" ] || { NAME=$(basename "$SRC"); NAME=${NAME%.*}; }
else
    case "$SRC" in
        http://*|https://*) ;;
        *) die "not a URL or an existing file: $SRC" ;;
    esac
    curl -fsSL --max-time 60 --max-filesize "$MAX_BYTES" -o "$tmp" "$SRC" \
        || die "download failed (or larger than $MAX_BYTES bytes): $SRC"
    if [ -z "$NAME" ]; then
        NAME=$(basename "${SRC%%\?*}"); NAME=${NAME%.*}
    fi
fi

[ -s "$tmp" ] || die "empty download"

# Validate: a saved error page has no audio stream.
command -v ffprobe >/dev/null || die "ffprobe is required to validate audio"
codec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name \
        -of default=nw=1:nk=1 "$tmp" 2>/dev/null || true)
[ -n "$codec" ] || die "no audio stream in that file — a download that is not a sound"

dur=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$tmp" 2>/dev/null || echo 0)
awk -v d="$dur" 'BEGIN{ exit !(d+0 > 0 && d+0 <= 30) }' \
    || die "duration ${dur}s is not a notification sound (want 0-30s)"

# Keep the container we were given; canberra is not involved for file sounds.
ext=$(ffprobe -v error -show_entries format=format_name -of default=nw=1:nk=1 "$tmp" 2>/dev/null)
case "$ext" in
    *ogg*) ext=ogg ;; *wav*) ext=wav ;; *mp3*|*mp2*) ext=mp3 ;;
    *flac*) ext=flac ;; *) ext=ogg ;;
esac

NAME=$(printf '%s' "$NAME" | tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//')
[ -n "$NAME" ] || NAME="sound-$(date +%s)"
dest="$DIR/$NAME.$ext"
/usr/bin/mv "$tmp" "$dest"; trap - EXIT
chmod 644 "$dest"

printf 'added: %s\n%s\n' "$NAME" "$dest"
printf 'codec=%s duration=%ss\n' "$codec" "$dur"
