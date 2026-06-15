#!/usr/bin/env bash
# One-time Reddit OAuth setup for fetch_reddit.sh.
#
# What you need beforehand:
#   1. Go to https://www.reddit.com/prefs/apps (logged in)
#   2. Scroll to the bottom → "create another app..."
#   3. Choose type: SCRIPT  (not web app, not installed app)
#      - name: anything you want, e.g. "skwd-wallpapers"
#      - description: optional
#      - about url: leave blank
#      - redirect uri: http://localhost:8080  (required even though unused)
#   4. Click "create app"
#   5. Note the two strings you need:
#        - CLIENT_ID: the short string just under "personal use script"
#        - CLIENT_SECRET: the "secret" field below the app name
#
# Run this script and paste them in when prompted. It will:
#   - Exchange your creds for an access token + refresh token
#   - Save everything to ~/.secure/reddit-app.env (chmod 600)
#   - Verify by calling oauth.reddit.com once
#
# After this, fetch_reddit.sh works.

set -eu

SECRET_DIR="$HOME/.secure"
ENV_FILE="$SECRET_DIR/reddit-app.env"
TOKEN_CACHE="$HOME/.cache/quickshell/reddit-oauth-token.json"
mkdir -p "$SECRET_DIR" "$(dirname "$TOKEN_CACHE")"

# Existing config?
if [ -f "$ENV_FILE" ]; then
    echo "Existing config at $ENV_FILE."
    read -r -p "Overwrite? [y/N] " ans
    case "${ans,,}" in y|yes) ;; *) echo "Aborted."; exit 0 ;; esac
fi

echo "=== Reddit OAuth setup ===  (creds NEVER leave this machine)"
echo
read -r -p "Reddit username: " REDDIT_USER
[ -z "$REDDIT_USER" ] && { echo "username required" >&2; exit 1; }

# read -s hides the input (no echo to terminal).
read -r -s -p "Reddit password: " REDDIT_PASS; echo
[ -z "$REDDIT_PASS" ] && { echo "password required" >&2; exit 1; }

read -r -p "App CLIENT_ID (under 'personal use script'): " CLIENT_ID
[ -z "$CLIENT_ID" ] && { echo "client id required" >&2; exit 1; }

read -r -s -p "App CLIENT_SECRET: " CLIENT_SECRET; echo
[ -z "$CLIENT_SECRET" ] && { echo "client secret required" >&2; exit 1; }

# Reddit requires the UA to identify the app + user. Format:
# <platform>:<app-name>:<version> (by /u/<user>)
UA="skwd-wallpapers:0.1 (by /u/${REDDIT_USER})"

echo
echo "Exchanging credentials for access token…"
RESPONSE=$(curl --silent --show-error --max-time 15 \
    -X POST \
    --user "${CLIENT_ID}:${CLIENT_SECRET}" \
    -A "$UA" \
    -d "grant_type=password" \
    --data-urlencode "username=${REDDIT_USER}" \
    --data-urlencode "password=${REDDIT_PASS}" \
    "https://www.reddit.com/api/v1/access_token")

# Reddit returns { error: "invalid_grant" } on bad creds
if ! echo "$RESPONSE" | jq -e '.access_token' >/dev/null 2>&1; then
    echo "✘ Token request failed. Response:"
    echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
    echo
    echo "Common causes:"
    echo "  - Wrong CLIENT_ID / CLIENT_SECRET (re-check at reddit.com/prefs/apps)"
    echo "  - Wrong username / password"
    echo "  - 2FA on your Reddit account → use password:OTPCODE in the password prompt"
    echo "  - Account hasn't verified email yet (Reddit requires this for API)"
    exit 1
fi

ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')
EXPIRES_IN=$(echo "$RESPONSE" | jq -r '.expires_in')

echo "✔ Got access token (expires in ${EXPIRES_IN}s)"

# Verify by making a real API call
echo "Verifying with a /me lookup…"
ME=$(curl --silent --show-error --max-time 10 \
    -A "$UA" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    "https://oauth.reddit.com/api/v1/me")

ME_USER=$(echo "$ME" | jq -r '.name // empty')
if [ "$ME_USER" != "$REDDIT_USER" ]; then
    echo "✘ /me returned a different (or no) user: $ME_USER"
    echo "$ME" | jq . 2>/dev/null | head -10
    exit 1
fi
echo "✔ /me confirms identity: $ME_USER"

# Save credentials. The access token gets cached separately in
# TOKEN_CACHE with its expiry; the fetcher refreshes it transparently.
umask 077
cat > "$ENV_FILE" <<EOF
# Reddit OAuth credentials for skwd wallpaper fetcher
# Read by ~/.config/quickshell/ii/scripts/colors/fetch_reddit.sh
REDDIT_USER='$REDDIT_USER'
REDDIT_PASS='$REDDIT_PASS'
REDDIT_CLIENT_ID='$CLIENT_ID'
REDDIT_CLIENT_SECRET='$CLIENT_SECRET'
REDDIT_UA='$UA'
EOF

# Save the access token + when it expires (epoch seconds) so we don't
# have to re-auth on every script invocation.
NOW=$(date +%s)
cat > "$TOKEN_CACHE" <<EOF
{
  "access_token": "$ACCESS_TOKEN",
  "expires_at": $((NOW + EXPIRES_IN - 60))
}
EOF
chmod 600 "$ENV_FILE" "$TOKEN_CACHE"

echo
echo "✔ Setup complete."
echo "  Credentials: $ENV_FILE"
echo "  Token cache: $TOKEN_CACHE"
echo
echo "fetch_reddit.sh is now ready. Test it:"
echo "  $HOME/.config/quickshell/ii/scripts/colors/fetch_reddit.sh space hot '' \"\$HOME/Pictures/Wallpapers/skwd\""
