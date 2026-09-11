#!/usr/bin/env bash
# Reddit subreddit autocomplete — feeds the skwd search dropdown.
#
# Usage:  reddit_complete.sh <query>
# Output (stdout), one subreddit per line, tab-separated:
#   <display_name>\t<over18: 0|1>\t<subscribers>
#
# Prints nothing (exit 0) on any failure — the dropdown just stays empty.

set -u
Q=${1:-}
[ -z "$Q" ] && exit 0

# shellcheck source=reddit_lib.sh
. "$(dirname "$0")/reddit_lib.sh"

reddit_load_env || exit 0

QCLEAN=$(printf '%s' "$Q" | tr -cd 'A-Za-z0-9_' | cut -c1-40)
[ -z "$QCLEAN" ] && exit 0

TOKEN=$(reddit_get_token) || exit 0

# subreddit_autocomplete_v2 returns a listing of subreddit things. We ask
# for over_18 results too so NSFW subs are searchable (and taggable).
JSON=$(reddit_api "$TOKEN" --get \
    --data-urlencode "query=${QCLEAN}" \
    --data-urlencode "include_over_18=true" \
    --data-urlencode "include_profiles=false" \
    --data-urlencode "limit=10" \
    "https://oauth.reddit.com/api/subreddit_autocomplete_v2")

printf '%s' "$JSON" | jq -r '
    .data.children[]?
    | .data
    | select(.display_name != null)
    | [ .display_name,
        (if (.over18 // false) then "1" else "0" end),
        (.subscribers // 0 | tostring) ]
    | @tsv
' 2>/dev/null

exit 0
