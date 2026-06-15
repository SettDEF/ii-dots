#!/usr/bin/env python3
"""Parse `nethogs -t` (trace mode) from stdin and emit per-process up/down.

nethogs trace mode prints, once per refresh, a block of lines shaped like:

    /usr/lib/firefox/firefox/1234/1000\t12.500\t3.200

i.e. "<program-path>/<pid>/<uid>\\t<sent KB/s>\\t<recv KB/s>", and separates
refreshes with a line beginning "Refreshing:". We accumulate the current
refresh and, on each "Refreshing:" boundary (and at EOF), write the snapshot
as a JSON array to the path given in argv[1], atomically and world-readable so
the (unprivileged) Quickshell HUD can poll it.

This script is run as root (the parent daemon is launched via pkexec), so it
keeps the output file at mode 0644.
"""
import json
import os
import re
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "/run/qs-netmon.json"

# <path/with/slashes>/<pid>/<uid>   <sent>   <recv>
# Split tolerates tabs or runs of spaces; the program path itself may contain
# slashes and spaces, so we anchor on the trailing /<pid>/<uid> + two numbers.
ENTRY = re.compile(
    r"^(?P<prog>.+)/(?P<pid>\d+)/(?P<uid>\d+)[ \t]+"
    r"(?P<sent>[\d.]+)[ \t]+(?P<recv>[\d.]+)\s*$"
)


def write_snapshot(rows):
    # rows: dict keyed by (name, pid) -> [up, dn]
    data = [
        {"name": name, "pid": pid, "up": round(up, 1), "dn": round(dn, 1)}
        for (name, pid), (up, dn) in rows.items()
    ]
    # Heaviest first (up+dn) so the HUD can just take the head.
    data.sort(key=lambda r: r["up"] + r["dn"], reverse=True)
    tmp = OUT + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.chmod(tmp, 0o644)
    os.replace(tmp, OUT)


def main():
    rows = {}
    # Emit an immediate empty snapshot so the HUD sees "monitor is up" at once.
    write_snapshot(rows)
    for line in sys.stdin:
        line = line.rstrip("\n")
        if line[:11].lower().startswith("refreshing"):
            write_snapshot(rows)
            rows = {}
            continue
        m = ENTRY.match(line)
        if not m:
            continue
        prog = m.group("prog")
        name = prog.rsplit("/", 1)[-1] or prog
        if name in ("unknown TCP", "unknown UDP"):
            name = "unknown"
        pid = int(m.group("pid"))
        up = float(m.group("sent"))
        dn = float(m.group("recv"))
        key = (name, pid)
        cur = rows.get(key)
        # Within a refresh a (name,pid) should appear once; if it repeats, keep
        # the larger sample rather than double-count.
        if cur is None:
            rows[key] = [up, dn]
        else:
            cur[0] = max(cur[0], up)
            cur[1] = max(cur[1], dn)
    write_snapshot(rows)


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
