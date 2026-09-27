import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property alias materialIcon: icon.text
    property alias text: noticeText.text
    default property alias data: buttonRow.data

    radius: Appearance.rounding.normal
    // A note, not an alert. Filled with the accent it out-shouted every
    // control above it; the tinted icon carries the same meaning.
    color: Appearance.colors.colLayer2
    border.width: 1
    border.color: Appearance.colors.colLayer0Border
    implicitWidth: mainRowLayout.implicitWidth + mainRowLayout.anchors.margins * 2
    implicitHeight: mainRowLayout.implicitHeight + mainRowLayout.anchors.margins * 2

    RowLayout {
        id: mainRowLayout
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        MaterialSymbol {
            id: icon
            Layout.fillWidth: false
            Layout.alignment: Qt.AlignTop
            text: "info"
            iconSize: Appearance.font.pixelSize.huge
            color: Appearance.colors.colPrimary
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            StyledText {
                id: noticeText
                Layout.fillWidth: true
                text: "Notice message"
                color: Appearance.colors.colOnLayer2
                wrapMode: Text.WordWrap
            }

            RowLayout {
                id: buttonRow
                visible: children.length > 0
                Layout.fillWidth: true 
            }
        }
    }
}
