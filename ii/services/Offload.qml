// Read-only service for ~/.scripts/offload. Polls "offload status" and
// exposes the per-folder state so the QuickToggle can render it. The
// widget never mutates state — link/unlink stays on the CLI where the
// dry-run is visible.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Each entry: { folder, size, state, target }
    // state ∈ "local" | "linked" | "linked-broken" | "foreign-link" | "missing"
    property var folders: []
    property bool mounted: false
    property string mountFree: "—"
    property bool loading: false
    readonly property string home: Quickshell.env("HOME") || `${Quickshell.env("HOME")}`
    readonly property string scriptPath: home + "/.scripts/offload"
    readonly property string mountPath: "/mnt/nuke9100"

    function refresh() {
        loading = true
        // One probe; we glue findmnt + script output together with a
        // sentinel so a single onStreamFinished updates both halves.
        proc.exec({ command: ["bash", "-c",
            "findmnt -nbo SIZE,USED,AVAIL,FSTYPE " + mountPath + " 2>/dev/null" +
            " || echo UNMOUNTED;" +
            " echo '###'; " +
            scriptPath + " status 2>/dev/null"
        ] })
    }

    Component.onCompleted: refresh()

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    function _humanBytes(b) {
        if (!b || b <= 0) return "—"
        const u = ["B","K","M","G","T","P"]
        let i = 0, v = b
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++ }
        return v.toFixed(v < 10 && i > 0 ? 1 : 0) + u[i]
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const t = String(text || "")
                    const sentinelIdx = t.indexOf("###")
                    const mountTxt  = sentinelIdx >= 0 ? t.substring(0, sentinelIdx).trim() : t.trim()
                    const statusTxt = sentinelIdx >= 0 ? t.substring(sentinelIdx + 3).trim() : ""

                    // ── mount half ──
                    if (!mountTxt || mountTxt.indexOf("UNMOUNTED") >= 0) {
                        root.mounted = false
                        root.mountFree = "—"
                    } else {
                        const parts = mountTxt.split(/\s+/)
                        const avail = parseInt(parts[2] || "0", 10)
                        root.mounted = true
                        root.mountFree = root._humanBytes(avail)
                    }

                    // ── folder rows ──
                    const next = []
                    const lines = statusTxt.split("\n")
                    for (let i = 0; i < lines.length; i++) {
                        const ln = lines[i].replace(/\s+$/, "")
                        if (!ln) continue
                        if (ln.indexOf("FOLDER") === 0) continue
                        if (ln.indexOf("Mount:") === 0) continue
                        const parts = ln.split(/\s+/)
                        if (parts.length < 3) continue
                        next.push({
                            folder: parts[0],
                            size:   parts[1],
                            state:  parts[2],
                            target: parts.length > 3 ? parts.slice(3).join(" ") : ""
                        })
                    }
                    root.folders = next
                } catch (e) {
                    console.warn("[Offload] parse error:", e)
                }
                root.loading = false
            }
        }
    }

    function openFolder(folder) {
        Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/" + folder])
    }
    function copyDryRun(folder, action) {
        // action ∈ "link" | "unlink" — copy the CLI command to clipboard
        Quickshell.clipboardText = scriptPath + " " + action + " " + folder + " --go"
    }
    function mount() {
        // Calls `offload wake` which (via the sudoers exception) runs
        // nuke9100-bus.sh enable + mount /mnt/nuke9100 without a prompt.
        Quickshell.execDetached(["bash", "-c", scriptPath + " wake"])
    }
    function park() {
        Quickshell.execDetached(["bash", "-c", scriptPath + " park"])
    }
}
