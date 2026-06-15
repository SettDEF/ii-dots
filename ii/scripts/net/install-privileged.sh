#!/usr/bin/env bash
# One-time privileged setup for the HUD network monitor + limiter.
# Run this yourself:  sudo ~/.config/quickshell/ii/scripts/net/install-privileged.sh
#
# It: installs nethogs + firejail, installs the polkit action + rule, and
# fixes ownership so the rule can't be tampered with by non-root. Idempotent.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root:  sudo $0" >&2
  exit 1
fi

DIR="$(cd "$(dirname "$0")" && pwd)"

echo ">> Installing packages (nethogs, firejail)…"
pacman -S --needed --noconfirm nethogs firejail

echo ">> Installing polkit action…"
install -Dm644 "$DIR/polkit/io.quickshell.netmon.policy" \
  /usr/share/polkit-1/actions/io.quickshell.netmon.policy

echo ">> Installing polkit rule…"
install -Dm644 "$DIR/polkit/49-quickshell-netmon.rules" \
  /etc/polkit-1/rules.d/49-quickshell-netmon.rules

echo ">> Reloading polkit…"
systemctl try-restart polkit 2>/dev/null || true

echo
echo "Done. Test with:"
echo "  ~/.config/quickshell/ii/scripts/net/netmon.sh start   # no password prompt if the rule took"
echo "  sleep 4 && cat /run/qs-netmon.json"
echo "  ~/.config/quickshell/ii/scripts/net/netmon.sh stop"
