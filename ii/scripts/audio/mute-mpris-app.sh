#!/bin/bash
# Toggle mute on the audio sinks of the app behind a given MPRIS player.
# Usage: mute-mpris-app.sh <identity> [<desktopEntry>] [<dbusName>]
# Output: "MUTED" / "UNMUTED" / "NOSINK" on stdout.

set -e

ident="${1:-}"
desktop="${2:-}"
dbus="${3:-}"

# Build a list of lowercase keywords to match against pactl properties.
keys=()
[[ -n "$ident"   ]] && keys+=("$(echo "$ident"   | awk '{print tolower($1)}')")
[[ -n "$desktop" ]] && keys+=("$(echo "$desktop" | tr '[:upper:]' '[:lower:]')")
if [[ -n "$dbus" ]]; then
    keys+=("$(echo "$dbus" | cut -d. -f1 | tr '[:upper:]' '[:lower:]')")
fi
# De-dupe + drop empties
keys=($(printf "%s\n" "${keys[@]}" | awk 'NF && !seen[$0]++'))
[[ ${#keys[@]} -eq 0 ]] && { echo NOSINK; exit 0; }

ids_str=$(
  pactl list sink-inputs | python3 -c '
import sys, re
keys = [k.lower() for k in sys.argv[1:]]
def match(section):
    blob = "\n".join(section).lower()
    return any(k and k in blob for k in keys)
current = []
out = []
def flush():
    if current and match(current):
        for l in current:
            if l.startswith("Sink Input #"):
                out.append(l.split("#",1)[1].strip())
                break
for line in sys.stdin:
    if line.startswith("Sink Input #"):
        flush()
        current.clear()
    current.append(line)
flush()
print(" ".join(out))
' "${keys[@]}"
)

# Bash array from space-separated stdout
read -r -a ids <<<"$ids_str"
[[ ${#ids[@]} -eq 0 ]] && { echo NOSINK; exit 0; }

for id in "${ids[@]}"; do
    pactl set-sink-input-mute "$id" toggle
done

# Re-parse to find the resulting state of the LAST sink we toggled (pactl 17
# doesn't expose `get-sink-input-mute`).
last_id="${ids[-1]}"
final=$(pactl list sink-inputs | awk -v id="$last_id" '
    $0 ~ "^Sink Input #"id"$" { in_section = 1; next }
    in_section && /^Sink Input #/ { in_section = 0 }
    in_section && /^[[:space:]]*Mute:/ { print ($2 == "yes" ? "MUTED" : "UNMUTED"); exit }
')
echo "${final:-UNMUTED}"
