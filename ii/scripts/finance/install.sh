#!/usr/bin/env bash
# Installs the user timer that keeps the sidebar's finance data fresh.
# Nothing here needs root — it is all in the user systemd instance.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dst="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$dst"
install -m 644 "$here/systemd/finance-sync.service" "$dst/"
install -m 644 "$here/systemd/finance-sync.timer"   "$dst/"
systemctl --user daemon-reload
systemctl --user enable --now finance-sync.timer
echo "Enabled. Next run:"
systemctl --user list-timers finance-sync.timer --no-pager
