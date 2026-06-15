#!/usr/bin/env bash

# Generate thumbnails for files using ImageMagick, following Freedesktop spec
# Usage:
#   ./generate-thumbnails-magick.sh --file <path>
#   ./generate-thumbnails-magick.sh --directory <path>
#
# Resilient mode: a single corrupted file (e.g. an HTML error page saved with
# a .jpg extension by a downloader) must NOT abort thumbnailing the rest of
# the folder, so `set -e` is intentionally off.
set -u

# Thumbnail sizes mapping
get_thumbnail_size() {
    case "$1" in
        normal) echo 128 ;;
        large) echo 256 ;;
        x-large) echo 512 ;;
        xx-large) echo 1024 ;;
        *) echo 128 ;;
    esac
}

usage() {
    echo "Usage: $0 --file <path> | --directory <path>"
    exit 1
}

md5() {
    # Calculate md5 hash of the file's absolute path
    echo -n "$1" | md5sum | awk '{print $1}'
}

urlencode() {
    # Percent-encode a string for use in a URI, but do not encode slashes
    local str="$1"
    local encoded=""
    local c
    for ((i=0; i<${#str}; i++)); do
        c="${str:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]|/) encoded+="$c" ;;
            *) printf -v hex '%%%02X' "'${c}'"; encoded+="$hex" ;;
        esac
    done
    echo "$encoded"
}

generate_thumbnail() {
    local src="$1"
    local abs_path
    abs_path="$(realpath "$src")"
    # Animated → ffmpegthumbnailer (single bounded ffmpeg call, far lighter
    # than magick which spawns a per-frame 37-thread ffmpeg pipeline).
    local is_animated=0
    case "${abs_path,,}" in
        *.gif|*.mp4|*.webm|*.m4v|*.mkv|*.avi|*.mov|*.flv|*.ts|*.mts) is_animated=1 ;;
    esac
    local encoded_path
    encoded_path="$(urlencode "$abs_path")"
    local uri
    uri="file://$encoded_path"
    local hash
    hash="$(md5 "$uri")"
    local out="$CACHE_DIR/$hash.png"
    mkdir -p "$CACHE_DIR"
    if [ -f "$out" ]; then
        return
    fi
    # Sniff first bytes — auto-delete obviously-non-image files (HTML
    # error pages, JSON responses) that downloaders sometimes save with
    # an image extension. They cause magick to fail every run.
    local head
    head="$(head -c 16 "$abs_path" 2>/dev/null | LC_ALL=C tr -d "\n\r" | head -c 16)"
    case "$head" in
        \<*|"{"*|"["*)
            echo "skipping non-image (auto-removing): $abs_path" >&2
            rm -f -- "$abs_path"
            return
            ;;
    esac
    if [ "$is_animated" -eq 1 ] && command -v ffmpegthumbnailer >/dev/null; then
        # ffmpegthumbnailer is single-threaded, ~30 MB peak. Quality 8/10 is
        # plenty for a tile thumb. Falls back to magick only if it fails.
        ffmpegthumbnailer -i "$abs_path" -o "$out" -s "$THUMBNAIL_SIZE" -q 8 -t 1 2>/dev/null && return
    elif command -v vipsthumbnail >/dev/null; then
        # vipsthumbnail: low RAM, no thread fanout, ~same speed as magick
        # on static JPEG/PNG. -s NxN keeps aspect to fit inside the box.
        vipsthumbnail "$abs_path" -s "${THUMBNAIL_SIZE}x${THUMBNAIL_SIZE}" -o "$out" 2>/dev/null && return
    fi
    # Last-resort fallback: magick with the env caps from the dir mode.
    magick "$abs_path" -resize "${THUMBNAIL_SIZE}x${THUMBNAIL_SIZE}" "$out" 2>/dev/null || {
        echo "thumbnail failed for: $abs_path" >&2
        return
    }
}

# Parse arguments
SIZE_NAME="normal"
MODE=""
TARGET=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --file|-f)
            MODE="file"
            TARGET="$2"
            shift 2
            ;;
        --directory|-d)
            MODE="dir"
            TARGET="$2"
            shift 2
            ;;
        --size|-s)
            SIZE_NAME="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
    # Only one mode allowed
    [[ -n "$MODE" ]] && break
done

THUMBNAIL_SIZE="$(get_thumbnail_size "$SIZE_NAME")"
CACHE_DIR="$HOME/.cache/thumbnails/$SIZE_NAME"

if [ -z "$MODE" ] || [ -z "$TARGET" ]; then
    usage
fi

case "$MODE" in
    file)
        if [ ! -f "$TARGET" ]; then
            echo "File not found: $TARGET"
            exit 2
        fi
        generate_thumbnail "$TARGET"
        ;;
    dir)
        if [ ! -d "$TARGET" ]; then
            echo "Directory not found: $TARGET"
            exit 2
        fi
        # Lock per (directory,size) so multiple Quickshell reloads can't
        # double-fire concurrent batches. Without this, opening the picker
        # after 4 reloads spawns 4 × N concurrent magick processes — and
        # magick on a single 4K JPEG can briefly use 200 MB.
        LOCKDIR="$HOME/.cache/quickshell/thumbgen-locks"
        mkdir -p "$LOCKDIR"
        LOCK_HASH="$(printf '%s|%s' "$TARGET" "$SIZE_NAME" | md5sum | cut -d' ' -f1)"
        LOCKFILE="$LOCKDIR/$LOCK_HASH.lock"
        exec 9>"$LOCKFILE"
        if ! flock -n 9; then
            # Another instance is already processing this folder/size — bail.
            exit 0
        fi
        export -f generate_thumbnail urlencode md5
        export CACHE_DIR THUMBNAIL_SIZE
        # Hard caps — magick by default spawns one thread per CPU core
        # AND keeps the entire source image in memory uncompressed (~4 K
        # JPEG = 50 MB, animated GIF/MP4 frame = much worse). With xargs
        # -P 2 below, peak load is bounded at ≤2 magicks × 1 thread × 256 MB.
        export MAGICK_THREAD_LIMIT=1
        export MAGICK_MEMORY_LIMIT=256MiB
        export MAGICK_MAP_LIMIT=512MiB
        export MAGICK_DISK_LIMIT=1GiB
        # OMP threads for the underlying lib (also used by some helpers).
        export OMP_NUM_THREADS=1
        # Two workers in parallel is enough for a snappy UI without
        # registering on `top`. Files appear left-to-right as they
        # finish, which is how the user perceives "instant" anyway.
        find "$TARGET" -maxdepth 1 -type f -print0 \
            | xargs -0 -n1 -P 2 \
                bash -c 'generate_thumbnail "$0"'
        ;;
    *)
        usage
        ;;
esac

