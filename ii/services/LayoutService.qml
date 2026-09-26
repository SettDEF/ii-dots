pragma Singleton
import qs.modules.common
import QtQuick
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    // ── Public API ────────────────────────────────────────────────────
    readonly property var availableLayouts: [
        { id: "tile",       icon: "splitscreen_right",    label: "Tile (master right)" },
        { id: "tileleft",   icon: "splitscreen_left",     label: "Tile (master left)"  },
        { id: "tiletop",    icon: "splitscreen_top",      label: "Tile (master top)"   },
        { id: "tilebottom", icon: "splitscreen_bottom",   label: "Tile (master bottom)"},
        { id: "dwindle",    icon: "calendar_view_week",   label: "Spiral / Dwindle"    },
        { id: "max",        icon: "fullscreen",           label: "Maximised"           },
        { id: "floating",   icon: "drag_pan",             label: "Floating"            },
    ]

    property string defaultLayout: "tile"
    property var perWorkspace: ({})

    // Emitted whenever the layout for the focused workspace changes.
    signal layoutChanged(string layoutId)

    // Currently focused workspace id (-1 = unknown)
    readonly property int focusedWsId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1

    function layoutFor(wsId) {
        const id = String(wsId)
        return root.perWorkspace[id] ?? root.defaultLayout
    }

    function currentLayout() { return root.layoutFor(root.focusedWsId) }

    function setLayout(wsId, name) {
        const id = String(wsId)
        const cur = root.perWorkspace[id] ?? root.defaultLayout
        if (cur === name) { applyLayout(wsId); root.layoutChanged(name); return }
        const next = Object.assign({}, root.perWorkspace)
        next[id] = name
        root.perWorkspace = next
        save()
        applyLayout(wsId)
        if (wsId === root.focusedWsId) root.layoutChanged(name)
    }

    function setCurrent(name) { setLayout(root.focusedWsId, name) }

    function cycle(dir) {
        const list = root.availableLayouts
        const cur = root.currentLayout()
        let i = list.findIndex(l => l.id === cur)
        if (i < 0) i = 0
        const j = (i + dir + list.length) % list.length
        setCurrent(list[j].id)
    }

    // ── Float-mode bookkeeping ────────────────────────────────────────
    // Per-workspace last-applied layout so transitions are detected correctly.
    property var lastApplied: ({})
    // Per-workspace list of window addresses we floated when entering "floating" mode.
    // Only these are returned to tiled when leaving — manually-floated windows stay floating.
    property var floatedByUs: ({})

    function setMasterOrientation(dir) {
        // Was `exec hyprctl keyword ...`, which shells out to a request this
        // Hyprland answers with "unknown request" — silently, exit code 0.
        HyprDispatch.config("general:layout", "master")
        HyprDispatch.config("master:orientation", dir)
    }

    // Float every currently-tiled window on the focused workspace and remember
    // which ones we floated so we can revert exactly those later.
    Process {
        id: enterFloatingProc
        property int targetWs: -1
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.trim() === "" ? [] : text.trim().split(",")
                const next = Object.assign({}, root.floatedByUs)
                next[String(enterFloatingProc.targetWs)] = list
                root.floatedByUs = next
            }
        }
    }

    function enterFloating(wsId) {
        enterFloatingProc.targetWs = wsId
        enterFloatingProc.command = ["bash", "-c",
            `hyprctl -j clients | python3 -c '
import json, sys, subprocess
data = json.load(sys.stdin)
ws = json.loads(subprocess.check_output(["hyprctl","-j","activeworkspace"]))["id"]
addrs = []
for c in data:
    if c.get("workspace",{}).get("id") == ws and not c.get("floating"):
        subprocess.run(["hyprctl","dispatch","setfloating","address:"+c["address"]])
        addrs.append(c["address"])
print(",".join(addrs))
'`]
        enterFloatingProc.running = true
    }

    Process { id: exitFloatingProc }

    function exitFloating(wsId) {
        const key = String(wsId)
        const ours = root.floatedByUs[key] ?? []
        if (ours.length === 0) return
        const arg = ours.join(" ")
        exitFloatingProc.command = ["bash", "-c",
            `for a in ${arg}; do
                state=$(hyprctl -j clients | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['address'] == '$a':
        print('1' if c.get('floating') else '0')
        break
")
                if [ "$state" = "1" ]; then
                    hyprctl dispatch "hl.dsp.window.float({ action = \"set\", window = \"address:$a\" })"
                fi
            done`]
        exitFloatingProc.running = true
        const next = Object.assign({}, root.floatedByUs)
        delete next[key]
        root.floatedByUs = next
    }

    // ── Apply ─────────────────────────────────────────────────────────
    function applyLayout(wsId) {
        if (wsId !== root.focusedWsId) return  // layouts apply to focused ws only
        const name = root.layoutFor(wsId)
        const prev = root.lastApplied[String(wsId)] ?? null

        // No-op if the workspace already has this layout applied. Without this
        // guard, every onFocusedWorkspaceChanged event reissues
        // `hyprctl keyword master:orientation X` (a GLOBAL setting), which
        // forces Hyprland to re-tile every master-layout workspace on every
        // monitor — visible as windows on other monitors swapping positions
        // in a loop whenever you switch workspaces.
        if (prev === name) return

        // Float-mode transitions
        if (prev !== "floating" && name === "floating") enterFloating(wsId)
        else if (prev === "floating" && name !== "floating") exitFloating(wsId)

        switch (name) {
        case "tile":       setMasterOrientation("right");  break
        case "tileleft":   setMasterOrientation("left");   break
        case "tiletop":    setMasterOrientation("top");    break
        case "tilebottom": setMasterOrientation("bottom"); break
        case "dwindle":    HyprDispatch.config("general:layout", "dwindle"); break
        case "max":
            HyprDispatch.config("general:layout", "dwindle")
            HyprDispatch.run("fullscreen 0")
            break
        case "floating":
            // floating geometry is already set by enterFloating; nothing else to do
            break
        }

        const nextApplied = Object.assign({}, root.lastApplied)
        nextApplied[String(wsId)] = name
        root.lastApplied = nextApplied
    }

    // ── Layout application policy ─────────────────────────────────────
    // Layouts are applied ONLY when the user explicitly cycles them
    // (Super+Y → setLayout → applyLayout). We deliberately do NOT reapply
    // on focused-workspace change because every apply path writes global
    // Hyprland state (`master:orientation`, `general:layout`) — which retiles
    // every master-layout workspace on every monitor, producing visible
    // window-swap loops when you bounce focus between workspaces or monitors.
    //
    // Trade-off: a workspace's saved layout is no longer asserted just by
    // visiting it. If you want it enforced, cycle once with Super+Y and it
    // sticks until you change global state elsewhere.
    //
    // The "max" auto-fullscreen on activeToplevelChanged was removed for the
    // same reason — `HyprDispatch.run("fullscreen 0")` fired on every focus
    // change, including focus events that originate on other monitors.

    // ── Persistence ───────────────────────────────────────────────────
    readonly property string statePath: `${Quickshell.env("HOME")}/.local/state/quickshell/user/generated/layouts.json`

    FileView {
        id: stateFile
        path: root.statePath
        onLoaded: {
            try {
                const data = JSON.parse(stateFile.text())
                if (data && typeof data === "object") {
                    if (typeof data.default === "string") root.defaultLayout = data.default
                    if (data.perWorkspace && typeof data.perWorkspace === "object")
                        root.perWorkspace = data.perWorkspace
                }
            } catch (e) {
                console.warn("[LayoutService] state parse failed:", e)
            }
        }
        onLoadFailed: function(err) {
            // No file yet — that's fine, defaults stay.
        }
    }

    function save() {
        const json = JSON.stringify({
            default: root.defaultLayout,
            perWorkspace: root.perWorkspace
        }, null, 2)
        stateFile.setText(json)
    }

    Component.onCompleted: stateFile.reload()

    // ── IPC: `qs ipc call layout <fn> [args]` ─────────────────────────
    IpcHandler {
        target: "layout"

        function set(name: string): void { root.setCurrent(name) }
        function cycle(dirStr: string): void {
            const d = parseInt(dirStr || "1", 10)
            root.cycle(isNaN(d) ? 1 : d)
        }
        function next(): void  { root.cycle(1) }
        function prev(): void  { root.cycle(-1) }
        function get(): string { return root.currentLayout() }
        function reapply(): void { root.applyLayout(root.focusedWsId) }
    }
}
