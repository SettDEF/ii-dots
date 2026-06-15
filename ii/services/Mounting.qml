// Lightweight drive-mounting service. Polls `lsblk` periodically and
// exposes mountable block devices + mount/unmount actions via udisksctl.
//
// Doesn't require root — udisks handles policy via PolicyKit.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs


Singleton {
    id: root

    // List of devices: { name, path, label, fsType, size, mountPoint, mounted, removable }
    property var devices: []
    // Number of currently-mounted user drives (excluding root + system mounts).
    readonly property int mountedCount: devices.filter(d => d.mounted).length
    property bool loading: false

    // Drives that are typically system-mounts (boot, swap, root) — hide them.
    function _isSystemMount(mp) {
        if (!mp) return false
        return mp === "/" || mp.startsWith("/boot") || mp.startsWith("/var")
            || mp.startsWith("/sys") || mp.startsWith("/proc") || mp === "[SWAP]"
    }

    function refresh() {
        loading = true
        lsblkProc.running = true
    }

    function mountDevice(devPath)   { mountProc.exec({ command: ["udisksctl", "mount",   "-b", devPath] }) }
    function unmountDevice(devPath) { mountProc.exec({ command: ["udisksctl", "unmount", "-b", devPath] }) }
    function powerOff(devPath)      { mountProc.exec({ command: ["udisksctl", "power-off", "-b", devPath] }) }
    function openInFileManager(mountPoint) {
        if (mountPoint) Quickshell.execDetached(["xdg-open", mountPoint])
    }
    function copyPath(text) { Quickshell.clipboardText = text || "" }

    // ── Per-device live stats (usage + temperature). Polled every 4 s
    // for the device the user has open in the popup.
    // statsByPath[devPath] = { used, total, free, percent, temp, tempPath }
    property var statsByPath: ({})
    property string statsTargetPath: ""   // set by UI to focus polling on one device
    property string statsTargetMountPoint: ""

    function setStatsTarget(path, mountPoint) {
        statsTargetPath = path || ""
        statsTargetMountPoint = mountPoint || ""
        if (statsTargetPath) statsProc.fetch(statsTargetPath, statsTargetMountPoint)
    }

    Process {
        id: statsProc
        property string activePath: ""
        // Use exec() (one-shot) rather than mutating `command` + toggling
        // `running` — the latter is a no-op on Quickshell.Io.Process when
        // it's already running, which silently broke periodic re-polls.
        function fetch(path, mountPoint) {
            activePath = path
            const sh =
                `path='${path}'; mp='${mountPoint || ""}'; ` +
                `if [ -n "$mp" ]; then ` +
                `  df -B1 --output=size,used,avail,pcent "$mp" 2>/dev/null | tail -1; ` +
                `else echo "0 0 0 0%"; fi; ` +
                // Find a hwmon temp for this device (NVMe controller / SATA SCT).
                `name=$(basename "$path" | sed 's/p[0-9]*$//'); ` +
                `t=""; ` +
                `for h in /sys/block/$name/device/hwmon*/temp1_input ` +
                `         /sys/class/nvme/$name/hwmon*/temp*_input; do ` +
                `  [ -f "$h" ] && { read v <"$h"; t="$v"; break; }; ` +
                `done; ` +
                `echo "TEMP=$t"`
            exec({ command: ["bash", "-c", sh] })
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (text || "").trim().split("\n").filter(l => l.length)
                if (lines.length === 0) return
                const dfLine = lines[0]   // "<size> <used> <avail> <pcent>"
                const parts = dfLine.trim().split(/\s+/)
                const total = parseInt(parts[0]) || 0
                const used  = parseInt(parts[1]) || 0
                const free  = parseInt(parts[2]) || 0
                const pct   = parseFloat((parts[3] || "0%").replace("%","")) || 0

                let temp = NaN
                for (const l of lines) {
                    const m = l.match(/^TEMP=(\d+)/)
                    if (m) { temp = parseInt(m[1]) / 1000.0; break }
                }

                const next = Object.assign({}, root.statsByPath)
                next[statsProc.activePath] = {
                    total, used, free, percent: pct,
                    temp: isFinite(temp) ? temp : NaN
                }
                root.statsByPath = next
            }
        }
    }
    Timer {
        interval: 4000; repeat: true
        running: root.statsTargetPath !== ""
        onTriggered: statsProc.fetch(root.statsTargetPath, root.statsTargetMountPoint)
    }

    Process {
        id: lsblkProc
        command: ["lsblk", "-J", "-o", "NAME,PATH,LABEL,FSTYPE,SIZE,MOUNTPOINT,RM"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false
                try {
                    const data = JSON.parse(text)
                    const out = []
                    function walk(node) {
                        // Only consider real partitions / disks with a filesystem.
                        if (node.fstype && node.fstype !== "swap"
                                && !root._isSystemMount(node.mountpoint)) {
                            out.push({
                                name: node.name,
                                path: node.path ?? ("/dev/" + node.name),
                                label: node.label ?? "",
                                fsType: node.fstype,
                                size: node.size ?? "",
                                mountPoint: node.mountpoint ?? "",
                                mounted: !!node.mountpoint,
                                removable: node.rm === true || node.rm === "1"
                            })
                        }
                        if (node.children) for (const c of node.children) walk(c)
                    }
                    for (const d of (data.blockdevices ?? [])) walk(d)
                    root.devices = out
                } catch (e) {
                    console.error("[Mounting] parse error:", e)
                }
            }
        }
    }

    // Refresh after any mount/unmount completes.
    Process {
        id: mountProc
        onExited: (code) => Qt.callLater(root.refresh)
    }

    // Lightweight polling — every 30 s.  Drive list rarely changes and
    // every refresh spawns lsblk + a parse.  Users open the panel
    // explicitly when they want the latest, so a long passive poll is
    // plenty.
    // Poll only while the right sidebar is open AND a stats target is
    // active (i.e. the user has expanded a drive's panel).  When the
    // sidebar is closed, lsblk doesn't run at all.
    Timer {
        interval: 30000
        running: GlobalStates.sidebarRightOpen
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
