pragma ComponentBehavior: Bound

import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell

StyledListView { // Scrollable window
    id: root
    property bool popup: false
    // A shared PopupContextMenu (mounted by the container, e.g. NotificationList)
    // that group delegates open for per-app mute options. Null in the toast
    // popup, where the delegate falls back to a plain mute toggle.
    property var contextMenu: null

    spacing: 3
    // popups: the cards below a new one follow its growing height (NotificationGroup.appear) instead of
    // one move with the height it had when it came, which left a gap and snapped later
    Transition { id: noMove }
    Component.onCompleted: if (root.popup) root.addDisplaced = noMove
    // "off": no fade either
    animateAppearance: !root.popup || Notifications.popupAnimation !== "off"

    model: ScriptModel {
        values: root.popup ? Notifications.popupAppNameList : Notifications.appNameList
    }
    delegate: NotificationGroup {
        required property int index
        required property var modelData
        popup: root.popup
        width: ListView.view.width // https://doc.qt.io/qt-6/qml-qtquick-listview.html
        notificationGroup: popup ? 
            Notifications.popupGroupsByAppName[modelData] :
            Notifications.groupsByAppName[modelData]
    }
}
