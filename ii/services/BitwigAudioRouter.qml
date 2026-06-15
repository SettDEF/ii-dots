pragma Singleton
import qs.services
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire

/**
 * Auto-route the default audio sink based on the focused app.
 *
 * When Bitwig (or any app whose appId matches `targetAppRegex`) becomes the
 * focused window, switch the default sink to the configured device. When
 * focus leaves that app, restore whichever sink was default before the
 * switch. Per-app override avoids the user having to manually flip outputs
 * via the QuickToggle every time they jump between Bitwig and a browser.
 *
 * Stream routing is handled by PipeWire's default-sink mechanism — same
 * pattern as AudioOutputToggle.qml. No subprocesses.
 */
Singleton {
    id: root

    property bool enabled: true
    // Regex of focused-window appId/class that triggers the swap.
    property string targetAppRegex: "bitwig"
    // Substring matched against the candidate sink's description / name.
    property string targetSinkMatch: "Roland"

    // Cached sink to restore when focus leaves the target app.
    property var previousSink: null
    property bool routedForApp: false

    function findSink(needle) {
        const lc = needle.toLowerCase()
        const list = Audio.outputDevices
        for (let i = 0; i < list.length; ++i) {
            const n = list[i]
            const hay = ((n.description || "") + " " + (n.name || "")).toLowerCase()
            if (hay.indexOf(lc) !== -1) return n
        }
        return null
    }

    function appMatches(appId) {
        if (!appId) return false
        try {
            return new RegExp(targetAppRegex, "i").test(appId)
        } catch (e) {
            return false
        }
    }

    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            if (!root.enabled) return
            const tl  = ToplevelManager.activeToplevel
            const app = tl?.appId ?? ""
            const isTarget = root.appMatches(app)

            if (isTarget && !root.routedForApp) {
                const target = root.findSink(root.targetSinkMatch)
                if (!target) return
                const cur = Pipewire.defaultAudioSink
                if (cur && cur.id === target.id) {
                    root.routedForApp = true
                    return
                }
                root.previousSink = cur
                Audio.setDefaultSink(target)
                root.routedForApp = true
            } else if (!isTarget && root.routedForApp) {
                if (root.previousSink) Audio.setDefaultSink(root.previousSink)
                root.previousSink = null
                root.routedForApp = false
            }
        }
    }
}
