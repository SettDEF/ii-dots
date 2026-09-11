#!/usr/bin/env bash
# Reddit fetcher — OAuth API client. Replaces gallery-dl.
#
# Why OAuth: Reddit blocks the unauthenticated .json endpoint with 403
# for every browser-shaped UA now (2025+). The OAuth API (oauth.reddit.com)
# is the only reliable public path. It also gets 600 req/min instead of
# 60, so we can paginate aggressively for "infinite scroll" feel.
#
# Setup: run reddit_oauth_setup.sh once before this script will work.
#
# Usage:
#   fetch_reddit.sh <sub> <sort> <after> <dest>
#
# Args:
#   sub    — subreddit name
#   sort   — "hot" | "top?t=all" | "top?t=year" | "new" | "rising" | ...
#   after  — pagination cursor ("" for first page)
#   dest   — destination root; files go to $dest/reddit/<sub>/
#
# Output (stdout):
#   First line: "AFTER=<token>" — empty if sort is exhausted
#   Subsequent lines: paths of files newly written
#
# Exit codes:
#   0  — success
#   2  — bad args
#   3  — network / parse fail
#   4  — sub doesn't exist / private / banned
#   5  — auth failure (need to re-run reddit_oauth_setup.sh)

set -u

[ $# -lt 4 ] && { echo "Usage: $0 <sub> <sort> <after> <dest>" >&2; exit 2; }
SUB=$1
SORT=$2
AFTER=$3
DEST=$4

# Shared OAuth token + request helpers.
# shellcheck source=reddit_lib.sh
. "$(dirname "$0")/reddit_lib.sh"
reddit_load_env || exit 5

# ── Validate sub name ───────────────────────────────────────────────
SUB=$(printf '%s' "$SUB" | tr -d '\r\n' | tr -cd 'A-Za-z0-9_+')
[ -z "$SUB" ] && { echo "empty sub" >&2; exit 2; }

OUT_DIR="$DEST/reddit/$SUB"
mkdir -p "$OUT_DIR"

# ── Build URL ───────────────────────────────────────────────────────
# oauth.reddit.com mirrors the same listing paths. limit=100 is max.
# raw_json=1 disables HTML entity escaping in URLs (so &amp; → &).
URL="https://oauth.reddit.com/r/${SUB}/${SORT}"
SEP="?"
case "$URL" in *"?"*) SEP="&" ;; esac
URL="${URL}${SEP}limit=100&raw_json=1"
[ -n "$AFTER" ] && URL="${URL}&after=${AFTER}"

TOKEN=$(reddit_get_token) || exit 5

JSON=$(reddit_api "$TOKEN" "$URL")

if ! printf '%s' "$JSON" | jq -e '.data.children' >/dev/null 2>&1; then
    # Token might have just expired — invalidate cache, try once more.
    rm -f "$REDDIT_TOKEN_CACHE"
    TOKEN=$(reddit_get_token) || exit 5
    JSON=$(reddit_api "$TOKEN" "$URL")
    if ! printf '%s' "$JSON" | jq -e '.data.children' >/dev/null 2>&1; then
        err=$(printf '%s' "$JSON" | jq -r '.message // .error // empty' 2>/dev/null)
        [ -n "$err" ] && echo "reddit: $err" >&2
        echo "AFTER="
        exit 4
    fi
fi

NEXT_AFTER=$(printf '%s' "$JSON" | jq -r '.data.after // empty')
echo "AFTER=${NEXT_AFTER}"

