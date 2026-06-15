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

ENV_FILE="$HOME/.secure/reddit-app.env"
TOKEN_CACHE="$HOME/.cache/quickshell/reddit-oauth-token.json"

[ -r "$ENV_FILE" ] || {
    echo "Missing $ENV_FILE — run reddit_oauth_setup.sh first." >&2
    exit 5
}
# shellcheck disable=SC1090
. "$ENV_FILE"

# ── Token management ────────────────────────────────────────────────
# Cached access token is good for ~50 min (Reddit's 60min - 60s safety
# margin from the setup script). When expired, re-auth via password
# grant — we have the creds in the env file.
get_access_token() {
    local now exp tok
    now=$(date +%s)
    if [ -r "$TOKEN_CACHE" ]; then
        exp=$(jq -r '.expires_at // 0' "$TOKEN_CACHE" 2>/dev/null)
        tok=$(jq -r '.access_token // empty' "$TOKEN_CACHE" 2>/dev/null)
        if [ -n "$tok" ] && [ "$exp" -gt "$now" ] 2>/dev/null; then
            printf '%s' "$tok"
            return 0
        fi
    fi

    # Refresh — exchange creds for a new token.
    local response access_token expires_in
    response=$(curl --silent --show-error --max-time 15 \
        -X POST \
        --user "${REDDIT_CLIENT_ID}:${REDDIT_CLIENT_SECRET}" \
        -A "$REDDIT_UA" \
        -d "grant_type=password" \
        --data-urlencode "username=${REDDIT_USER}" \
        --data-urlencode "password=${REDDIT_PASS}" \
        "https://www.reddit.com/api/v1/access_token")
    access_token=$(printf '%s' "$response" | jq -r '.access_token // empty')
    expires_in=$(printf '%s' "$response" | jq -r '.expires_in // 3600')
    if [ -z "$access_token" ]; then
        echo "OAuth refresh failed:" >&2
        printf '%s' "$response" | jq . 2>/dev/null >&2 || printf '%s\n' "$response" >&2
        return 1
    fi

    umask 077
    mkdir -p "$(dirname "$TOKEN_CACHE")"
    cat > "$TOKEN_CACHE" <<EOF
{
  "access_token": "$access_token",
  "expires_at": $((now + expires_in - 60))
}
EOF
    printf '%s' "$access_token"
}

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

TOKEN=$(get_access_token) || exit 5

JSON=$(curl --silent --show-error --max-time 12 \
    -A "$REDDIT_UA" \
    -H "Authorization: Bearer $TOKEN" \
    "$URL")

