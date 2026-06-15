#!/usr/bin/env bash
# Privileged half of the HUD per-process network monitor.
#
# Runs as ROOT — it is the exec.path of the polkit action
# io.quickshell.netmon.run, and is invoked via pkexec by netmon.sh. nethogs
# needs CAP_NET_RAW to see per-process traffic, which is why this must be
# privileged.
#
#   netmon-daemon.sh start [iface]   stream nethogs -> JSON snapshot loop
#   netmon-daemon.sh stop            kill a running daemon
#
# Output: /run/qs-netmon.json  (mode 0644, JSON array, refreshed ~2s)
set -u

OUT="/run/qs-netmon.json"
PIDFILE="/run/qs-netmon.pid"
SELFDIR="$(cd "$(dirname "$0")" && pwd)"

case "${1:-start}" in
  stop)
    [ -r "$PIDFILE" ] && kill "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
    # The nethogs child lives in our process group; mop up any stragglers.
    pkill -f 'nethogs -t' 2>/dev/null || true
    rm -f "$PIDFILE"
    exit 0
    ;;
  start)
    IFACE="${2:-$(ip route 2>/dev/null | awk '/default/{print $5; exit}')}"
    [ -n "$IFACE" ] || { echo "no default interface" >&2; exit 1; }

    echo $$ > "$PIDFILE"; chmod 644 "$PIDFILE" 2>/dev/null || true
    # Clean up the pidfile and the nethogs child when we exit/are killed.
    trap 'rm -f "$PIDFILE"; pkill -P $$ -f nethogs 2>/dev/null' EXIT TERM INT

    # -t trace mode (machine-parsable blocks), -d 2 → 2-second refresh.
    nethogs -t -d 2 "$IFACE" 2>/dev/null | python3 "$SELFDIR/netmon-parse.py" "$OUT"
    ;;
  *)
    echo "usage: $0 {start [iface]|stop}" >&2
    exit 2
    ;;
esac
