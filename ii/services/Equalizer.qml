pragma Singleton
pragma ComponentBehavior: Bound

// HUD 10-band equalizer — drives a native PipeWire filter-chain sink via
// scripts/hud-equalizer.sh. Band gains apply live (pw-cli, no restart);
// install/enable touch audio routing and restart PipeWire.

import qs
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string scriptPath: Quickshell.shellPath("scripts") + "/hud-equalizer.sh"
    readonly property var freqLabels: ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    readonly property real minGain: -12
    readonly property real maxGain: 12

    // dB gain per band (-12..+12).
    property var bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property string activePreset: "Flat"

    property bool installed: false   // conf file present
    property bool active: false      // EQ sink routed as default
    property string nodeId: ""       // live filter-chain sink node id
    property string outNodeId: ""    // filter-chain output node (headroom)
    property bool busy: false        // install/remove in flight

    readonly property var presetNames: ["Flat", "Bass", "Treble", "Vocal", "Pop", "Rock", "Jazz", "Classic"]
    readonly property var presets: ({
        "Flat":    [ 0,  0,  0,  0,  0,  0,  0,  0,  0,  0],
        "Bass":    [ 7,  6,  4,  2,  0,  0,  0,  0,  0,  0],
        "Treble":  [ 0,  0,  0,  0,  0,  0,  2,  4,  6,  7],
        "Vocal":   [-3, -2,  0,  2,  4,  4,  3,  1, -1, -2],
        "Pop":     [-1,  0,  2,  4,  4,  2,  0, -1, -1,  0],
        "Rock":    [ 5,  3,  1, -1, -2,  0,  2,  3,  4,  5],
        "Jazz":    [ 3,  2,  0,  1,  2,  2,  0,  1,  2,  3],
        "Classic": [ 4,  3,  2,  0,  0,  0, -2, -1,  2,  3]
    })

    // ── Persistence ────────────────────────────────────────────────────
    FileView {
        id: store
        path: Qt.resolvedUrl(`file://${Quickshell.env("HOME")}/.local/state/quickshell/equalizer.json`)
        onLoaded: {
            try {
                const d = JSON.parse(store.text() || "{}")
                if (Array.isArray(d.bands) && d.bands.length === 10) root.bands = d.bands
                if (d.activePreset !== undefined) root.activePreset = d.activePreset
            } catch (e) {}
        }
        onLoadFailed: {}
        Component.onCompleted: reload()
    }
    function save() {
        store.setText(JSON.stringify({ bands: root.bands, activePreset: root.activePreset }))
    }
    Timer { id: saveDeb; interval: 600; onTriggered: root.save() }

    // ── Status poll ─────────────────────────────────────────────────────
    Process {
        id: statusProc
        command: ["bash", root.scriptPath, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                root.installed = t.indexOf("installed=yes") >= 0
                const m = t.match(/ id=(\S+)/)
                root.nodeId = (m && m[1] !== "-") ? m[1] : ""
                const mo = t.match(/ out=(\S+)/)
                root.outNodeId = (mo && mo[1] !== "-") ? mo[1] : ""
            }
        }
    }
    function refreshStatus() { statusProc.running = true }

    // ── Install / remove / route ────────────────────────────────────────
    Process {
        id: actionProc
        onExited: {
            root.busy = false
            statusRePoll.restart()
        }
    }
    // PipeWire needs a beat to come back up + register the sink node.
    Timer { id: statusRePoll; interval: 1800; onTriggered: root.refreshStatus() }

    function install() {
        root.busy = true
        actionProc.exec(["bash", root.scriptPath, "install"])
    }
    function remove() {
        root.busy = true
        root.active = false
        actionProc.exec(["bash", root.scriptPath, "remove"])
    }
    function setActive(on) {
        if (on && root.nodeId === "") return
        root.active = on
        actionProc.exec(on
            ? ["bash", root.scriptPath, "enable", root.nodeId]
            : ["bash", root.scriptPath, "disable"])
    }

    // ── Live band control (pw-cli) ──────────────────────────────────────
    Process { id: applyProc }
    Timer {
        id: applyDeb
        interval: 55
        onTriggered: {
            if (root.nodeId === "") return
            if (applyProc.running) { applyDeb.restart(); return }
            applyProc.exec(["bash", root.scriptPath, "apply",
                            root.nodeId, root.outNodeId || "-"]
                .concat(root.bands.map(b => String(Math.round(b * 10) / 10))))
        }
    }
    function applyBands() { applyDeb.restart() }

    function setBand(i, gain) {
        const b = root.bands.slice()
        b[i] = Math.max(root.minGain, Math.min(root.maxGain, gain))
        root.bands = b
        root.activePreset = ""
        applyBands()
        saveDeb.restart()
    }
    function applyPreset(name) {
        if (!root.presets[name]) return
        root.bands = root.presets[name].slice()
        root.activePreset = name
        applyBands()
        root.save()
    }

    // Push the saved curve whenever the live node (re)appears.
    onNodeIdChanged: if (nodeId !== "") applyBands()

    Component.onCompleted: refreshStatus()
}
