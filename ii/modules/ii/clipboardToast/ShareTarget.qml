// One target in the share grid: a circular icon with its label centred beneath.
//
// Proportions follow the share-sheet grid spec — 48px icon, label centred
// below with an 8px gap — rather than the list-row shape this used to be.
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property string icon: ""
    property string label: ""
    signal activated

    implicitWidth: 72
    implicitHeight: iconCircle.height + 8 + labelText.implicitHeight

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Rectangle {
            id: iconCircle
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 48
            implicitHeight: 48
            radius: width / 2
            color: ma.containsMouse
                ? Qt.lighter(Appearance.m3colors.m3secondaryContainer, 1.18)
                : Appearance.m3colors.m3secondaryContainer
            Behavior on color { ColorAnimation { duration: 120 } }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.icon
                iconSize: 22
                color: Appearance.m3colors.m3onSecondaryContainer
            }
        }

        StyledText {
            id: labelText
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            text: root.label
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnLayer1
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
