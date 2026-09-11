#!/usr/bin/env bash
# Unprivileged control for the ROG power feature, called by the HUD.
#   rog-power-ctl.sh set <watts>   set PPT (via pkexec → rog-power.sh)
#   rog-power-ctl.sh get           read current PPT/temp/fans (no root needed)
#   rog-power-ctl.sh fan <data>    apply a fan curve via asusctl (no root)
#       data = "42c:11%,50c:21%,..." (asusctl format)
#   rog-power-ctl.sh fancurve on|off   custom curve vs firmware default
#   rog-power-ctl.sh fanstate      -> on | off | mixed  (for the UI toggle)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAT=/sys/devices/platform/asus-nb-wmi

case "${1:-}" in
  set)
    pkexec "$DIR/rog-power.sh" set "${2:-}" ;;
  get)
    # PPT/temp/fans are world-readable, so no pkexec needed for a poll.
    w=$(cat "$PLAT/ppt_pl1_spl" 2>/dev/null || echo 0)
    t=$(( $(cat /sys/class/hwmon/hwmon*/temp1_input 2>/dev/null | sort -rn | head -1 || echo 0) / 1000 ))
    f1=$(cat /sys/class/hwmon/*/fan1_input 2>/dev/null | head -1)
    f2=$(cat /sys/class/hwmon/*/fan2_input 2>/dev/null | head -1)
    echo "${w}|${t}|${f1:-0}|${f2:-0}" ;;
  fan)
    # asusd is the privileged daemon; asusctl talks to it as the user.
    prof=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo performance)
    data="${2:-}"
    # Drawing a curve enables it (below), so the deliberate-off flag no longer
    # holds — clear it or the keeper stays stood down over an enabled curve.
    rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/fan-curve-keeper.off"
    for fan in cpu gpu; do
        asusctl fan-curve --mod-profile "$prof" --fan "$fan" --data "$data" >/dev/null 2>&1 || true
        asusctl fan-curve --mod-profile "$prof" --fan "$fan" --enable-fan-curve true >/dev/null 2>&1 || true
    done
    echo ok ;;
  fancurve)
    # Flip the whole profile between the user's custom curve and the firmware's
    # default one. Both fans together on purpose: they were found in DIFFERENT
    # modes (CPU on firmware default, GPU on the custom curve), which makes the
    # graph in the UI a lie for whichever fan is not following it.
    case "${2:-}" in
      on|true|1)  v=true ;;
      off|false|0) v=false ;;
      *) echo "usage: rog-power-ctl.sh fancurve <on|off>" >&2; exit 2 ;;
    esac
    prof=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo performance)
    # Tell fan-curve-keeper this was deliberate. It watches pwm1_enable and
    # cannot distinguish a user turning the curve off from asusd dropping it,
    # so without this flag it re-enables within 20s and the HUD switch shows
    # "off" over a curve that is actually on.
    ovr="${XDG_STATE_HOME:-$HOME/.local/state}/fan-curve-keeper.off"
    mkdir -p "$(dirname "$ovr")"
    if [ "$v" = false ]; then : > "$ovr"; else rm -f "$ovr"; fi
    # --enable-fan-curves (plural) covers every fan of the profile in one call.
    asusctl fan-curve --mod-profile "$prof" --enable-fan-curves "$v" >/dev/null 2>&1 || true
    echo ok ;;
  fanstate)
    # asusctl is the source of truth here. The hwmon pwmN_enable values also
    # encode this but INVERTED from the obvious reading (1 = manual/custom
    # active, 2 = automatic/firmware default), which is easy to get backwards.
    out=$(asusctl fan-curve --get-enabled 2>/dev/null)
    on=$(printf '%s\n' "$out" | grep -c "enabled: true")
    off=$(printf '%s\n' "$out" | grep -c "enabled: false")
    if   [ "$on" -gt 0 ] && [ "$off" -eq 0 ]; then echo on
    elif [ "$off" -gt 0 ] && [ "$on" -eq 0 ]; then echo off
    elif [ "$on" -gt 0 ] || [ "$off" -gt 0 ]; then echo mixed
    else echo unknown; fi ;;
  *) echo "usage: rog-power-ctl.sh {set <watts>|get|fan <data>|fancurve <on|off>|fanstate}" >&2; exit 2 ;;
esac
