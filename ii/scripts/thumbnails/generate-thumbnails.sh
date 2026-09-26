#!/usr/bin/env bash
# Freedesktop-spec thumbnails with tinct (videos and GIFs via ffmpegthumbnailer).
# Usage: generate-thumbnails.sh [--size normal|large|x-large|xx-large] [--machine_progress] (-d DIR | -f FILE)
# --machine_progress prints "PROGRESS n/total FILE path" per finished file.
set -u

size_name=normal
progress=0
mode=""
target=""
while [ $# -gt 0 ]; do
    case "$1" in
        --size|-s) size_name="$2"; shift 2 ;;
        --machine_progress) progress=1; shift ;;
        --directory|-d) mode=dir; target="$2"; shift 2 ;;
        --file|-f) mode=file; target="$2"; shift 2 ;;
        *) echo "usage: $0 [--size NAME] [--machine_progress] (-d DIR | -f FILE)" >&2; exit 1 ;;
    esac
done
[ -n "$mode" ] && [ -e "$target" ] || { echo "not found: $target" >&2; exit 2; }

case "$size_name" in
    large) px=256 ;;
    x-large) px=512 ;;
    xx-large) px=1024 ;;
    *) size_name=normal; px=128 ;;
esac
export CACHE="$HOME/.cache/thumbnails/$size_name"
mkdir -p "$CACHE"
tinct="$HOME/.local/bin/tinct"
target="$(realpath "$target")"

# One run per folder and size: reloads used to stack several on top of each other.
if [ "$mode" = dir ]; then
    lockdir="$HOME/.cache/quickshell/thumbgen-locks"
    mkdir -p "$lockdir"
    exec 9>"$lockdir/$(printf '%s|%s' "$target" "$size_name" | md5sum | cut -d' ' -f1).lock"
    flock -n 9 || exit 0
fi

# "SRC<TAB>DST" for every file without a thumbnail. The name is the md5 of the
# file:// URI as ThumbnailImage builds it: Qt.resolvedUrl escapes `%` first, then
# encodeURIComponent runs over the result.
jobs="$(
    if [ "$mode" = dir ]; then find "$target" -maxdepth 1 -type f; else printf '%s\n' "$target"; fi |
    perl -MDigest::MD5=md5_hex -ne '
        chomp; next unless length;
        my $enc = join "/", map { my $s = $_; $s =~ s/%/%25/g; $s =~ s/([^A-Za-z0-9\-_.!~*\x27()])/sprintf("%%%02X", ord $1)/ge; $s } split m{/}, $_, -1;
        my $out = "$ENV{CACHE}/" . md5_hex("file://$enc") . ".png";
        print "$_\t$out\n" unless -e $out;
    '
)"
[ -z "$jobs" ] && exit 0
total=$(printf '%s\n' "$jobs" | wc -l)

report() {
    if [ "$progress" = 1 ]; then
        awk -F'\t' -v total="$total" '$1 == "ok" || $1 == "fail" { n++; print "PROGRESS " n "/" total " FILE " $2; fflush() }'
    else
        cat >/dev/null
    fi
}

animated='\.(gif|mp4|webm|m4v|mkv|avi|mov|flv|ts|mts)'$'\t'
{
    printf '%s\n' "$jobs" | grep -viE "$animated" | "$tinct" image thumb --batch --size "$px" --jobs 4
    printf '%s\n' "$jobs" | grep -iE "$animated" | while IFS=$'\t' read -r src dst; do
        if command -v ffmpegthumbnailer >/dev/null && ffmpegthumbnailer -i "$src" -o "$dst" -s "$px" -q 8 -t 1 2>/dev/null; then
            printf 'ok\t%s\t%s\n' "$src" "$dst"
        else
            printf 'fail\t%s\n' "$src"
        fi
    done
} | report
