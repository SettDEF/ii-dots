import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// A round icon button for the toast's header pill: pin, pop out, share, close.
Rectangle {
    id: root
    property string icon
    property string tip
    property bool on: false
    signal hit()
    implicitWidth: 28
    implicitHeight: 28
    radius: 14
    color: root.on ? Appearance.colors.colSecondaryContainer : ma.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }
    MaterialSymbol {
        anchors.centerIn: parent
        text: root.icon
        iconSize: 17
        fill: root.on ? 1 : 0
        color: root.on ? Appearance.colors.colOnSecondaryContainer : ma.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.hit()
    }
    StyledToolTip { text: root.tip; extraVisibleCondition: false; alternativeVisibleCondition: ma.containsMouse && root.tip !== "" }
}
