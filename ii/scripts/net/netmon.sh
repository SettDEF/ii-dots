#!/usr/bin/env bash
# Unprivileged control for the HUD per-process network monitor.
# Drives the privileged netmon-daemon.sh through pkexec (polkit action
# io.quickshell.netmon.run, which a rules.d entry lets the active user run
# without a password — see polkit/49-quickshell-netmon.rules).
#
#   netmon.sh start    launch the monitor (idempotent)
#   netmon.sh stop     stop it
#   netmon.sh status   prints "running" or "stopped" (liveness by file mtime)
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="/run/qs-netmon.json"
FRESH_SECS=8   # snapshot older than this ⇒ daemon is not alive

is_fresh() {
  [ -f "$OUT" ] || return 1
  local now mt
  now=$(date +%s); mt=$(stat -c %Y "$OUT" 2>/dev/null || echo 0)
  [ $(( now - mt )) -lt "$FRESH_SECS" ]
}

case "${1:-}" in
  start)
    is_fresh && exit 0          # already running, nothing to do
    # pkexec stays attached as the root parent of the daemon; background it.
    setsid pkexec "$DIR/netmon-daemon.sh" start >/dev/null 2>&1 &
    ;;
  stop)
    pkexec "$DIR/netmon-daemon.sh" stop >/dev/null 2>&1 || true
    ;;
  status)
    is_fresh && echo running || echo stopped
    ;;
  *)
    echo "usage: netmon.sh {start|stop|status}" >&2
    exit 2
    ;;
esac
