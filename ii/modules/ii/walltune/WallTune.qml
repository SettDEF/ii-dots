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

            // Esc closes. This used to come free with the focus grab; without it
            // the panel would only be closable from its own buttons.
            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: GlobalStates.wallTuneOpen = false
            }
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:walltune"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors.top: true
            anchors.right: true
            margins.top: Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut + 2
            // This panel is listed in PanelStack.order but never registered or
            // applied an offset, so it sat at the base position and every other
            // panel opened directly on top of it. It keeps its own chrome —
            // WallTuneContent already draws a card — but it has to take part in
            // the stacking like everything else.
            margins.right: (Appearance.sizes.hyprlandGapsOut + 8) + PanelStack.offsetFor("walltune")
            Behavior on margins.right {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            onImplicitWidthChanged: PanelStack.register("walltune", implicitWidth)
            Component.onCompleted: PanelStack.register("walltune", implicitWidth)
            Component.onDestruction: PanelStack.unregister("walltune")

            // Shared width AND height. Sizing to content left this panel 640px
            // tall next to 889px neighbours, and a row of panels at different
            // heights reads as broken rather than as compact — the same reason
            // StackedSettingsPanel takes the full available height.
            // Wider than a standard panel: this one carries a section rail as
            // well as its content. PanelStack is told the real width, so it
            // still works out how many panels fit beside each other.
            implicitWidth: Math.min(ScreenFit.panelWidth + 190,
                                    Math.max(ScreenFit.panelWidth, win.screen.width * 0.42))
            implicitHeight: ScreenFit.maxHeight(win)

            mask: Region { item: panel }

            WallTuneContent {
                id: panel
                width: parent.width
                // Fill the taller window rather than floating at its natural
                // height inside it, so the card matches its neighbours.
                height: parent.height
            }
        }
    }

    // GlobalShortcut moved to panelFamilies/Shortcuts.qml so the keybind
    // stays registered while this panel is smart-unloaded.
}
