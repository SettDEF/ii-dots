import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    id: root
    name: Translation.tr("MiniMeters")

    // ── State ─────────────────────────────────────────────────────────
    property bool mmRunning:  false
    property bool mmHasLayer: false
    readonly property bool mmZombie: mmRunning && !mmHasLayer  // running but no surface
    readonly property string mmPath: `${Quickshell.env("HOME")}/Applications/MiniMeters-x86_64.AppImage`

    toggled: mmRunning && mmHasLayer
    icon: mmZombie ? "refresh" : "equalizer"
    statusText: mmZombie ? Translation.tr("No layer — restart")
              : (mmRunning ? Translation.tr("Running") : Translation.tr("Off"))
    tooltipText: Translation.tr("Audio meters overlay (MiniMeters) | Right-click for options")

    mainAction: () => {
        if (mmZombie)        restartMM()
        else if (mmRunning)  stopMM()
        else                 startMM()
    }

    altAction: () => {
        Quickshell.execDetached([`${Quickshell.env("HOME")}/.config/quickshell/ii/scripts/hyprland/minimeters_control.sh`])
    }

    function startMM()   { Quickshell.execDetached([mmPath]); Qt.callLater(() => mmCheckProc.running = true) }
    function stopMM()    { Quickshell.execDetached(["pkill", "-ix", "minimeters"]); mmRunning = false }
    function restartMM() {
        Quickshell.execDetached(["bash", "-c",
            `pkill -ix minimeters; sleep 0.4; nohup '${mmPath}' >/dev/null 2>&1 &`])
        Qt.callLater(() => mmCheckProc.running = true)
    }

    // Probe MiniMeters status periodically.
    Process {
        id: mmCheckProc
        command: ["bash", "-c",
            `printf 'RUN:%s LAYER:%s' "$(pgrep -ix minimeters | head -1)" "$(hyprctl -j layers 2>/dev/null | grep -c '"namespace": *"MiniMeters"')"`]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/RUN:([^\s]*)\s+LAYER:(\d+)/)
                root.mmRunning  = !!(m && m[1] && m[1] !== "")
                root.mmHasLayer = !!(m && parseInt(m[2]) > 0)
            }
        }
    }
    Timer {
        interval: 3000; running: true; repeat: true
        onTriggered: mmCheckProc.running = true
    }
    Component.onCompleted: mmCheckProc.running = true
}
