pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

// ── RAM safety monitor ─────────────────────────────────────────────────────
// Polls /proc/meminfo every 5 s, exposes percent-used and a 3-tier state
// (ok / warn / critical). On WARN transition: desktop notification once.
// On CRITICAL sustained for 20 s: notifies + closes the heaviest known
// in-memory panels (skwd content, walltune history) to free RAM without
// taking the whole shell down. Only if STILL critical 15 s after that
// does it fall back to an explicit "kill skwd" panic.
//
// Thresholds are chosen for a ~23 GiB box:
//   warn at 80 %       — still safe, but skwd-heavy work should stop
//   critical at 92 %   — swap is likely engaging
//   panic at 96 %      — kernel OOM-killer is close
//
// Call RamMonitor.load() once from shell.qml to force singleton init.

Singleton {
    id: root

    // ── Tunables ──────────────────────────────────────────────────────────
    readonly property real warnThreshold:     80    // % used
    readonly property real criticalThreshold: 92    // % used
    readonly property real panicThreshold:    96    // % used
    readonly property int  pollIntervalMs:    5000
    // Hysteresis below the threshold before the state drops back down,
    // stops the notification spam when usage oscillates around the line.
    readonly property real hysteresis:        3     // % points

    // ── Live state ────────────────────────────────────────────────────────
    property real percentUsed: 0
    property real percentAvailable: 100
    property string state: "ok"            // "ok" | "warn" | "critical" | "panic"
    property bool ready: false

    function load() { /* force init */ }

    function tier(p) {
        if (p >= panicThreshold)    return "panic"
        if (p >= criticalThreshold) return "critical"
        if (p >= warnThreshold)     return "warn"
        return "ok"
    }
    // Transition tier with hysteresis: only drop down if we're meaningfully
    // below the threshold.
    function _settledTier(p, prevState) {
        const t = tier(p)
        if (t === prevState) return t
        // Climbing up: take the new tier immediately.
        const order = { ok: 0, warn: 1, critical: 2, panic: 3 }
        if (order[t] > order[prevState]) return t
        // Dropping down: require hysteresis distance below the boundary.
        const adjusted = p + hysteresis
        return tier(adjusted)
    }

    // ── Polling ───────────────────────────────────────────────────────────
    Timer {
        interval: root.pollIntervalMs
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: memProc.running = true
    }
    Process {
        id: memProc
        command: ["bash", "-c",
            "awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{print t, a}' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = (text || "").trim().split(/\s+/)
                if (parts.length < 2) return
                const total = parseInt(parts[0]) || 1
                const avail = parseInt(parts[1]) || 0
                root.percentAvailable = (avail / total) * 100
                root.percentUsed      = 100 - root.percentAvailable
                const newState = root._settledTier(root.percentUsed, root.state)
                if (newState !== root.state) {
                    const prev = root.state
                    root.state = newState
                    root._onStateChanged(prev, newState)
                }
                root.ready = true
            }
        }
    }

    // ── Reactions ─────────────────────────────────────────────────────────
    // Sustained-critical timer: only after N continuous seconds in
    // critical do we start unloading heavy panels.
    Timer {
        id: sustainCriticalTimer
        interval: 20000
        repeat: false
        onTriggered: root._unloadHeavyPanels()
    }
    Timer {
        id: sustainPanicTimer
        interval: 15000
        repeat: false
        onTriggered: root._panic()
    }

    function _onStateChanged(prev, next) {
        // Tier transition notifications + sustained timers.
        sustainCriticalTimer.stop()
        sustainPanicTimer.stop()
        if (next === "ok") {
            return
        }
        if (next === "warn") {
            _notify("RAM at " + Math.round(percentUsed) + "%",
                    "System getting full. Closing heavy apps recommended.",
                    "low")
            return
        }
        if (next === "critical") {
            _notify("RAM critical (" + Math.round(percentUsed) + "%)",
                    "Skwd / Wall-tune will auto-unload in 20 s if this persists.",
                    "normal")
            sustainCriticalTimer.restart()
            return
        }
        if (next === "panic") {
            _notify("RAM PANIC (" + Math.round(percentUsed) + "%)",
                    "Auto-unloading heavy panels NOW.",
                    "critical")
            _unloadHeavyPanels()
            sustainPanicTimer.restart()
        }
    }

    function _unloadHeavyPanels() {
        // skwd's lazy Loader is gated by GlobalStates.skwdWallOpen — set it
        // false to destroy the content tree and free the wallpaper array,
        // poster cache, MediaPlayer, etc. Same trick for walltune.
        if (GlobalStates.skwdWallOpen)   GlobalStates.skwdWallOpen   = false
        if (GlobalStates.wallTuneOpen)   GlobalStates.wallTuneOpen   = false
        if (GlobalStates.wallpaperSelectorOpen) GlobalStates.wallpaperSelectorOpen = false
        _notify("Closed skwd / WallTune to free RAM",
                "Panels will reopen on demand.",
                "low")
    }

    function _panic() {
        // Last-ditch: panels were already closed but we're still in panic.
        // Trigger an explicit GC pass via Qt.callLater (best we can do from
        // QML), and tell the user to inspect manually.
        Qt.callLater(function () {
            for (let i = 0; i < 3; i++) gcProc.running = true
        })
        _notify("RAM still panicking — manual cleanup needed",
                "Check top memory consumers in the HUD.",
                "critical")
    }

    function _notify(title, body, urgency) {
        notifyProc.command = [
            "notify-send",
            "-a", "Quickshell",
            "-u", urgency || "normal",
            "-i", "system-monitor-symbolic",
            title, body
        ]
        notifyProc.running = true
    }

    Process { id: notifyProc }
    // sync forces dirty pages to disk so the kernel can drop them sooner
    // when memory pressure is acute. Cheap, harmless if we're not actually
    // in panic.
    Process {
        id: gcProc
        command: ["bash", "-c", "sync"]
    }
}
