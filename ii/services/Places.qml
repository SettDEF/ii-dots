// The user's file-manager places, for the dock's folder grid.
//
// Read from KDE's own bookmark file by scripts/fs/places.sh so the grid
// matches Dolphin's sidebar rather than a hardcoded list.
pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    /// [{ path, name }]
    property var entries: []
    property bool loaded: false

    /// Places that are mount points (under /mnt, /media, /run/media) rather
    /// than folders: they get a usage bar instead of a folder chip.
    readonly property var drives: root.entries.filter(e => root.isDrive(e.path))
    readonly property var folders: root.entries.filter(e => !root.isDrive(e.path))

    /// path -> { mounted, size, avail } in bytes. Filled by refreshUsage().
    property var usage: ({})

    function isDrive(path) {
        return /^\/(mnt|media|run\/media)\/[^/]+/.test(String(path));
    }

    function refresh() {
        proc.exec({ command: ["bash", `${Directories.scriptPath}/fs/places.sh`] });
    }

    /// df on every drive place. Cheap, so callers run it whenever they show.
    function refreshUsage() {
        const paths = root.drives.map(d => root._strip(d.path));
        if (paths.length === 0 || dfProc.running) return;
        dfProc.exec({ command: ["/usr/bin/df", "-B1", "--output=target,size,avail", "--", ...paths] });
    }

    function open(path) {
        if (!path) return;
        Quickshell.execDetached(["xdg-open", path]);
    }

    function _strip(p) {
        const s = String(p);
        return s.length > 1 ? s.replace(/\/+$/, "") : s;
    }

    Component.onCompleted: root.refresh()

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of String(text || "").split("\n")) {
                    if (line.length === 0) continue;
                    const tab = line.indexOf("\t");
                    if (tab < 0) continue;
                    out.push({ path: line.slice(0, tab), name: line.slice(tab + 1) });
                }
                root.entries = out;
                root.loaded = true;
                root.refreshUsage();
            }
        }
    }

    // df prints one row per argument, in order. An unmounted mount point
    // reports the filesystem it sits on (usually /), so "mounted" means the
    // row's target IS the path.
    Process {
        id: dfProc
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = String(text || "").split("\n").slice(1).filter(l => l.trim().length > 0);
                const paths = root.drives.map(d => root._strip(d.path));
                const next = {};
                rows.forEach((row, i) => {
                    const m = row.trim().match(/^(.*\S)\s+(\d+)\s+(\d+)$/);
                    if (!m || i >= paths.length) return;
                    next[paths[i]] = {
                        mounted: m[1] === paths[i],
                        size: Number(m[2]),
                        avail: Number(m[3])
                    };
                });
                root.usage = next;
            }
        }
    }
}
