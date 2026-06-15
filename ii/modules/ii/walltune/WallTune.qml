pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

Scope {
    id: root

    Loader {
        active: GlobalStates.wallTuneOpen
        sourceComponent: PanelWindow {
            id: win
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:walltune"
            WlrLayershell.layer: WlrLayer.Overlay
            color: "transparent"

            anchors.top: true
            anchors.right: true
            margins.top: Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut + 8
            margins.right: Appearance.sizes.hyprlandGapsOut + 8

            implicitWidth: 290
            implicitHeight: panel.implicitHeight

            mask: Region { item: panel }

            Component.onCompleted: GlobalFocusGrab.addDismissable(win)
            Component.onDestruction: GlobalFocusGrab.removeDismissable(win)
            Connections {
                target: GlobalFocusGrab
                function onDismissed() { GlobalStates.wallTuneOpen = false }
            }

            WallTuneContent {
                id: panel
                width: parent.width
            }
        }
    }

    // GlobalShortcut moved to panelFamilies/Shortcuts.qml so the keybind
    // stays registered while this panel is smart-unloaded.
}
