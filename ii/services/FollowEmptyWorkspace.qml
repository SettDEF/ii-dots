pragma Singleton
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * Auto-follow workspace orphans.
 *
 * When a window is dragged or moved out of a workspace and that workspace ends
 * up empty on the monitor displaying it, redirect that monitor to follow the
 * window to its new workspace. Same for the last window being closed.
 *
 * Replaces an earlier `~/.scripts/follow-empty-workspace.sh` shell daemon that
 * shelled out via socat + jq + hyprctl on every event. This QML version uses
 * the in-process `Hyprland` event stream and `HyprlandData` snapshots — no
 * subprocesses.
 */
Singleton {
    id: root

    property bool enabled: true
    // Debounce so HyprlandData has time to refresh its cached client list
    // after the same Hyprland raw event we're reacting to.
    property int settleMs: 60
    // Destination workspace id to follow, captured from the event payload.
    property int pendingDest: -1

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!root.enabled) return
            // Only react to deliberate window MOVES, not closes. Apps with
            // many transient sub-windows (Bitwig VST UIs, browser popups,
            // file dialogs) fire `closewindow` constantly; reacting to those
            // yanked focus + warped the cursor to whatever other monitor
            // happened to have an empty workspace.
            if (event.name !== "movewindowv2") return
            const data = (event.data ?? "").toString()
            const wsid = parseInt(data.split(",")[1])
            if (!isNaN(wsid)) root.scheduleCheck(wsid)
        }
    }

    Timer {
        id: settleTimer
        interval: root.settleMs
        repeat: false
        onTriggered: root.checkAndFollow()
    }

    function scheduleCheck(destWs) {
        root.pendingDest = destWs
        settleTimer.restart()
    }

    function checkAndFollow() {
        const targetWs = root.pendingDest
        if (targetWs <= 0) return

        // Only operate on the FOCUSED monitor. Acting on any other monitor's
        // empty workspace yanks the cursor and keyboard focus away — that
        // surprised the user every time a transient window closed elsewhere.
        const focusedMon = Hyprland.focusedMonitor
        if (!focusedMon) return
        const ws = focusedMon.activeWorkspace?.id
        if (ws === undefined || ws === targetWs) return

        const windows  = HyprlandData.windowList || []
        let count = 0
        for (let i = 0; i < windows.length; ++i) {
            if (windows[i].workspace?.id === ws) {
                count++
                if (count > 0) break
            }
        }
        if (count === 0) {
            // Switch the focused monitor's view only. Do NOT dispatch
            // focusmonitor — that would warp the cursor.
            HyprDispatch.run(`workspace ${targetWs}`)
        }
    }
}
