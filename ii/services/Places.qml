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

    function refresh() {
        proc.exec({ command: ["bash", `${Directories.scriptPath}/fs/places.sh`] });
    }

    function open(path) {
        if (!path) return;
        Quickshell.execDetached(["xdg-open", path]);
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
            }
        }
    }
}
