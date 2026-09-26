pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common

/**
 * ROG Flow Z13 (GZ302EA) hardware state and control.
 *
 * Two kinds of state live here:
 *   - settings (profiles, charge limit): read on demand and after every change
 *   - telemetry (temps, fans, power, battery): read from sysfs through
 *     FileViews - no process per poll - and only while something watches.
 *
 * Panels hold a watcher while they exist (watchers++ / watchers--). Nothing
 * polls for an audience of nobody.
 */
Singleton {
    id: root

    // ── Watchers ─────────────────────────────────────────────────────────────
    property int watchers: 0
    readonly property bool live: root.watchers > 0 || GlobalStates.sidebarRightOpen

    // ── Profiles ─────────────────────────────────────────────────────────────
    readonly property var profiles: ["Quiet", "Balanced", "Performance"]
    property string profile: "Balanced"          // active now
    property string acProfile: ""                // applied when the charger connects
    property string batteryProfile: ""           // applied when it disconnects

    function setProfile(p) {
        root.profile = p
        root._run(["asusctl", "profile", "set", p])
    }
    function setAcProfile(p) {
        Persistent.states.rog.chargerProfile = p
        root._applied = ""
        root._chargerTick()
    }
    function setBatteryProfile(p) {
        root.batteryProfile = p
        if (!root.onAc) root.profile = p
        root._run(["asusctl", "profile", "set", "--battery", p])
    }
    function nextProfile() { root._run(["asusctl", "profile", "next"]) }


    // ── On the charger ───────────────────────────────────────────────────────
    // The charger is weak, so the charger profile is only the most it may use:
    // it steps down while the battery is low, or when the battery drains despite
    // being plugged in. Applied only when the answer changes, so a manual pick stays.
    readonly property string chargerMax: Persistent.states.rog.chargerProfile
    property int _drain: 0
    property int _cap: 2
    property real _capAt: 0
    property string _applied: ""

    function _chargerTick() {
        if (!root.onAc || capacityFile.value <= 0 || root.batteryStatus === "") {
            root._applied = ""
            root._cap = 2
            return
        }
        root._drain = root.batteryStatus === "Discharging" ? root._drain + 1 : 0
        if (root._drain >= 4) {
            root._cap = Math.max(0, root.profiles.indexOf(root.profile) - 1)
            root._capAt = Date.now()
            root._drain = 0
        } else if (Date.now() - root._capAt > 600000) {
            root._cap = 2
        }
        const pct = root.batteryPercent
        const level = Math.min(root.profiles.indexOf(root.chargerMax), pct < 20 ? 0 : pct < 40 ? 1 : 2, root._cap)
        const target = root.profiles[Math.max(0, level)]
        if (target === root._applied) return
        root._applied = target
        root.acProfile = target
        root.profile = target
        root._run(["asusctl", "profile", "set", "--ac", target])
    }

    Timer {
        interval: 5000
        repeat: true
        running: Persistent.ready
        onTriggered: {
            if (!root.live) for (const f of [acFile, capacityFile, statusFile]) f.reload()
            root._chargerTick()
        }
    }

    // ── GPU mode ─────────────────────────────────────────────────────────────
    // The GZ302EA has no discrete GPU; supergfxctl only ever reports Integrated.
    property string gpuMode: "Integrated"
    property string gpuPendingAction: ""
    readonly property bool hasDiscreteGpu: false
    function setGpuMode(m) { root._run(["supergfxctl", "--mode", m]) }

    // ── Battery ──────────────────────────────────────────────────────────────
    property int batteryLimit: 100               // 20..100
    function setBatteryLimit(v) {
        const clamped = Math.max(20, Math.min(100, Math.round(v)))
        root.batteryLimit = clamped
        root._run(["asusctl", "battery", "limit", String(clamped)])
    }
    /// Charge once to `percent` (default 100), then fall back to the limit.
    function chargeOnce(percent) {
        root._run(["asusctl", "battery", "oneshot", String(percent ?? 100)])
    }

    readonly property int batteryPercent: Math.round(capacityFile.value)
    property string batteryStatus: ""
    readonly property bool onAc: acFile.value > 0
    /// Present capacity against design, as a percentage. 58.1 of 70.0 Wh = 83.
    readonly property int batteryHealth: designFile.value > 0
        ? Math.round(fullFile.value / designFile.value * 100) : -1
    readonly property real batteryFullWh: fullFile.value / 1e6
    readonly property real batteryDesignWh: designFile.value / 1e6
    /// Firmware reports 0 when it does not count; -1 means "not known".
    readonly property int batteryCycles: cyclesFile.value > 0 ? Math.round(cyclesFile.value) : -1
    readonly property real batteryWatts: batPowerFile.value / 1e6

    // ── Firmware toggles (read-only here until the privileged helper grows
    //    them; `asusctl armoury` exposes nothing on this kernel) ──────────────
    readonly property bool panelOverdrive: panelOdFile.value > 0
    readonly property bool bootSound: bootSoundFile.value > 0
    readonly property int chargeMode: Math.round(chargeModeFile.value)
    readonly property bool chargeModeWritable: false
    function setPanelOverdrive(v) { console.log("[Rog] panel overdrive needs the privileged helper") }
    function setBootSound(v) { console.log("[Rog] boot sound needs the privileged helper") }
    function setChargeMode(v) { console.log("[Rog] charge_mode is read-only on this machine") }

    // ── Telemetry ────────────────────────────────────────────────────────────
    readonly property int cpuTemp: Math.round(cpuTempFile.value / 1000)
    readonly property int gpuTemp: Math.round(gpuTempFile.value / 1000)
    readonly property int fan1Rpm: Math.round(fan1File.value)
    readonly property int fan2Rpm: Math.round(fan2File.value)
    readonly property real apuWatts: apuPowerFile.value / 1e6

    // hwmon indices move between boots, so the directories are resolved by
    // name once, then read by path.
    property string hwCpu: ""
    property string hwGpu: ""
    property string hwFans: ""

    Process {
        id: hwmonResolver
        running: true
        command: ["bash", "-c", "for h in /sys/class/hwmon/hwmon*; do echo \"$(cat $h/name)\t$h\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.split("\n")) {
                    const [name, path] = line.split("\t")
                    if (name === "k10temp") root.hwCpu = path
                    else if (name === "amdgpu") root.hwGpu = path
                    else if (name === "asus") root.hwFans = path
                }
            }
        }
    }

    component SysValue: FileView {
        property real value: 0
        blockLoading: false
        printErrors: false
        onLoaded: {
            const v = parseFloat(text())
            if (!isNaN(v)) value = v
        }
    }

    readonly property string plat: "/sys/devices/platform/asus-nb-wmi"
    readonly property string bat: "/sys/class/power_supply/BAT0"

    SysValue { id: cpuTempFile;    path: root.hwCpu  ? root.hwCpu  + "/temp1_input" : "" }
    SysValue { id: gpuTempFile;    path: root.hwGpu  ? root.hwGpu  + "/temp1_input" : "" }
    SysValue { id: apuPowerFile;   path: root.hwGpu  ? root.hwGpu  + "/power1_average" : "" }
    SysValue { id: fan1File;       path: root.hwFans ? root.hwFans + "/fan1_input" : "" }
    SysValue { id: fan2File;       path: root.hwFans ? root.hwFans + "/fan2_input" : "" }
    SysValue { id: capacityFile;   path: root.bat + "/capacity" }
    SysValue { id: batPowerFile;   path: root.bat + "/power_now" }
    SysValue { id: fullFile;       path: root.bat + "/energy_full" }
    SysValue { id: designFile;     path: root.bat + "/energy_full_design" }
    SysValue { id: cyclesFile;     path: root.bat + "/cycle_count" }
    SysValue { id: limitFile;      path: root.bat + "/charge_control_end_threshold"
                                   onValueChanged: if (value >= 20) root.batteryLimit = Math.round(value) }
    SysValue { id: acFile;         path: "/sys/class/power_supply/AC0/online" }
    SysValue { id: panelOdFile;    path: root.plat + "/panel_od" }
    SysValue { id: bootSoundFile;  path: root.plat + "/boot_sound" }
    SysValue { id: chargeModeFile; path: root.plat + "/charge_mode" }
    FileView {
        id: statusFile
        path: root.bat + "/status"
        printErrors: false
        onLoaded: root.batteryStatus = text().trim()
    }
    FileView {
        id: platformProfileFile
        path: "/sys/firmware/acpi/platform_profile"
        printErrors: false
        // "performance" -> "Performance". Changes on AC transitions by itself,
        // so it is re-read with the telemetry rather than only after a set.
        onLoaded: {
            const t = text().trim()
            if (t.length > 0) root.profile = t.charAt(0).toUpperCase() + t.slice(1)
        }
    }

    readonly property var _fast: [cpuTempFile, gpuTempFile, apuPowerFile, fan1File, fan2File,
                                  batPowerFile, capacityFile, acFile, statusFile, platformProfileFile]
    readonly property var _slow: [fullFile, designFile, cyclesFile, limitFile,
                                  panelOdFile, bootSoundFile, chargeModeFile]

    Timer {
        interval: 2000
        repeat: true
        running: root.live
        triggeredOnStart: true
        onTriggered: { for (const f of root._fast) f.reload() }
    }
    Timer {
        interval: 30000
        repeat: true
        running: root.live
        triggeredOnStart: true
        onTriggered: {
            for (const f of root._slow) f.reload()
            root.readProfiles()
        }
    }

    // ── asusctl ──────────────────────────────────────────────────────────────
    Process {
        id: profileProc
        command: ["asusctl", "profile", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const a = text.match(/Active profile:\s*(\w+)/)
                const ac = text.match(/AC profile\s+(\w+)/)
                const b = text.match(/Battery profile\s+(\w+)/)
                if (a) root.profile = a[1]
                if (ac) root.acProfile = ac[1]
                if (b) root.batteryProfile = b[1]
            }
        }
    }
    function readProfiles() { if (!profileProc.running) profileProc.running = true }

    // Commands queue so a quick sequence of changes cannot drop one on the
    // floor while the previous is still running.
    property var _queue: []
    function _run(cmd) {
        root._queue = root._queue.concat([cmd])
        root._pump()
    }
    function _pump() {
        if (cmdProc.running || root._queue.length === 0) return
        cmdProc.command = root._queue[0]
        root._queue = root._queue.slice(1)
        cmdProc.running = true
    }
    Process {
        id: cmdProc
        onRunningChanged: if (!running) {
            root._pump()
            if (root._queue.length === 0) settle.restart()
        }
    }
    // Re-read what a change touched, once it has landed.
    Timer {
        id: settle
        interval: 400
        onTriggered: {
            root.readProfiles()
            limitFile.reload()
            platformProfileFile.reload()
        }
    }

    /// Kept for callers that ask for a refresh.
    function poll() {
        root.readProfiles()
        for (const f of root._fast) f.reload()
        for (const f of root._slow) f.reload()
    }

    Component.onCompleted: root.poll()
}
