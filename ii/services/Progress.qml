pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Jobs in progress, from any program: one JSON file each in $XDG_RUNTIME_DIR/progress
 * (written by `prog`, ~/.local/bin/prog, or anything else). The cards (modules/ii/progressCards) show them.
 * A finished job stays a few seconds, then its files go; a job whose process died is dropped.
 */
Singleton {
    id: root

    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/progress"
    /// every job, oldest first: { id, title, step, percent (-1 unknown), count [n, m], state running|done|failed, code }
    property var jobs: []
    readonly property var running: jobs.filter(j => j.state === "running")
    /// how long a finished card stays (ms)
    property int linger: 4000
    property real now: Date.now() / 1000

    function apply(list) {
        list.sort((a, b) => a.started - b.started)
        root.jobs = list
        root.now = Date.now() / 1000
        // finished ones whose time is up: their files go (the cards animate them out)
        const old = list.filter(j => j.state !== "running" && root.now - j.updated > root.linger / 1000)
        if (old.length) Quickshell.execDetached(["sh", "-c", 'cd "$0" && for i; do rm -f "$i.json" "$i.log"; done', root.dir].concat(old.map(j => j.id)))
    }
    function dismiss(id) { Quickshell.execDetached(["rm", "-f", `${root.dir}/${id}.json`, `${root.dir}/${id}.log`]) }
    function stop(job) { if (job.pid) Quickshell.execDetached(["kill", "-INT", String(job.pid)]) }

    Process {
        id: lister
        // each job file on one line; a running job whose pid is gone is marked failed
        command: ["sh", "-c", 'cd "$0" 2>/dev/null || exit 0; for f in *.json; do [ -e "$f" ] || continue; cat "$f"; echo; done', root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const l of text.split("\n")) {
                    if (!l.trim()) continue
                    try { out.push(JSON.parse(l)) } catch (e) {}
                }
                root.apply(out)
            }
        }
    }
    Timer { id: debounce; interval: 60; onTriggered: { lister.running = false; lister.running = true } }

    Process {
        id: watcher
        running: true
        command: ["sh", "-c", `mkdir -p '${root.dir}' && exec setpriv --pdeathsig TERM inotifywait -m -q -e moved_to,create,delete --format %f '${root.dir}'`]
        stdout: SplitParser { onRead: l => { if (l.endsWith(".json")) debounce.restart() } }
        onExited: restartWatcher.start()
    }
    Timer { id: restartWatcher; interval: 5000; onTriggered: watcher.running = true }
    // finished cards' time running out, and jobs whose program died without saying
    Timer { interval: 1000; running: root.jobs.length > 0; repeat: true; onTriggered: debounce.restart() }
    Timer {
        interval: 15000; running: root.running.length > 0; repeat: true
        onTriggered: Quickshell.execDetached(["sh", "-c", 'cd "$0" || exit; for f in *.json; do p=$(grep -o "\\"pid\\":[0-9]*" "$f" | cut -d: -f2); grep -q "\\"state\\":\\"running\\"" "$f" && [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null && rm -f "$f" "${f%.json}.log"; done', root.dir])
    }
    Component.onCompleted: debounce.restart()
}
