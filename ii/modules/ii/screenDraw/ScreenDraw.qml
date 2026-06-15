pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    // ── Fullscreen drawing overlay (triggered by sidebar's icon button) ──
    Loader {
        active: GlobalStates.screenDrawFullOpen
        sourceComponent: PanelWindow {
            id: fullWin
            color: "transparent"
            WlrLayershell.namespace: "quickshell:screenDrawFull"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            exclusionMode: ExclusionMode.Ignore

            anchors { top: true; bottom: true; left: true; right: true }

            Component.onCompleted: GlobalFocusGrab.addDismissable(fullWin)
            Component.onDestruction: GlobalFocusGrab.removeDismissable(fullWin)
            Connections {
                target: GlobalFocusGrab
                function onDismissed() { GlobalStates.screenDrawFullOpen = false }
            }

            ScreenDrawContent {
                anchors.fill: parent
                onCloseRequested: GlobalStates.screenDrawFullOpen = false
            }
        }
    }

    // GlobalShortcuts moved to panelFamilies/Shortcuts.qml.
}
