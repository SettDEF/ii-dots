// Average colour of an app icon, resolved once per icon name and kept for the
// session. Quickshell.iconPath() hands back an "image://icon/..." URL, which
// ColorQuantizer cannot read, so scripts/images/icon-color.sh resolves the
// name on disk and averages it instead.
pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // icon name -> "#rrggbb", or "" when nothing could be resolved.
    property var colors: ({})

    property var _queue: []
    property string _current: ""

    /// Kick off a lookup. Cheap to call repeatedly: cached and de-duplicated.
    function request(name) {
        if (!name || root.colors[name] !== undefined) return
        if (root._current === name || root._queue.indexOf(name) >= 0) return
        root._queue.push(name)
        root._next()
    }

    function colorOf(name) {
        return (name && root.colors[name]) || ""
    }

    function _next() {
        if (root._current !== "" || root._queue.length === 0) return
        root._current = root._queue.shift()
        proc.exec({ command: ["bash", `${Directories.scriptPath}/images/icon-color.sh`, root._current] })
    }

    function _finish(out) {
        if (root._current === "") return
        const map = Object.assign({}, root.colors)
        map[root._current] = String(out || "").trim()
        root.colors = map
        root._current = ""
        root._next()
    }

    Process {
        id: proc
        // Only the stream end records a result. Process.exited fires after the
        // queue has already moved on, so using it too wrote one icon's colour
        // onto the next icon's name.
        stdout: StdioCollector {
            onStreamFinished: root._finish(text)
        }
    }

    // A process that never opens its stream would otherwise stall the queue.
    Timer {
        interval: 5000
        running: root._current !== ""
        onTriggered: root._finish("")
    }
}
