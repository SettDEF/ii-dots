pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * zeit's jobs (commands a z.rule sent to another pane), from the file zeit
 * keeps at $XDG_RUNTIME_DIR/zeit/jobs.json: what runs, what just failed.
 */
Singleton {
    id: root

    readonly property string path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/zeit/jobs.json"
    property var jobs: []
    readonly property var running: root.jobs.filter(j => j.state === "running")
    // the newest finished job, while it is fresh (until seen or ten minutes old)
    property string seen: ""
    property real loadedAt: Date.now()
    readonly property var latest: root.jobs.find(j => j.state !== "running") ?? null
    readonly property bool fresh: !!root.latest && root.latest.id !== root.seen
    readonly property bool failed: root.fresh && root.latest.state === "failed"

    function markSeen() { if (root.latest) root.seen = root.latest.id }
    // show the job's pane in zeit (the zash window still has to be raised by hand)
    function jump(job) {
        Quickshell.execDetached(["sh", "-c", `"$HOME/.local/bin/zeit" job-jump -t "${job.pane}"`])
        root.markSeen()
    }
    function rerun(job) {
        Quickshell.execDetached(["sh", "-c", `"$HOME/.local/bin/zeit" job-rerun -t "${job.pane}"`])
    }

    FileView {
        id: file
        path: Qt.resolvedUrl("file://" + root.path)
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.jobs = JSON.parse(String(file.text()))
            } catch (e) {
                root.jobs = []
            }
        }
        // no jobs.json yet (zeit has run none): a file watch cannot watch what does not exist, so
        // look again every few seconds until zeit writes it, or the first job never showed
        printErrors: false
        onLoadFailed: {
            root.jobs = []
            missingRetry.restart()
        }
    }
    Timer {
        id: missingRetry
        interval: 5000
        onTriggered: file.reload()
    }
    // a finished job stops being news after ten minutes
    Timer {
        interval: 60000
        running: root.fresh
        repeat: true
        onTriggered: {
            if (root.latest && Date.now() - root.loadedAt > 600000) root.markSeen()
        }
    }
    onLatestChanged: root.loadedAt = Date.now()
}
