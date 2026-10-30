import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: notificationPopup

    PanelWindow {
        id: root
        visible: (Notifications.popupList.length > 0) && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null

        WlrLayershell.namespace: "quickshell:notificationPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0

        // Over a real fullscreen window (mode 2, not maximised) the bar is
        // covered but its reserved strip stays, so the popup floated a bar's
        // height below the corner. Ignore the strip then and sit in the corner.
        readonly property bool overFullscreen: {
            const ws = HyprlandData.activeWorkspace?.id;
            return (HyprlandData.windowList ?? []).some(w => w?.workspace?.id === ws && (w.fullscreen ?? 0) >= 2);
        }
        exclusionMode: root.overFullscreen ? ExclusionMode.Ignore : ExclusionMode.Normal

        // Full height is see-through: without a GPU that draws that (Appearance.noAlpha) it was
        // black below the notifications. Then only the notifications (all of it while the menu is open).
        anchors {
            top: true
            right: true
            bottom: !Appearance.noAlpha || popupMenu.opened || popupMenu.closing
        }
        implicitHeight: Math.max(1, Math.min(listview.contentHeight + 8, screen?.height ?? 720))

        // Clicks only land on the notifications themselves - except while the
        // bell's menu is open, when the whole strip takes them so the menu can
        // be clicked (and a click beside it can dismiss it).
        mask: Region {
            item: (popupMenu.opened || popupMenu.closing) ? fullArea : listview.contentItem
        }
        Item { id: fullArea; anchors.fill: parent }

        color: "transparent"
        implicitWidth: Appearance.sizes.notificationPopupWidth

        NotificationListView {
            id: listview
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
                rightMargin: 4
                topMargin: 4
            }
            implicitWidth: parent.width - Appearance.sizes.elevationMargin * 2
            popup: true
            // Same mute menu as the notification centre.
            Component.onCompleted: contextMenu = popupMenu
        }

        PopupContextMenu { id: popupMenu }
    }
}
