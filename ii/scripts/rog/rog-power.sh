#!/usr/bin/env bash
# Privileged half of the ROG Flow Z13 power control. Writes the APU power
# limits (PPT) via the asus-wmi platform driver — root-only sysfs, so this is
# the polkit exec.path, invoked by rog-power-ctl.sh through pkexec.
#
#   rog-power.sh set <watts>   clamp to [MIN,MAX] and apply all PPT limits
#   rog-power.sh get           print "watts|cpuTempC|fan1Rpm|fan2Rpm"
#
# Fan curves are NOT touched here — those go through `asusctl fan-curve`
# (asusd-mediated, no root) from the HUD. The HUD enforces the fan-floor
# safety coupling on the curve before applying it.
set -uo pipefail

PLAT=/sys/devices/platform/asus-nb-wmi
MIN=10            # sane floor (5W = the broken throttle we're fixing)
MAX=65            # summer-safe ceiling the user chose

die() { echo "rog-power: $*" >&2; exit 1; }
[ -w "$PLAT/ppt_pl1_spl" ] || [ "$(id -u)" = 0 ] || die "needs root (run via pkexec)"

case "${1:-}" in
  set)
    w="${2:-}"; [[ "$w" =~ ^[0-9]+$ ]] || die "watts must be an integer"
    (( w < MIN )) && w=$MIN; (( w > MAX )) && w=$MAX
    # Uniform sustained = boost = w: predictable and summer-safe (no boost
    # spike above the chosen ceiling). Firmware clamps anything it rejects.
    for f in ppt_pl1_spl ppt_apu_sppt ppt_pl2_sppt ppt_fppt; do
        [ -e "$PLAT/$f" ] && echo "$w" > "$PLAT/$f" 2>/dev/null || true
    done
    echo "$w"
    ;;
  get)
    w=$(cat "$PLAT/ppt_pl1_spl" 2>/dev/null || echo 0)
    t=$(awk '/Tctl/{}' </dev/null 2>/dev/null; cat /sys/class/hwmon/hwmon*/temp1_input 2>/dev/null | sort -rn | head -1)
    t=$(( ${t:-0} / 1000 ))
    f1=$(cat /sys/class/hwmon/*/fan1_input 2>/dev/null | head -1)
    f2=$(cat /sys/class/hwmon/*/fan2_input 2>/dev/null | head -1)
    echo "${w}|${t}|${f1:-0}|${f2:-0}"
    ;;
  *) die "usage: rog-power.sh {set <watts>|get}" ;;
esac
