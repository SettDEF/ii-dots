#!/usr/bin/env bash
# Put BetterDiscord back into Discord after Discord updates itself.
#
# Every Discord update unpacks a fresh app-X.Y.Z/ whose core index.js is plain
# again, so BetterDiscord — and with it every plugin, including the shell's
# IIVoiceOverlay (voice overlay, dock voice controls) — silently stops loading.
# That happened with app-1.0.162 on 2026-10-13 and went unnoticed for days.
#
# Run by bd-reinject.path whenever ~/.config/discord changes; idempotent. The
# change takes effect the next time Discord starts (it is never restarted here:
# restarting Discord mid-call drops the call).
set -euo pipefail

ASAR="${XDG_CONFIG_HOME:-$HOME/.config}/BetterDiscord/data/betterdiscord.asar"
[ -f "$ASAR" ] || { echo "bd-reinject: no BetterDiscord at $ASAR" >&2; exit 0; }

patched=0
for idx in "${XDG_CONFIG_HOME:-$HOME/.config}"/discord/app-*/modules/discord_desktop_core-*/discord_desktop_core/index.js; do
    [ -f "$idx" ] || continue
    grep -q "betterdiscord.asar" "$idx" && continue
    printf 'require(%s);\nmodule.exports = require("./core.asar");\n' "\"$ASAR\"" > "$idx"
    echo "bd-reinject: patched $idx"
    patched=1
done

if [ $patched = 1 ] && command -v notify-send >/dev/null; then
    notify-send -a Discord -i discord "BetterDiscord re-installed" \
        "Discord updated and dropped it; plugins load again the next time Discord starts."
fi
