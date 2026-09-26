pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common

/**
 * Changes the wallpaper on an interval, from the favourites or the wallpapers
 * folder, never picking one of the last few again. Waits while game mode is on:
 * a switch rethemes every app, which is not something to do mid-match.
 */
Singleton {
    id: root

    readonly property var intervals: [0, 15, 30, 60, 180]   // minutes, 0 = off
    readonly property int minutes: Persistent.ready ? Persistent.states.skwd.rotateMinutes : 0
    readonly property string from: Persistent.ready ? Persistent.states.skwd.rotateFrom : "favorites"
    readonly property bool enabled: root.minutes > 0

    function setMinutes(m) { Persistent.states.skwd.rotateMinutes = m }
    function setFrom(f) { Persistent.states.skwd.rotateFrom = f }

    function next() {
        if (root.from === "favorites") {
            root._pick(Object.keys(WallpaperHub.favoritePaths).filter(p => p.startsWith("/")))
        } else if (!folderProc.running) {
            folderProc.running = true
        }
    }

    function _pick(candidates) {
        const recent = JSON.parse(Persistent.states.skwd.rotateHistory || "[]")
        const current = Config.options.background.wallpaperPath
        let pool = candidates.filter(p => p !== current && recent.indexOf(p) < 0)
        if (pool.length === 0) pool = candidates.filter(p => p !== current)
        if (pool.length === 0) return
        const path = pool[Math.floor(Math.random() * pool.length)]
        // Remember up to half the pool, so a small set still rotates.
        const keep = Math.max(1, Math.min(20, Math.floor(candidates.length / 2)))
        Persistent.states.skwd.rotateHistory = JSON.stringify([path].concat(recent).slice(0, keep))
        Wallpapers.apply(path)
    }

    Process {
        id: folderProc
        command: ["bash", "-c", `find "$HOME/Pictures/Wallpapers" -maxdepth 3 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) 2>/dev/null`]
        stdout: StdioCollector {
            onStreamFinished: root._pick(text.split("\n").filter(l => l.length > 0))
        }
    }

    Timer {
        interval: Math.max(1, root.minutes) * 60000
        repeat: true
        running: root.enabled
        onTriggered: if (!GameMode.active && !GlobalStates.screenLocked) root.next()
    }
}
