import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

/**
 * One app row in the usage list — icon, name, time, and a bar whose
 * length is proportional to `seconds / maxSeconds`. Click → `clicked()`
 * (the per-app detail view).
 */
Item {
    id: root

    property string appId: ""
    property string displayName: appId
    property int seconds: 0
    property int maxSeconds: 1
    property color accent: Appearance.m3colors.m3primary
    signal clicked()

    implicitHeight: 46

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    Image {
        id: icon
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: 1
        width: 22
        height: 22
        sourceSize.width: 44
        sourceSize.height: 44
        smooth: true
        source: Quickshell.iconPath(root.appId, "application-x-executable")
    }

    StyledText {
        anchors.left: icon.right
        anchors.leftMargin: 9
        anchors.verticalCenter: icon.verticalCenter
        text: root.displayName
        font.family: Appearance.font.family.monospace
        font.pixelSize: Appearance.font.pixelSize.normal
        color: Appearance.colors.colOnLayer0
        elide: Text.ElideRight
    }

    StyledText {
        anchors.right: parent.right
        anchors.verticalCenter: icon.verticalCenter
        text: AppUsage.pretty(root.seconds)
        font.family: Appearance.font.family.monospace
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.Bold
        color: Appearance.colors.colSubtext
    }

    // Proportional usage bar.
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 5
        radius: 2.5
        color: Qt.alpha(Appearance.colors.colOnLayer0, 0.1)
        Rectangle {
            width: parent.width * Math.min(
                root.seconds / Math.max(root.maxSeconds, 1), 1)
            height: parent.height
            radius: parent.radius
            color: root.accent
            Behavior on width {
                NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
            }
        }
    }
}
