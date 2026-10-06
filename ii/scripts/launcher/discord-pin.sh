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
# Pinning one at a time is slow, so there are two bulk routes:
#
#   discord-pin.sh --import <dir|servers/index.json>
#       Every server at once, correctly named, from the data package Discord
#       gives you under Settings > Data & Privacy > Request all of my data.
#       Their export, their names, nothing touched that is not yours.
#
#   discord-pin.sh --harvest
#       Copy a pile of links in Discord (Copy Link), then run this once. It
#       reads them back out of the clipboard history Hyprland already keeps,
#       so there is no second watcher to run and it reaches backwards as well
#       as forwards. Names come from the PUBLIC widget endpoint, which needs
#       no auth; servers with the widget off fall back to their id.
#
#   discord-pin.sh --watch
#       The live version of the same thing, for pinning as you go. Costs a
#       wl-paste process for as long as it runs, which --harvest does not.
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
# https://discord.com/api/guilds/<id>/widget.json is public: no token, no
# account, nothing of Discord's that is not already open. Servers with the
# widget disabled simply 403, and the id is used instead.
guild_name() {   # $1 guild id -> name, or empty
    [ "$1" = "@me" ] && { printf 'Direct messages'; return; }
    curl -fsS --max-time 8 "https://discord.com/api/guilds/$1/widget.json" 2>/dev/null \
        | jq -r '.name // empty' 2>/dev/null
}

auto_name() {    # $1 guild id, $2 channel id ("" for a whole server)
    local g; g=$(guild_name "$1"); [ -n "$g" ] || g="Server $1"
    if [ -n "${2:-}" ]; then printf '%s · %s' "$g" "${2: -4}"; else printf '%s' "$g"; fi
}

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

# Parses a link (web, deep, or bare ids) into "<guild>/<channel>" or "<guild>".
parse_ids() {
    printf '%s' "$1" | grep -oE '(@me|[0-9]{5,})(/[0-9]{5,})?$' || true
}

# Discord's Developer Mode "Copy ID" gives a bare snowflake with no link around
# it, which is what most people actually copy. The public widget endpoint tells
# the two apart without any auth: 200 is a guild and names it, 403 "Widget
# Disabled" is still a guild (just private), and 404 means it is not one — a
# channel id, which cannot be opened without knowing its guild.
classify_snowflake() {   # $1 id -> prints "guild" or "channel"
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
        "https://discord.com/api/guilds/$1/widget.json" 2>/dev/null) || code=000
    case "$code" in
        200|403) printf 'guild' ;;
        *)       printf 'channel' ;;
    esac
}

pin() {          # $1 name ("" = derive), $2 ids
    local name=$1 ids=$2 guild channel deep node
    guild=${ids%%/*}; channel=${ids#"$guild"}; channel=${channel#/}
    [ "$channel" = "$guild" ] && channel=""
    deep="discord://-/channels/${ids}"
    [ -n "$name" ] || name=$(auto_name "$guild" "$channel")
    node=$(build_node "$name" "$deep")
    jq --arg g "$GROUP" --arg n "$name" --argjson node "$node" '
        .search.commands //= []
      | if ([.search.commands[]? | select(.name==$g)] | length) == 0
        then .search.commands += [{name:$g, icon:"forum", description:"Discord", sub:[]}]
        else . end
      | .search.commands = [ .search.commands[]? |
          if .name==$g
          then .sub = ([ .sub[]? | select(.name != $n) ] + [$node])
          else . end ]
    ' "$CONFIG" | write_json "$CONFIG"
    printf 'pinned: /%s %s  ->  %s\n' "$GROUP" "$name" "$deep"
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
    --import)
        [ $# -eq 2 ] || die "--import needs the export dir or its servers/index.json"
        [ -f "$CONFIG" ] || die "no config at $CONFIG"
        src=$2; [ -d "$src" ] && src="$src/servers/index.json"
        [ -f "$src" ] || die "no servers/index.json at: $src"
        jq -e 'type=="object"' "$src" >/dev/null 2>&1 || die "not a Discord servers index: $src"
        n=0
        # Names come from the export, so no network call and no rate limit.
        while IFS=$'\t' read -r gid gname; do
            [ -n "$gid" ] || continue
            pin "$gname" "$gid" >/dev/null && n=$((n+1))
        done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$src")
        echo "imported $n server(s) into /$GROUP"
        exit 0 ;;
    --harvest)
        # The cheap one. Hyprland already runs a clipboard watcher, so a second
        # daemon of our own would be duplicated work: cliphist's history IS the
        # watch, and it reaches backwards as well as forwards.
        command -v cliphist >/dev/null || die "--harvest needs cliphist"
        [ -f "$CONFIG" ] || die "no config at $CONFIG"
        n=0; seen=""
        # Previews are truncated, so match on them cheaply and decode only the
        # few that look like links. Nothing else in the history is read.
        while read -r cid; do
            [ -n "$cid" ] || continue
            ids=$(parse_ids "$(cliphist decode "$cid" 2>/dev/null | tr -d '[:space:]')")
            [ -n "$ids" ] || continue
            case " $seen " in *" $ids "*) continue ;; esac
            seen="$seen $ids"
            pin "" "$ids" && n=$((n+1))
        done < <(cliphist list 2>/dev/null \
                 | grep -aE 'discord\.com/channels|discord://' | cut -f1)
        [ "$n" -gt 0 ] && echo "harvested $n link(s) from the clipboard history" \
                       || echo "no Discord links in the clipboard history yet — copy some and run this again"
        exit 0 ;;
    --watch)
        command -v wl-paste >/dev/null || die "--watch needs wl-clipboard"
        echo "watching the clipboard; copy channel or server links in Discord. Ctrl-C to stop."
        exec wl-paste --watch "$0" --from-stdin ;;
    --from-stdin)
        url=$(cat | tr -d '[:space:]'); ids=$(parse_ids "$url")
        [ -n "$ids" ] || exit 0          # not a Discord link, stay quiet
        [ -f "$CONFIG" ] || exit 0
        # A bare snowflake could be either kind; a channel one is unusable on
        # its own, so say that rather than pinning something that will not open.
        case "$url" in
            [0-9][0-9][0-9][0-9][0-9]*)
                if [ "$(classify_snowflake "$ids")" = channel ]; then
                    echo "that is a channel id; use right-click > Copy Link instead," >&2
                    echo "since a channel cannot be opened without its server id" >&2
                    exit 1
                fi ;;
        esac
        pin "" "$ids"
        exit 0 ;;
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

# Manual: a name you chose, one link.
[ $# -eq 2 ] || usage 2
[ -f "$CONFIG" ] || die "no config at $CONFIG"
ids=$(parse_ids "$2")
[ -n "$ids" ] || die "no guild/channel ids in: $2
    expected .../channels/<guild|@me>[/<channel>]"
pin "$1" "$ids"