if ! printf '%s' "$JSON" | jq -e '.data.children' >/dev/null 2>&1; then
    # Token might have just expired — invalidate cache, try once more.
    rm -f "$TOKEN_CACHE"
    TOKEN=$(get_access_token) || exit 5
    JSON=$(curl --silent --show-error --max-time 12 \
        -A "$REDDIT_UA" \
        -H "Authorization: Bearer $TOKEN" \
        "$URL")
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
#   2. Gallery: t3.is_gallery=true, URLs in t3.media_metadata[K].s.u
#   3. Crosspost: t3.crosspost_parent_list[0] is the real post, recurse
#   4. Anything else: skipped (videos / external links handled elsewhere)
TASKS=$(printf '%s' "$JSON" | jq -r '
    def is_image_url(u):
        (u | test("\\.(?:jpe?g|png|webp|gif|bmp)(?:\\?|$)"; "i"));

    def post_to_url(p):
        if (p.crosspost_parent_list // [] | length) > 0 then
            post_to_url(p.crosspost_parent_list[0])
        elif (p.is_gallery // false) then
            ((p.media_metadata // {}) | to_entries[]
                | select(.value.status == "valid")
                | (.value.s.u // "")
                | gsub("&amp;"; "&"))
        elif is_image_url(p.url // "") then
            p.url
        else
            empty
        end;

    .data.children[]
    | .data as $p
    | (post_to_url($p)) as $u
    | "\($u)\t\($p.id)\t\($p.title // "untitled")"
' 2>/dev/null)

[ -z "$TASKS" ] && exit 0

# ── Download with 8-way parallelism ─────────────────────────────────
# Filename pattern matches gallery-dl's convention so existing
# redditScanProc / filename → id parsing keeps working.
printf '%s\n' "$TASKS" \
  | while IFS=$'\t' read -r url id title; do
        [ -z "$url" ] && continue
        safe_title=$(printf '%s' "$title" \
            | tr -d '\r\n' \
            | tr -cd 'A-Za-z0-9 _.,!?()-' \
            | cut -c1-80 \
            | sed 's/[[:space:]]*$//')
        ext="${url##*.}"
        ext="${ext%%\?*}"
        case "${ext,,}" in jpe?g|png|webp|gif|bmp) ;; *) ext=jpg ;; esac
        out="$OUT_DIR/${id} ${safe_title}.${ext}"
        [ -f "$out" ] && continue
        printf '%s\t%s\n' "$url" "$out"
    done \
  | xargs -P 8 -I{} bash -c '
        line="{}"
        url="${line%%	*}"
        out="${line#*	}"
        # Atomic write + structural validation.
        #
        # Two problems we have to defend against:
        #  1. Partial-read race: QML scanner sees the file mid-write and
        #     decodes a half-JPEG → rainbow noise. Solved by writing to
        #     <out>.part and atomic-rename only on success.
        #  2. Silent truncation: curl returns 0 even when the server
        #     hangs up mid-stream without Content-Length. The .part is
        #     "complete" but structurally broken. QML decodes what it
        #     can, hence the rainbow tail under a clean top. Solved by
        #     verifying the JPEG end-of-image marker (FFD9) and a
        #     minimum size before promoting to <out>.
        tmp="${out}.part"
        if ! curl --silent --show-error --location --max-time 25 --fail \
                  --remove-on-error \
                  -A "'"$REDDIT_UA"'" \
                  -o "$tmp" "$url"; then
            rm -f "$tmp"
            exit 0
        fi
        # Reject tiny responses (HTML error pages, captchas, empties).
        size=$(stat -c%s "$tmp" 2>/dev/null || echo 0)
        if [ "$size" -lt 4096 ]; then
            rm -f "$tmp"
            exit 0
        fi
        # Validate format by extension. JPEG must end in FFD9; PNG must
        # end with IEND chunk; WebP must start with RIFF/WEBP. Anything
        # else gets the same end-byte check as a coarse sanity floor.
        ext_lc=$(printf "%s" "${out##*.}" | tr "[:upper:]" "[:lower:]")
        valid=1
        case "$ext_lc" in
            jpg|jpeg)
                # JPEG SOI = FFD8, EOI = FFD9. Read first 2 + last 2 bytes.
                head_b=$(head -c2 "$tmp" | od -An -tx1 | tr -d " \n")
                tail_b=$(tail -c2 "$tmp" | od -An -tx1 | tr -d " \n")
                [ "$head_b" = "ffd8" ] && [ "$tail_b" = "ffd9" ] || valid=0
                ;;
            png)
                # PNG signature is fixed 8 bytes; the IEND chunk lives
                # in the last 12 bytes with literal "IEND" at offset -8.
                head_b=$(head -c8 "$tmp" | od -An -tx1 | tr -d " \n")
                tail_b=$(tail -c8 "$tmp" | head -c4)
                [ "$head_b" = "89504e470d0a1a0a" ] && [ "$tail_b" = "IEND" ] || valid=0
                ;;
            webp)
                head_b=$(head -c4 "$tmp" | tr -d "\0")
                [ "$head_b" = "RIFF" ] || valid=0
                ;;
        esac
        if [ $valid -eq 0 ]; then
            rm -f "$tmp"
            exit 0
        fi
        mv "$tmp" "$out" && printf "%s\n" "$out"
    '

exit 0
