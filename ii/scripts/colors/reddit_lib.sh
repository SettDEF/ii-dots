#!/usr/bin/env bash
# Shared Reddit helpers — sourced by fetch_reddit.sh and reddit_complete.sh.
# Not meant to be run directly. Holds the one copy of OAuth token handling
# and the authenticated-request helper so the callers stay small.
#
# Provides:
#   REDDIT_ENV_FILE, REDDIT_TOKEN_CACHE   — paths
#   reddit_load_env      — source ~/.secure/reddit-app.env (exit-caller on fail)
#   reddit_get_token     — echo a valid access token, refreshing if expired
#   reddit_api <url...>  — curl the oauth API with the bearer token + UA
#
# Requires (from the env file): REDDIT_CLIENT_ID/SECRET/USER/PASS/UA.

REDDIT_ENV_FILE="$HOME/.secure/reddit-app.env"
REDDIT_TOKEN_CACHE="$HOME/.cache/quickshell/reddit-oauth-token.json"

# Load creds. On failure, echo reason to stderr and return non-zero so the
# caller can decide the exit code (fetch uses 5, complete just bails quietly).
reddit_load_env() {
    [ -r "$REDDIT_ENV_FILE" ] || {
        echo "Missing $REDDIT_ENV_FILE — run reddit_oauth_setup.sh first." >&2
        return 1
    }
    # shellcheck disable=SC1090
    . "$REDDIT_ENV_FILE"
}

# Echo a valid bearer token. Uses the cache when it is still good (the setup
# script bakes in a 60s safety margin); otherwise refreshes via password
# grant and rewrites the cache. Returns non-zero if refresh fails.
reddit_get_token() {
    local now exp tok response access_token expires_in
    now=$(date +%s)
    if [ -r "$REDDIT_TOKEN_CACHE" ]; then
        exp=$(jq -r '.expires_at // 0' "$REDDIT_TOKEN_CACHE" 2>/dev/null)
        tok=$(jq -r '.access_token // empty' "$REDDIT_TOKEN_CACHE" 2>/dev/null)
        if [ -n "$tok" ] && [ "$exp" -gt "$now" ] 2>/dev/null; then
            printf '%s' "$tok"; return 0
        fi
    fi

    response=$(curl --silent --show-error --max-time 15 -X POST \
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
    mkdir -p "$(dirname "$REDDIT_TOKEN_CACHE")"
    printf '{"access_token":"%s","expires_at":%d}\n' \
        "$access_token" "$((now + expires_in - 60))" > "$REDDIT_TOKEN_CACHE"
    printf '%s' "$access_token"
}

# Authenticated GET against oauth.reddit.com. First arg is the token, the
# rest are passed through to curl (URL and/or --data-urlencode pairs).
reddit_api() {
    local token=$1; shift
    curl --silent --show-error --max-time 12 \
        -A "$REDDIT_UA" \
        -H "Authorization: Bearer $token" \
        "$@"
}
