pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Wayland

// Standalone toggled panel for ROG power + fan control. Smart-loaded via
// LazyPanelLoader (IllogicalImpulseFamily) and toggled by GlobalStates.rogPowerOpen.
// Top-right popup, dismiss-on-click-away — same pattern as WallTune.
Scope {
    id: root

    Loader {
        active: GlobalStates.rogPowerOpen
        sourceComponent: PanelWindow {
            id: win
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:rogpower"
            WlrLayershell.layer: WlrLayer.Overlay
            color: "transparent"

            anchors.top: true
            anchors.right: true
            margins.top: Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut + 2
            // Listed in PanelStack.order but never registered and never offset,
            // so it always sat at the base position — directly underneath any
            // other panel that happened to be open. It has to take part in the
            // stacking to stop overlapping them.
            margins.right: (Appearance.sizes.hyprlandGapsOut + 8) + PanelStack.offsetFor("rogPower")
            Behavior on margins.right {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            onImplicitWidthChanged: PanelStack.register("rogPower", implicitWidth)

            // Shared width: the capacity maths assumes one slot size, and a
            // 360px panel among 400px ones left a ragged edge anyway.
            implicitWidth: ScreenFit.panelWidth
            implicitHeight: panel.implicitHeight

            mask: Region { item: panel }

            // Both concerns in ONE hook each: declaring Component.onCompleted
            // twice on the same object is not additive, the second silently
            // replaces the first.
            Component.onCompleted: {
                PanelStack.register("rogPower", implicitWidth);
                GlobalFocusGrab.addDismissable(win);
            }
            Component.onDestruction: {
                PanelStack.unregister("rogPower");
                GlobalFocusGrab.removeDismissable(win);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() { GlobalStates.rogPowerOpen = false }
            }

            RogPowerContent {
                id: panel
                width: parent.width
            }
        }
    }
}
