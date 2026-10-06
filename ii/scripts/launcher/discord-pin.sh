#!/usr/bin/env bash
# Pin Discord channels into the launcher's /dc group, across accounts.
#
# There is no safe way to enumerate your servers: Discord's RPC GET_GUILDS
# needs an OAuth scope they whitelist, the local leveldb holds the auth token
# but no guild list, and calling the API with that token is self-botting, which
# gets accounts disabled. So entries are curated, and this makes curating one a
# single command.
#
# In Discord: Settings > Advanced > Developer Mode, right-click a channel >
# Copy Link.
#
#   discord-pin.sh "Hyprland #support" https://discord.com/channels/123/456
#   discord-pin.sh --list
#   discord-pin.sh --remove "Hyprland #support"
#   discord-pin.sh --accounts                     show configured accounts
#   discord-pin.sh --add-account alt 'vesktop --url --'
#   discord-pin.sh --del-account alt
#
# With one account a pin is a flat leaf: /dc <name>. With several it becomes a
# group, one leaf per account: /dc <name> <account>. Re-pinning an existing
# name rebuilds it, so adding an account and re-pinning upgrades it in place.
#
# Entries land in search.commands, which the launcher reads live — no restart.
set -euo pipefail

CONFIG="${II_CONFIG:-$HOME/.config/illogical-impulse/config.json}"
ACCTS="${II_DISCORD_ACCOUNTS:-$HOME/.config/illogical-impulse/discord-accounts.json}"
GROUP=dc

die() { echo "discord-pin: $*" >&2; exit 1; }
usage() { sed -n '2,25p' "$0" | sed 's/^# \?//'; exit "${1:-0}"; }

command -v jq >/dev/null || die "jq is required"

# Accounts live in their own file on purpose: quickshell rewrites config.json
# from its declared schema, and a key the schema does not know about can be
# dropped on the next write.
ensure_accounts() {
    [ -f "$ACCTS" ] && return
    mkdir -p "$(dirname "$ACCTS")"
    printf '{\n  "main": "discord-open"\n}\n' > "$ACCTS"
}
accounts_json() { ensure_accounts; jq -c . "$ACCTS"; }

write_json() {   # $1 = destination; stdin = new content
    local dest=$1 tmp; tmp=$(mktemp)
    cat > "$tmp"
    jq -e . "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; die "refusing to write invalid JSON to $dest"; }
    /usr/bin/mv "$tmp" "$dest"
}

# One leaf per account, or a single flat leaf when there is only one.
build_node() {   # $1 name, $2 deep link
    local name=$1 deep=$2
    jq -n --arg n "$name" --arg d "$deep" --argjson a "$(accounts_json)" '
        ($a | to_entries) as $accs
        | if ($accs | length) <= 1
          then { name:$n, icon:"tag", description:$d,
                 exec: (($accs[0].value // "discord-open") + " " + $d) }
          else { name:$n, icon:"tag", description:$d,
                 sub: [ $accs[] | { name:.key, icon:"person", description:$d,
                                    exec: (.value + " " + $d) } ] }
          end'
}

[ $# -gt 0 ] || usage 2

case "${1:-}" in
    --help|-h) usage ;;
    --accounts) accounts_json | jq -r 'to_entries[] | "  \(.key)\t\(.value)"'; exit 0 ;;
    --add-account)
        [ $# -eq 3 ] || die "--add-account needs <id> <command>"
        ensure_accounts
        jq --arg k "$2" --arg v "$3" '.[$k] = $v' "$ACCTS" | write_json "$ACCTS"
        echo "account added: $2 -> $3"
        echo "re-pin an entry (or all of them) to give it buttons for this account"
        exit 0 ;;
    --del-account)
        [ $# -eq 2 ] || die "--del-account needs <id>"
        ensure_accounts
        jq --arg k "$2" 'del(.[$k])' "$ACCTS" | write_json "$ACCTS"
        echo "account removed: $2"; exit 0 ;;
    --list)
        [ -f "$CONFIG" ] || die "no config at $CONFIG"
        jq -r --arg g "$GROUP" '
            [.search.commands[]? | select(.name==$g)][0] // empty
            | .sub[]? | "  \(.name)\n      \(.description)"' "$CONFIG"
        exit 0 ;;
    --remove)
        [ $# -eq 2 ] || die "--remove needs a name"
        [ -f "$CONFIG" ] || die "no config at $CONFIG"
        # Drop the group once it empties, or the launcher keeps offering a /dc
        # with nothing behind it.
        jq --arg g "$GROUP" --arg n "$2" '
            .search.commands = [ .search.commands[]? |
              if .name==$g then .sub = [ .sub[]? | select(.name != $n) ] else . end ]
          | .search.commands = [ .search.commands[]? |
              select(.name != $g or ((.sub // []) | length) > 0) ]
        ' "$CONFIG" | write_json "$CONFIG"
        echo "removed: $2"; exit 0 ;;
esac

[ $# -eq 2 ] || usage 2
[ -f "$CONFIG" ] || die "no config at $CONFIG"
NAME=$1; URL=$2

ids=$(printf '%s' "$URL" | grep -oE '(@me|[0-9]{5,})/[0-9]{5,}$' || true)
[ -n "$ids" ] || die "no guild/channel ids in: $URL
    expected .../channels/<guild|@me>/<channel>"
DEEP="discord://-/channels/${ids}"

jq --arg g "$GROUP" --arg n "$NAME" --argjson node "$(build_node "$NAME" "$DEEP")" '
    .search.commands //= []
  | if ([.search.commands[]? | select(.name==$g)] | length) == 0
    then .search.commands += [{name:$g, icon:"forum", description:"Discord", sub:[]}]
    else . end
  | .search.commands = [ .search.commands[]? |
      if .name==$g
      then .sub = ([ .sub[]? | select(.name != $n) ] + [$node])
      else . end ]
' "$CONFIG" | write_json "$CONFIG"

echo "pinned: /$GROUP $NAME  ->  $DEEP"
