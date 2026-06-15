pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs

Singleton {
    id: root

    // ── Profile ───────────────────────────────────────────────────────────────
    property string profile: "Balanced"           // Quiet | Balanced | Performance
    readonly property var profiles: ["Quiet", "Balanced", "Performance"]

    function setProfile(p) {
        profile = p
        _exec(["asusctl", "profile", "set", p])
    }
    function nextProfile() { _exec(["asusctl", "profile", "next"]) }

    // ── GPU mode ──────────────────────────────────────────────────────────────
    property string gpuMode: "Hybrid"             // Integrated | Hybrid | AsusMuxDiscreet
    property string gpuPendingAction: ""

    function setGpuMode(m) { _exec(["supergfxctl", "--mode", m]) }

    // ── Battery charge limit ──────────────────────────────────────────────────
    property int batteryLimit: 100                // 20–100

    function setBatteryLimit(v) {
        batteryLimit = v
        _exec(["asusctl", "battery", "limit", String(v)])
    }

    // ── Armoury toggles ───────────────────────────────────────────────────────
    property bool panelOverdrive: false
    property bool bootSound: false
    property int  chargeMode: 0                   // 0=Default 1=Balanced 2=Full

    function setPanelOverdrive(v) {
        panelOverdrive = v
        _exec(["asusctl", "armoury", "set", "panel_overdrive", v ? "1" : "0"])
    }
    function setBootSound(v) {
        bootSound = v
        _exec(["asusctl", "armoury", "set", "boot_sound", v ? "1" : "0"])
    }
    function setChargeMode(v) {
        chargeMode = v
        _exec(["asusctl", "armoury", "set", "charge_mode", String(v)])
    }

    // ── Internal helpers ──────────────────────────────────────────────────────
    function _exec(cmd) {
        _cmdProc.exec({ command: cmd })
    }

    Process { id: _cmdProc }

    // Poll profile
    Process {
        id: profileProc
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/Active profile:\s*(\w+)/)
                if (m) root.profile = m[1]
            }
        }
    }

    // Poll GPU mode
    Process {
        id: gpuProc
        stdout: StdioCollector {
            onStreamFinished: { root.gpuMode = text.trim() }
        }
    }

    // Poll GPU pending action
    Process {
        id: gpuPendingProc
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                root.gpuPendingAction = (t === "No action required" || t === "") ? "" : t
            }
        }
    }

    // Poll battery limit
    Process {
        id: batLimitProc
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseInt(text.trim())
                if (!isNaN(v)) root.batteryLimit = v
            }
        }
    }

    // Poll armoury values
    Process {
        id: armouryProc
        stdout: StdioCollector {
            onStreamFinished: {
                const po = text.match(/panel_overdrive[\s\S]*?current:\s*\[([^\]]+)\]/)
                const bs = text.match(/boot_sound[\s\S]*?current:\s*\[([^\]]+)\]/)
                const cm = text.match(/charge_mode[\s\S]*?current:\s*\[([^\]]+)\]/)
                if (po) {
                    const vals = po[1].split(",").map(s => s.trim())
                    const active = vals.find(s => s.startsWith("("))
                    root.panelOverdrive = active === "(1)"
                }
                if (bs) {
                    const vals = bs[1].split(",").map(s => s.trim())
                    const active = vals.find(s => s.startsWith("("))
                    root.bootSound = active === "(1)"
                }
                if (cm) {
                    const vals = cm[1].split(",").map(s => s.trim())
                    const idx = vals.findIndex(s => s.startsWith("("))
                    root.chargeMode = idx >= 0 ? idx : 0
                }
            }
        }
    }

    function poll() {
        profileProc.exec({ command:     ["asusctl", "profile", "get"] })
        gpuProc.exec({ command:         ["supergfxctl", "--get"] })
        gpuPendingProc.exec({ command:  ["supergfxctl", "--pend-action"] })
        batLimitProc.exec({ command:    ["bash", "-c", "cat /sys/class/power_supply/BAT0/charge_control_end_threshold 2>/dev/null || echo 100"] })
        armouryProc.exec({ command:     ["asusctl", "armoury", "list"] })
    }

    Timer {
        // 15 s — and only while the right sidebar is actually open.
        // ROG profile / GPU / battery / charge change on user input,
        // not autonomously, so background polling is wasted.
        interval: 15000
        running: GlobalStates.sidebarRightOpen
        repeat: true
        onTriggered: root.poll()
    }
    Component.onCompleted: root.poll()
}
