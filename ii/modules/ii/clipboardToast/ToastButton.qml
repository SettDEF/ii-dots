// Small circular action button for the clipboard overlay.
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Rectangle {
    id: root
    property string icon: ""
    property string tip: ""
    signal activated

    implicitWidth: 52
    implicitHeight: 52
    radius: width / 2
    // m3 roles have no hover variant, so derive one — same hue, lifted.
    color: ma.containsMouse
        ? Qt.lighter(Appearance.m3colors.m3secondaryContainer, 1.18)
        : Appearance.m3colors.m3secondaryContainer
    Behavior on color { ColorAnimation { duration: 140 } }

    MaterialSymbol {
        anchors.centerIn: parent
        text: root.icon
        iconSize: 22
        color: Appearance.m3colors.m3onSecondaryContainer
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
    StyledToolTip { text: root.tip }
}
