#!/usr/bin/env bash
# Per-application up/down bandwidth limiting for the HUD, via firejail.
#
# firejail is installed setuid-root, so this needs no pkexec. Each limited app
# runs in its own network namespace (--net) connected by a veth pair; firejail
# drives `tc` on both ends, which is what makes DOWNLOAD limiting work (the
# app's inbound traffic becomes egress on the host side of the veth and can be
# shaped precisely — unlike throttling an already-running process).
#
#   throttle.sh launch <dl_kbps> <ul_kbps> <command> [args...]
#       Launch <command> sandboxed and capped. Prints the sandbox name.
#   throttle.sh list                 active firejail sandboxes (one per line)
#   throttle.sh set   <name> <dl> <ul>   change limits (KB/s)
#   throttle.sh clear <name>             remove limits
#   throttle.sh status <name>            show current shaping
#   throttle.sh kill  <name>             stop the sandboxed app
set -u

IFACE="$(ip route 2>/dev/null | awk '/default/{print $5; exit}')"

case "${1:-}" in
  launch)
    [ $# -ge 4 ] || { echo "usage: throttle.sh launch <dl> <ul> <cmd...>" >&2; exit 2; }
    dl="$2"; ul="$3"; shift 3
    # Sandbox name from the program basename + pid, sanitised for firejail.
    base="$(basename "$1" | tr -c 'A-Za-z0-9_' '_')"
    name="qsnet_${base}_$$"
    firejail --quiet --net="$IFACE" --name="$name" "$@" >/dev/null 2>&1 &
    # Wait for the sandbox to register before shaping it.
    for _ in $(seq 1 50); do
      firejail --list 2>/dev/null | grep -q -- "$name" && break
      sleep 0.1
    done
    firejail --bandwidth="$name" set "$IFACE" "$dl" "$ul" >/dev/null 2>&1 || true
    echo "$name"
    ;;
  list)
    # name<TAB>pid  for sandboxes we created (qsnet_*)
    firejail --list 2>/dev/null | awk -F: '/qsnet_/{print}'
    ;;
  set)
    [ $# -eq 4 ] || { echo "usage: throttle.sh set <name> <dl> <ul>" >&2; exit 2; }
    firejail --bandwidth="$2" set "$IFACE" "$3" "$4"
    ;;
  clear)
    [ $# -eq 2 ] || { echo "usage: throttle.sh clear <name>" >&2; exit 2; }
    firejail --bandwidth="$2" clear "$IFACE"
    ;;
  status)
    [ $# -eq 2 ] || { echo "usage: throttle.sh status <name>" >&2; exit 2; }
    firejail --bandwidth="$2" status
    ;;
  kill)
    [ $# -eq 2 ] || { echo "usage: throttle.sh kill <name>" >&2; exit 2; }
    firejail --shutdown="$2" >/dev/null 2>&1 || true
    ;;
  *)
    echo "usage: throttle.sh {launch|list|set|clear|status|kill} ..." >&2
    exit 2
    ;;
esac
