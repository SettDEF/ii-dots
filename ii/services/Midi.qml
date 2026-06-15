pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs

Singleton {
    id: root

    // ── Device list ───────────────────────────────────────────────────────────
    property list<var> devices: []

    // ── Live MIDI activity ────────────────────────────────────────────────────
    // Last received event fields
    property string lastEventType: ""   // "Note on", "Note off", "Control change", etc.
    property int    lastChannel:   0
    property int    lastNote:      0
    property int    lastVelocity:  0
    property int    lastControl:   0
    property int    lastValue:     0
    property string lastPort:      ""

    // Flash flag — briefly true on any incoming event
    property bool   activity: false
    property string activePort: ""      // port currently being monitored (e.g. "20:0")

    readonly property var noteNames: ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
    function noteName(n) { return noteNames[n % 12] + Math.floor(n / 12 - 1) }

    // ── Device polling ────────────────────────────────────────────────────────
    Process {
        id: deviceProc
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").slice(1) // skip header
                let devs = []
                for (const line of lines) {
                    const m = line.match(/^\s*(\d+:\d+)\s+(.+?)\s{2,}(.+?)\s*$/)
                    if (!m) continue
                    const port   = m[1].trim()
                    const client = m[2].trim()
                    const name   = m[3].trim()
                    // Skip system/internal ports
                    if (client === "System" || client === "Midi Through") continue
                    devs.push({ port, client, name })
                }
                root.devices = devs
                // Auto-select first real device if none selected
                if (root.activePort === "" && devs.length > 0)
                    root.activePort = devs[0].port
            }
        }
    }

    Timer {
        // 10 s — only while the sidebar is open.  Aseqdump invocations
        // were running 24/7 even though MIDI is only inspected from
        // the sidebar's MIDI container.
        interval: 10000
        running: GlobalStates.sidebarRightOpen
        repeat: true
        onTriggered: deviceProc.exec({ command: ["aseqdump", "-l"] })
    }
    Component.onCompleted: deviceProc.exec({ command: ["aseqdump", "-l"] })

    // ── MIDI event monitor ────────────────────────────────────────────────────
    Process {
        id: monitorProc
        command: root.activePort !== "" ? ["aseqdump", "-p", root.activePort] : []

        stdout: SplitParser {
            onRead: data => {
                // Example: "  0:1   Note on                 0, note 60, velocity 100"
                // or:      "  0:1   Control change          0, controller 7, value 100"
                const noteOn  = data.match(/Note on\s+(\d+),\s*note\s+(\d+),\s*velocity\s+(\d+)/)
                const noteOff = data.match(/Note off\s+(\d+),\s*note\s+(\d+),\s*velocity\s+(\d+)/)
                const cc      = data.match(/Control change\s+(\d+),\s*controller\s+(\d+),\s*value\s+(\d+)/)
                const pb      = data.match(/Pitch bend\s+(\d+),\s*value\s+(-?\d+)/)

                if (noteOn) {
                    root.lastEventType = "Note on"
                    root.lastChannel  = parseInt(noteOn[1])
                    root.lastNote     = parseInt(noteOn[2])
                    root.lastVelocity = parseInt(noteOn[3])
                    root.activity = true; activityTimer.restart()
                } else if (noteOff) {
                    root.lastEventType = "Note off"
                    root.lastChannel  = parseInt(noteOff[1])
                    root.lastNote     = parseInt(noteOff[2])
                    root.lastVelocity = parseInt(noteOff[3])
                    root.activity = true; activityTimer.restart()
                } else if (cc) {
                    root.lastEventType = "CC"
                    root.lastChannel   = parseInt(cc[1])
                    root.lastControl   = parseInt(cc[2])
                    root.lastValue     = parseInt(cc[3])
                    root.activity = true; activityTimer.restart()
                } else if (pb) {
                    root.lastEventType = "Pitch bend"
                    root.lastChannel   = parseInt(pb[1])
                    root.lastValue     = parseInt(pb[2])
                    root.activity = true; activityTimer.restart()
                }
            }
        }
    }

    onActivePortChanged: {
        monitorProc.terminate()
        if (activePort !== "") monitorProc.startDetached()
    }

    Timer {
        id: activityTimer
        interval: 400; repeat: false
        onTriggered: root.activity = false
    }
}
