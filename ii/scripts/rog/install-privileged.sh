#!/usr/bin/env bash
# One-time privileged setup for ROG power control.
#   sudo ~/.config/quickshell/ii/scripts/rog/install-privileged.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0" >&2; exit 1; }
DIR="$(cd "$(dirname "$0")" && pwd)"
install -Dm644 "$DIR/polkit/io.quickshell.rogpower.policy" /usr/share/polkit-1/actions/io.quickshell.rogpower.policy
install -Dm644 "$DIR/polkit/49-quickshell-rogpower.rules" /etc/polkit-1/rules.d/49-quickshell-rogpower.rules
systemctl try-restart polkit 2>/dev/null || true
echo "Done. Test:  ~/.config/quickshell/ii/scripts/rog/rog-power-ctl.sh set 35 && rog-power-ctl.sh get"
