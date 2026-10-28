pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * AwesomeWM-style layouts, per workspace like Awesome's tags.
 *
 * The layouts run inside Hyprland (~/.config/hypr/lua/awesome_layouts.lua):
 * natively where Hyprland has the layout (tile = master, dwindle, max =
 * monocle, so mouse resizing works), as the Lua layout "lua:awesomewm"
 * otherwise. This service only sends commands for the focused workspace and
 * mirrors the state file, so the bar indicator and the OSD show what Hyprland is doing.
 *
 * The old version faked layouts by flipping GLOBAL master/dwindle settings,
 * which re-tiled every workspace on every monitor; this one never touches
 * global state.
 */
Singleton {
    id: root

    // Same names as awful.layout.suit. Order = Super+Y cycle order.
    readonly property var availableLayouts: [
        { id: "tile",       icon: "splitscreen_left",    label: "Tile" },
        { id: "center",     icon: "picture_in_picture_center", label: "Center (floating master)" },
        { id: "tileleft",   icon: "splitscreen_right",   label: "Tile (master right)" },
        { id: "tilebottom", icon: "splitscreen_top",     label: "Tile (master top)" },
        { id: "tiletop",    icon: "splitscreen_bottom",  label: "Tile (master bottom)" },
        { id: "fair",       icon: "grid_view",           label: "Fair" },
        { id: "fairh",      icon: "view_agenda",         label: "Fair (rows)" },
        { id: "spiral",     icon: "cyclone",             label: "Spiral" },
        { id: "dwindle",    icon: "auto_awesome_mosaic", label: "Dwindle" },
        { id: "max",        icon: "fullscreen",          label: "Max" },
        { id: "cornernw",   icon: "north_west",          label: "Corner (top left)" },
        { id: "cornerne",   icon: "north_east",          label: "Corner (top right)" },
        { id: "cornersw",   icon: "south_west",          label: "Corner (bottom left)" },
        { id: "cornerse",   icon: "south_east",          label: "Corner (bottom right)" },
    ]

    readonly property string defaultLayout: "tile"
    /// workspace name -> { suit, mwfact, nmaster, ncol }, as Hyprland saved it.
    property var perWorkspace: ({})

    /// Emitted when the focused workspace's layout changes (drives the OSD).
    signal layoutChanged(string layoutId)

    readonly property string focusedWs: Hyprland.focusedWorkspace?.name ?? ""
    readonly property var current: root.perWorkspace[root.focusedWs]
        ?? { suit: root.defaultLayout, mwfact: 0.5, nmaster: 1, ncol: 1 }

    function currentLayout() { return root.current.suit }
    function layoutFor(wsName) { return (root.perWorkspace[String(wsName)] ?? {}).suit ?? root.defaultLayout }

    /// Any layout command: "suit tile", "next", "mwfact +0.05", "nmaster +1",
    /// "ncol -1", "swapmaster", "reset". Goes through the Lua module's cmd(),
    /// which knows whether the workspace runs a native layout (tile = master,
    /// dwindle, max = monocle) or the Lua one, and speaks the matching dialect.
    // loom (our compositor) runs the same layouts natively: it takes the message as a layoutmsg; its eval
    // only knows hl.config, so the Lua call below did nothing there
    property bool onLoom: false
    Process { running: true; command: ["hyprctl", "version", "-j"]; stdout: StdioCollector { onStreamFinished: { try { root.onLoom = JSON.parse(text).branch === "loom" } catch (e) {} } } }
    function message(msg) {
        if (root.onLoom) { cmdProc.exec(["hyprctl", "dispatch", "layoutmsg", String(msg)]); return }
        cmdProc.exec(["hyprctl", "eval",
            `package.loaded["lua.awesome_layouts"].cmd(${JSON.stringify(String(msg))})`]);
    }
    Process { id: cmdProc }

    function setCurrent(name) { root.message(`suit ${name}`) }
    /// Layout for any workspace, focused or not (the bar's workspace menu).
    function setFor(wsName, suit) {
        // loom: "ws:NAME" names the workspace (the focused one is the default)
        if (root.onLoom) { cmdProc.exec(["hyprctl", "dispatch", "layoutmsg", `ws:${wsName} suit ${suit}`]); return }
        cmdProc.exec(["hyprctl", "eval",
            `package.loaded["lua.awesome_layouts"].apply(${JSON.stringify(String(wsName))}, ${JSON.stringify(suit)})`]);
    }
    function cycle(dir) { root.message(dir < 0 ? "prev" : "next") }

    // ── State mirror ──────────────────────────────────────────────────
    FileView {
        id: stateFile
        path: `${Quickshell.env("HOME")}/.cache/${root.onLoom ? "loom" : "hypr"}-awesome.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const before = root.currentLayout();
                root.perWorkspace = JSON.parse(stateFile.text()) ?? {};
                if (root.currentLayout() !== before) root.layoutChanged(root.currentLayout());
            } catch (e) {}
        }
    }

    // ── IPC: `qs -c ii ipc call layout <fn> [arg]` ────────────────────
    IpcHandler {
        target: "layout"

        function set(name: string): void { root.setCurrent(name) }
        function next(): void { root.cycle(1) }
        function prev(): void { root.cycle(-1) }
        function cycle(dirStr: string): void { root.cycle(parseInt(dirStr || "1", 10) < 0 ? -1 : 1) }
        function get(): string { return root.currentLayout() }
        /// Awesome's Mod+l / Mod+h: master width, e.g. "+0.05" or "0.6".
        function mwfact(arg: string): void { root.message(`mwfact ${arg}`) }
        /// Awesome's Mod+Shift+h / l: number of masters, e.g. "+1".
        function nmaster(arg: string): void { root.message(`nmaster ${arg}`) }
        /// Awesome's Mod+Ctrl+h / l: number of stack columns, e.g. "+1".
        function ncol(arg: string): void { root.message(`ncol ${arg}`) }
        /// Awesome's Mod+Ctrl+Return: focused window becomes the master.
        function swapmaster(): void { root.message("swapmaster") }
        function reset(): void { root.message("reset") }
    }
}
