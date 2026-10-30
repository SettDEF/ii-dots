pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Browser downloads in progress, for the dock.
 *
 * tela-zen (Firefox) runs as a native Wayland window, and Firefox only reports
 * download progress through an X11 window property - so nothing announces it.
 * What it does do is write "<name>.part" next to the target while a download
 * runs and rename it when done. That gives which files and how fast, but not
 * a percentage: the total size is not on disk. `progress` stays -1 until
 * tela-zen publishes real numbers (see its TASKS.md).
 *
 * inotify wakes this up, so an empty folder costs nothing; sizes are polled
 * once a second only while something is downloading.
 */
Singleton {
    id: root

    /// tela-zen's browser.download.dir, plus the XDG folder other browsers use.
    readonly property var dirs: Paths.downloads === `${Quickshell.env("HOME")}/Downloads` ? [Paths.downloads] : [Paths.downloads, `${Quickshell.env("HOME")}/Downloads`]

    /// [{ name, path, size, speed }] - speed in bytes/s, 0 until the second sample.
    property var active: []
    readonly property int count: root.active.length
    readonly property real totalSpeed: root.active.reduce((s, d) => s + (d.speed ?? 0), 0)
    /// 0..1 once something reports it; -1 = running, size unknown.
    property real progress: -1

    /// Every .part on disk, stale ones included - only these keep the slow poll alive.
    property int partCount: 0
    /// A .part untouched this long is an abandoned download, not a running one.
    readonly property int staleMs: 30000

    property var _lastSize: ({})
    property real _lastAt: 0

    function rescan() {
        if (!scan.running) scan.exec({ command: ["find", ...root.dirs, "-maxdepth", "1", "-name", "*.part", "-printf", "%s\t%T@\t%p\n"] });
    }

    Process {
        id: scan
        stdout: StdioCollector {
            onStreamFinished: {
                const now = Date.now();
                const dt = root._lastAt > 0 ? (now - root._lastAt) / 1000 : 0;
                const sizes = {};
                const out = [];
                let parts = 0;
                for (const line of String(text || "").split("\n")) {
                    const f = line.split("\t");
                    if (f.length < 3) continue;
                    const size = Number(f[0]);
                    const path = f.slice(2).join("\t");
                    parts++;
                    // Left over from an abandoned download: on disk, not downloading.
                    if (now - Number(f[1]) * 1000 > root.staleMs) continue;
                    const prev = root._lastSize[path];
                    sizes[path] = size;
                    out.push({
                        name: path.slice(path.lastIndexOf("/") + 1).replace(/\.part$/, ""),
                        path: path,
                        size: size,
                        speed: (prev !== undefined && dt > 0) ? Math.max(0, (size - prev) / dt) : 0
                    });
                }
                root._lastSize = sizes;
                root._lastAt = now;
                root.active = out;
                root.partCount = parts;
            }
        }
    }

    // Wakes on any .part appearing or going away, in either folder.
    Process {
        id: watch
        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "inotifywait", "-m", "-q", "-e", "create,delete,moved_from,moved_to", "--format", "%f", ...root.dirs]
        stdout: SplitParser {
            onRead: line => { if (String(line).endsWith(".part")) root.rescan(); }
        }
        // inotifywait dies if a folder vanishes (drive unmounted); try again later.
        onExited: watchRestart.restart()
    }
    Timer {
        id: watchRestart
        interval: 10000
        onTriggered: watch.running = true
    }

    // 1s while downloading; 5s while only stale .part files exist, so a
    // resumed download (which writes, but creates nothing) is still noticed.
    Timer {
        interval: root.count > 0 ? 1000 : 5000
        repeat: true
        running: root.partCount > 0
        onTriggered: root.rescan()
    }

    // Real numbers, once tela-zen publishes them (its TASKS.md #37):
    // [{ file, currentBytes, totalBytes, speed }]. Absent = .part view only.
    FileView {
        id: published
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/tela-zen/downloads.json`
        watchChanges: true
        printErrors: false
        onFileChanged: published.reload()
        onLoaded: {
            let list = [];
            try { list = JSON.parse(published.text()) ?? []; } catch (e) { list = []; }
            const total = list.reduce((s, d) => s + (Number(d.totalBytes) || 0), 0);
            const cur = list.reduce((s, d) => s + (Number(d.currentBytes) || 0), 0);
            root.progress = (list.length > 0 && total > 0) ? Math.min(1, cur / total) : -1;
        }
        onLoadFailed: root.progress = -1
    }

    Component.onCompleted: root.rescan()
}