# ── Extract image URLs ──────────────────────────────────────────────
# Reddit post shapes we care about:
#   1. Direct image: t3.url ends in .jpg/.png/.gif/.webp + host is
#      i.redd.it / i.imgur.com
#   2. Gallery: t3.is_gallery=true, URLs in t3.media_metadata[K]
#   3. Crosspost: t3.crosspost_parent_list[0] is the real post, recurse
#   4. Anything else: skipped (videos / external links handled elsewhere)
#
# Resolution policy — the whole point of this pass:
#   We DON'T download the raw original (p.url on i.redd.it). Those are
#   frequently 5-9 MB PNGs and time out constantly. Reddit already hosts a
#   re-encoded JPEG preview ladder (preview.images[0].resolutions[] plus a
#   full-size .source). We pick the SMALLEST preview whose width is at least
#   TARGET_W — enough pixels to fill the screen at native quality — and fall
#   back to the largest available (usually .source) when nothing reaches it.
#   Result: ~screen-res JPEGs that are a fraction of the bytes, so the
#   carousel fills fast instead of stalling on multi-MB originals. GIFs keep
#   their original url (previews would kill the animation).
TARGET_W=${SKWD_TARGET_W:-2560}
# DASH rung to prefer for v.redd.it video.
#
# 480, not the 1080 that fallback_url advertises. A card cannot appear until
# its file is fully on disk, so the download size IS the time-to-listed — and
# 1080 is roughly 6x the bytes of 480 for a thumbnail-sized carousel card.
# Raise it (SKWD_VIDEO_H=720 or 1080) if you care more about the quality of
# the one you eventually set as wallpaper than about how fast the list fills.
VIDEO_H=${SKWD_VIDEO_H:-480}
TASKS=$(printf '%s' "$JSON" | jq -r --argjson tw "$TARGET_W" --argjson vh "$VIDEO_H" '
    def is_gif(u): (u | test("\\.gif(?:\\?|$)"; "i"));
    def is_image_url(u):
        (u | test("\\.(?:jpe?g|png|webp|gif|bmp)(?:\\?|$)"; "i"));
    def is_video_url(u):
        (u | test("\\.(?:mp4|webm|m4v|mov)(?:\\?|$)"; "i"));

    # v.redd.it serves a DASH ladder (…/DASH_96|220|360|480|720|1080.mp4) and
    # fallback_url usually points at the TOP rung. For a browsing carousel that
    # is several times the bytes for no visible gain, and it was the difference
    # between a video arriving and timing out. Step it down to $vh; the caller
    # keeps the original as a fallback in case that rung does not exist.
    def prefer_rung(u; vh):
        if (u | test("/DASH_[0-9]+\\.mp4"; "i"))
        then (u | sub("/DASH_[0-9]+\\.mp4"; "/DASH_" + (vh|tostring) + ".mp4"; "i"))
        else u end;

    # Reddit hosts video in a few places depending on how the post was made.
    # Taking the first that exists, most-specific first. fallback_url is the
    # muxed-video-only MP4 (audio is a separate track); for wallpaper use that
    # is exactly what we want.
    def video_url(p):
        ( p.secure_media.reddit_video.fallback_url
        // p.media.reddit_video.fallback_url
        // p.preview.reddit_video_preview.fallback_url
        // (if is_video_url(p.url // "") then p.url else null end)
        # imgur .gifv is an MP4 wearing a costume.
        // (if ((p.url // "") | test("\\.gifv(?:\\?|$)"; "i"))
           then ((p.url) | sub("\\.gifv"; ".mp4"; "i")) else null end)
        ) as $u
        # MUST yield null, never `empty`, for a post with no video: this is
        # used as an elif CONDITION, and an empty condition makes the whole
        # if/elif chain produce nothing -- which silently dropped every plain
        # image post rather than just failing the video test.
        | if $u == null then null else ($u | gsub("&amp;"; "&")) end;

    # From a candidate list [{url,width}], pick the smallest that meets the
    # target width; if none do, take the widest we have.
    def pick(cands; tw):
        (cands | map(select(.url != null and .width != null))) as $c
        | if ($c | length) == 0 then empty
          else
            ( [ $c[] | select(.width >= tw) ] | sort_by(.width) | first )
            // ( $c | sort_by(.width) | last )
            | .url | gsub("&amp;"; "&")
          end;

    # Preview ladder for a normal post → resolutions[] + source.
    def preview_pick(p; tw):
        (p.preview.images[0]) as $img
        | if $img == null then empty
          else pick( [ ($img.resolutions // [])[], $img.source ]; tw )
          end;

    # Emits {url, kind}. kind drives the download budget below — videos are
    # an order of magnitude bigger than a capped JPEG preview and need their
    # own ceiling rather than sharing the image one.
    def post_to_url(p; tw):
        if (p.crosspost_parent_list // [] | length) > 0 then
            post_to_url(p.crosspost_parent_list[0]; tw)
        elif ((p.is_gallery // false) or (p.media_metadata != null)) then
            # Gallery item: each media_metadata entry has a .p[] preview
            # ladder and a .s source. Same capped pick per image. (Some
            # galleries arrive with is_gallery unset but media_metadata
            # present, so key off either.)
            ((p.media_metadata // {}) | to_entries[]
                | select(.value.status == "valid")
                | .value as $m
                | { url: pick( [ ($m.p // [])[], ($m.s // {}) ]; tw ), kind: "img" })
        elif is_gif(p.url // "") then
            { url: p.url, kind: "img" }
        elif ((video_url(p)) != null) then
            # Checked BEFORE the image branch: a hosted video carries a
            # preview ladder too, so testing images first would silently
            # download the thumbnail and call the post handled. This branch
            # not existing at all is why the Videos tab could never grow --
            # every v.redd.it post fell through to `empty`.
            (video_url(p)) as $v
            | { url: prefer_rung($v; $vh), alt: $v, kind: "vid" }
        elif (is_image_url(p.url // "") or (p.post_hint // "") == "image") then
            # An actual image post: prefer the capped preview, fall back to
            # the raw original only when there is no preview ladder. Gating
            # on is_image_url / post_hint keeps self & text posts (which also
            # carry a preview) out of the results.
            { url: ((preview_pick(p; tw)) // (p.url)), kind: "img" }
        else
            empty
        end;

    .data.children[]
    | .data as $p
    | (post_to_url($p; $tw)) as $m
    | select($m != null and $m.url != null and $m.url != "")
    # Titles arrive containing real newlines and tabs. Those split one record
    # into several and shift every field left, which is where the
    # "Could not resolve host: img" failures came from -- title text landing
    # in the url slot. Flatten them here, before the record is ever formed.
    | ($p.title // "untitled" | gsub("[\\n\\r\\t]"; " ")) as $t
    | "\($m.url)\t\($m.alt // "")\t\($m.kind)\t\($p.id)\t\($t)"
' 2>/dev/null)

[ -z "$TASKS" ] && exit 0

# ── Download with parallelism ───────────────────────────────────────
# Filename pattern matches gallery-dl's convention so existing
# redditScanProc / filename → id parsing keeps working. The FINAL
# extension is decided from the downloaded bytes, not the URL: preview
# URLs end in ".png?format=pjpg" while serving JPEG, so trusting the
# path would misname (and then mis-validate) every preview.
export OUT_DIR REDDIT_UA
printf '%s\n' "$TASKS" \
  | while IFS=$'\t' read -r url alt kind id title; do
        [ -z "$url" ] && continue
        safe_title=$(printf '%s' "$title" \
            | tr -d '\r\n' \
            | tr -cd 'A-Za-z0-9 _.,!?()-' \
            | cut -c1-80 \
            | sed 's/[[:space:]]*$//')
        # Skip if ANY extension of this id is already on disk.
        if ls "$OUT_DIR/${id} "* >/dev/null 2>&1; then continue; fi
        # NUL-terminated, to be read by `xargs -0`. Newline records made xargs
        # apply its own quote parsing, and a single apostrophe anywhere in the
        # record aborted the WHOLE batch with "unmatched single quote" --
        # losing every remaining download in that wave, not just one.
        printf '%s\t%s\t%s\t%s\t%s\0' "$url" "$alt" "$kind" "$id" "$safe_title"
    done \
  | xargs -0 -P 12 -I{} bash -c '
        line="{}"
        url="${line%%	*}"
        rest="${line#*	}"
        alt="${rest%%	*}"
        rest="${rest#*	}"
        kind="${rest%%	*}"
        rest="${rest#*	}"
        id="${rest%%	*}"
        title="${rest#*	}"
        # Budget by kind. Previews are ~screen-res JPEGs where 20s is plenty;
        # a video is 10-50x that and was guaranteed to lose a 20s race.
        # --max-filesize refuses the giants outright instead of spending the
        # whole window on one file and getting killed mid-write -- the 58 MB
        # posts are what filled the sync log with timeouts and SIGPIPEs.
        if [ "$kind" = "vid" ]; then
            max_time=90; max_bytes=$((60*1024*1024))
        else
            max_time=20; max_bytes=$((20*1024*1024))
        fi
        tmp="$OUT_DIR/.${id}.part"
        fetch() {
            curl --silent --show-error --location --max-time "$max_time" --fail \
                 --remove-on-error --max-filesize "$max_bytes" \
                 -A "$REDDIT_UA" -o "$tmp" "$1"
        }
        # The preferred DASH rung may not exist for every post, so fall back to
        # the url reddit actually advertised rather than losing the video.
        if ! fetch "$url"; then
            if [ -n "$alt" ] && [ "$alt" != "$url" ] && fetch "$alt"; then
                :
            else
                rm -f "$tmp"
                exit 0
            fi
        fi
        # Reject tiny responses (HTML error pages, captchas, empties).
        size=$(stat -c%s "$tmp" 2>/dev/null || echo 0)
        if [ "$size" -lt 4096 ]; then
            rm -f "$tmp"
            exit 0
        fi
        # Decide format + integrity from the actual bytes. Magic at the
        # head, structural end-marker at the tail (catches the silent
        # mid-stream truncation curl reports as success).
        head_hex=$(head -c12 "$tmp" | od -An -tx1 | tr -d " \n")
        ext=""; ok=0
        case "$head_hex" in
            ffd8ff*)                       # JPEG
                ext=jpg
                [ "$(tail -c2 "$tmp" | od -An -tx1 | tr -d " \n")" = "ffd9" ] && ok=1 ;;
            89504e470d0a1a0a*)             # PNG
                ext=png
                [ "$(tail -c8 "$tmp" | head -c4)" = "IEND" ] && ok=1 ;;
            52494646*)                     # RIFF…  (WebP: bytes 8-11 = WEBP)
                if [ "$(dd if="$tmp" bs=1 skip=8 count=4 2>/dev/null)" = "WEBP" ]; then
                    ext=webp; ok=1
                fi ;;
            474946383*)                    # GIF87a / GIF89a
                ext=gif; ok=1 ;;
            ????????66747970*)             # ISO-BMFF: "ftyp" at byte offset 4
                # MP4/MOV. No cheap structural end-marker exists the way IEND
                # or ffd9 do, so integrity rests on curl having reported a
                # complete transfer. A truncated MP4 still decodes up to the
                # cut, which is a far better failure than discarding it.
                ext=mp4; ok=1 ;;
            1a45dfa3*)                     # EBML: WebM / Matroska
                ext=webm; ok=1 ;;
        esac
        # Without a video branch here, every downloaded video failed this
        # switch and was deleted below -- so even once a video URL was
        # extracted, nothing could ever land on disk.
        if [ "$ok" -ne 1 ] || [ -z "$ext" ]; then
            rm -f "$tmp"
            exit 0
        fi
        out="$OUT_DIR/${id} ${title}.${ext}"
        mv "$tmp" "$out" && printf "%s\n" "$out"
    '

exit 0
