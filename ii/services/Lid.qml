pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell

/**
 * Lid-close behaviour toggle. When enabled, closing the lid turns off the
 * internal panel if an external monitor is connected (clamshell), otherwise
 * suspends; opening it restores the panel. The actual reaction runs in
 * ~/.config/hypr/hyprland/scripts/lid.sh (bound to the lid switch in Hyprland);
 * this service just owns the on/off state and mirrors it to a plain file the
 * script can read (~/.local/state/quickshell/lid.state).
 */
Singleton {
    id: root
    property bool enabled: false

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (!Persistent.isNewHyprlandInstance)
                root.enabled = Persistent.states.lid.enabled;
            else
                Persistent.states.lid.enabled = root.enabled;
            root.syncMirror();
        }
    }

    function toggle(active = null) {
        root.enabled = (active !== null) ? active : !root.enabled;
        Persistent.states.lid.enabled = root.enabled;
    }

    function syncMirror() {
        Quickshell.execDetached(["bash", "-c",
            `mkdir -p "$HOME/.local/state/quickshell"; echo ${root.enabled ? "on" : "off"} > "$HOME/.local/state/quickshell/lid.state"`]);
    }

    onEnabledChanged: syncMirror()
    Component.onCompleted: syncMirror()
}
