// Small circular prev/next button for the cheatsheet search bar.
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

Rectangle {
    id: root
    property string icon: ""
    signal activated

    implicitWidth: 26
    implicitHeight: 26
    radius: width / 2
    color: ma.containsMouse ? Appearance.colors.colLayer2Hover : ColorUtils.transparentize(Appearance.colors.colLayer2Hover)
    Behavior on color { ColorAnimation { duration: 120 } }

    MaterialSymbol {
        anchors.centerIn: parent
        text: root.icon
        iconSize: 17
        color: Appearance.colors.colOnLayer1
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
