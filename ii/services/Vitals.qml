pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * What the vitals background service knows, for any module of the shell.
 *
 * `vitals --watch` (the vitals-watch user service) records metrics every 10 s
 * and logs findings as they open and close. This reads both — it does not
 * sample anything itself, so it costs nothing while the shell runs:
 *
 *   history      the last hour, one point per 10 s:
 *                { t, cpu, mem, gpu, temp, gpu_temp, pkg_w, bat, bat_w, rx, tx, dr, dw }
 *   findings     what is wrong right now: [{ sev: "critical"|"warning"|"info", title, detail, since }]
 *   critical, warnings   counts of those
 *   available    false when vitals is not installed / the service has not written yet
 *
 * open()        the Vitals window
 */
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || root.home + "/.local/state") + "/vitals"
    readonly property string bin: root.home + "/.local/bin/vitals"

    property var history: []
    property var findings: []
    property bool available: false
    readonly property int critical: (Array.isArray(root.findings) ? root.findings : []).filter(f => f && f.sev === "critical").length
    readonly property int warnings: (Array.isArray(root.findings) ? root.findings : []).filter(f => f && f.sev === "warning").length
    readonly property var latest: Array.isArray(root.history) && root.history.length ? root.history[root.history.length - 1] : null

    // ── the live feed ───────────────────────────────────────────────────
    // One `vitals --stream` for the whole shell: CPU, memory, swap, temps,
    // GPU and the top processes, every few seconds. The bar's and dock's
    // CPU/RAM readings (ResourceUsage), the RAM warning (RamMonitor) and the
    // HUD's process list read this instead of each polling /proc and running
    // ps on their own. Measured: ~1 % of one core at a 2 s interval.
    // `fresh` goes false when the feed stalls, and they fall back to their own reads.
    readonly property int streamInterval: Math.max(2, Math.round((Config.options?.resources?.updateInterval ?? 3000) / 1000))
    property var snap: null
    property real snapAt: 0
    property real _tick: 0
    Timer { interval: 5000; running: true; repeat: true; onTriggered: root._tick = Date.now() }
    readonly property bool fresh: root.snap !== null && (Math.max(root._tick, Date.now()) - root.snapAt) < root.streamInterval * 3000 + 2000
    readonly property var procs: root.snap?.procs ?? []

    Process {
        id: streamProc
        running: true
        command: [root.bin, "--stream", "--interval", String(root.streamInterval), "--top", "10"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const v = JSON.parse(line);
                    root.snap = v.snapshot ?? null;
                    root.snapAt = Date.now();
                } catch (e) {}
            }
        }
        // vitals missing or crashed: try again later, the consumers use their own reads meanwhile
        onExited: streamRestart.start()
    }
    Timer { id: streamRestart; interval: 30000; onTriggered: streamProc.running = true }
    onStreamIntervalChanged: { streamProc.running = false; streamProc.running = true; }

    /// One field of the history as a plain series (nulls dropped), for graphs.
    function series(field) { return root.history.map(p => p[field]).filter(v => v !== null && v !== undefined); }

    function open() {
        Quickshell.execDetached([root.home + "/.local/bin/vitals-gui"]);
    }

    function refresh() {
        if (!historyProc.running) historyProc.running = true;
        if (!findingsProc.running) findingsProc.running = true;
    }

    // The service writes every 10 s; reading every 15 s is fresh enough for a
    // dock tile and keeps this at one tiny process per tick.
    Timer {
        interval: 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: historyProc
        command: [root.bin, "--history", "1"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const h = JSON.parse(text);
                    root.history = h.points ?? [];
                    root.available = root.history.length > 0;
                } catch (e) {
                    root.available = false;
                }
            }
        }
    }

    // findings.jsonl: {"event":"open",…} when a finding appears, {"event":"close"} when it
    // clears. The open set is what is wrong now. The tail is plenty: findings
    // change rarely, and an old open that never closed predates the last restart
    // of the service, which re-opens whatever still holds on its first pass.
    Process {
        id: findingsProc
        command: ["sh", "-c", `tail -n 600 '${root.stateDir}/findings.jsonl' 2>/dev/null`]
        stdout: StdioCollector {
            onStreamFinished: {
                const open = {};
                for (const line of text.split("\n")) {
                    if (!line) continue;
                    let e;
                    try { e = JSON.parse(line); } catch (err) { continue; }
                    const sev = e.sev === "CRIT" ? "critical" : e.sev === "WARN" ? "warning" : "info";
                    if (e.event === "open") open[e.title] = { sev, title: e.title, detail: e.detail ?? "", since: e.t };
                    else if (e.event === "close") delete open[e.title];
                }
                root.findings = Object.values(open).sort((a, b) => (a.sev === "critical" ? 0 : 1) - (b.sev === "critical" ? 0 : 1));
            }
        }
    }
}
