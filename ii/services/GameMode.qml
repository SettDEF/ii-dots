pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs
import qs.modules.common

/**
 * Strips the desktop down for games: Hyprland effects off (old values saved and
 * put back, not `hyprctl reload`, which would drop runtime settings) and the
 * shell's self-redrawing surfaces gated on `active`. Manual, or auto while a
 * game window exists.
 */
Singleton {
    id: root

    readonly property bool manual: Persistent.ready && Persistent.states.gameMode.manual
    readonly property bool auto: Persistent.ready && Persistent.states.gameMode.auto
    readonly property bool gameRunning: HyprlandData.windowList.some(w => root.isGame(w))
    readonly property bool active: root.manual || (root.auto && root.gameRunning)
    // A game filling a screen: popups wait in the list instead of drawing over it.
    readonly property bool fullscreenGame: root.active && HyprlandData.windowList.some(w => w.fullscreen > 0 && root.isGame(w))

    function isGame(w) {
        return /^steam_app_\d+$|^gamescope$/.test(w?.class ?? "")
    }

    // Hyprland's own fullscreen flag: toplevel.wayland is null for XWayland games,
    // so checks built on it never saw a Proton game.
    function fullscreenOn(screen) {
        const ws = Hyprland.monitorFor(screen)?.activeWorkspace?.id
        return HyprlandData.windowList.some(w => w.fullscreen > 0 && w.workspace?.id === ws)
    }

    function toggle() {
        // Turning it off while a game runs has to beat auto, or nothing happens.
        if (root.active) {
            Persistent.states.gameMode.manual = false
            if (root.auto && root.gameRunning) Persistent.states.gameMode.auto = false
        } else {
            Persistent.states.gameMode.manual = true
        }
    }
    function setAuto(on) { Persistent.states.gameMode.auto = on }

    readonly property var gameValues: ({
        "animations:enabled": false,
        "decoration:blur:enabled": false,
        "decoration:shadow:enabled": false,
        "decoration:dim_inactive": false,
        "decoration:rounding": 0,
        "render:direct_scanout": 1,
        "cursor:no_hardware_cursors": 2
    })

    function _lua(values) {
        const tree = {}
        for (const key of Object.keys(values)) {
            const parts = key.split(":")
            let node = tree
            for (let i = 0; i < parts.length - 1; i++) {
                if (!node[parts[i]]) node[parts[i]] = {}
                node = node[parts[i]]
            }
            node[parts[parts.length - 1]] = values[key]
        }
        const lit = v => {
            if (typeof v === "boolean" || typeof v === "number") return String(v)
            if (typeof v === "object") return "{ " + Object.keys(v).map(k => `${k} = ${lit(v[k])}`).join(", ") + " }"
            return `"${String(v).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`
        }
        return `hl.config(${lit(tree)})`
    }

    function _eval(values) {
        root._ownWriteAt = Date.now()
        Quickshell.execDetached(["hyprctl", "eval", root._lua(values)])
    }

    property real _ownWriteAt: 0

    // Persisted, so a shell that dies in game mode can still restore.
    Process {
        id: snapshot
        command: ["bash", "-c", `for k in ${Object.keys(root.gameValues).join(" ")}; do hyprctl -j getoption "$k" | jq -c --arg k "$k" '{($k): (if has("bool") then .bool elif has("int") then .int elif has("float") then .float else .str end)}'; done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const saved = {}
                for (const line of text.split("\n")) {
                    try { Object.assign(saved, JSON.parse(line)) } catch (e) {}
                }
                // Already stripped = we read our own writes; exit falls back to a reload.
                const ours = Object.keys(root.gameValues).every(k => saved[k] === root.gameValues[k])
                if (Object.keys(saved).length > 0 && !ours) Persistent.states.gameMode.saved = JSON.stringify(saved)
                root._eval(root.gameValues)
            }
        }
    }

    function _enter() {
        if (Persistent.states.gameMode.saved.length > 2) root._eval(root.gameValues)
        else snapshot.running = true
        Quickshell.execDetached(["pkill", "-STOP", "-x", "mpvpaper"])
    }

    function _leave() {
        let saved = {}
        try { saved = JSON.parse(Persistent.states.gameMode.saved) } catch (e) {}
        if (Object.keys(saved).length > 0) root._eval(saved)
        else Quickshell.execDetached(["hyprctl", "reload"])
        Persistent.states.gameMode.saved = "{}"
        Quickshell.execDetached(["pkill", "-CONT", "-x", "mpvpaper"])
    }

    property bool _applied: false
    function _sync() {
        if (!Persistent.ready || root.active === root._applied) return
        root._applied = root.active
        root.active ? root._enter() : root._leave()
    }
    onActiveChanged: root._sync()

    // A saved snapshot at start means the last shell died in game mode.
    property bool _booted: false
    function _boot() {
        if (!Persistent.ready || root._booted) return
        root._booted = true
        if (Persistent.states.gameMode.saved.length > 2) {
            root._applied = true
            if (root.active) root._enter()
        }
        root._sync()
    }
    Component.onCompleted: root._boot()
    Connections {
        target: Persistent
        function onReadyChanged() { root._boot() }
    }

    // A config reload restores everything: re-snapshot and strip again.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "configreloaded" || !root._applied) return
            if (Date.now() - root._ownWriteAt < 1500) return
            Persistent.states.gameMode.saved = "{}"
            snapshot.running = true
        }
    }
}
