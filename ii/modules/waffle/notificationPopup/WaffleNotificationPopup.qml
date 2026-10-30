import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.modules.waffle.notificationCenter

Scope {
    id: notificationPopup

    PanelWindow {
        id: root
        visible: (Notifications.popupList.length > 0) && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null

        WlrLayershell.namespace: "quickshell:notificationPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0

        // Full height is see-through: without a GPU that draws that (Looks.noAlpha) it was black
        // above the notifications. Then the window is only the notifications.
        anchors {
            top: !Looks.noAlpha
            right: true
            bottom: true
        }
        implicitHeight: Math.max(1, Math.min(listview.contentHeight + listview.topMargin + listview.bottomMargin, screen?.height ?? 720))

        mask: Region {
            item: listview.contentItem
        }

        color: "transparent"
        implicitWidth: listview.implicitWidth

        WListView {
            id: listview
            anchors {
                bottom: parent.bottom
                right: parent.right
                left: parent.left
            }
            leftMargin: Looks.noAlpha ? 0 : 16
            rightMargin: Looks.noAlpha ? 0 : 16
            topMargin: Looks.noAlpha ? 0 : 16
            bottomMargin: Looks.noAlpha ? 0 : 16

            height: Math.min(contentItem.height + topMargin + bottomMargin, parent.height)
            width: parent.width - Appearance.sizes.elevationMargin * 2
            
            implicitWidth: 396
            spacing: Looks.noAlpha ? 0 : 12

            model: ScriptModel {
                values: Notifications.popupList
            }
            delegate: WSingleNotification {
                required property var modelData
                notification: modelData
                width: ListView.view.width - ListView.view.leftMargin - ListView.view.rightMargin
            }
        }
    }
}
