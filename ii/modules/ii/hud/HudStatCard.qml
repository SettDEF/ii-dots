import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property string label:   ""
    property real   value:   0
    property string unit:    "%"
    property var    history: []
    property color  accent:  Appearance.colors.colPrimary

    Layout.fillWidth: true
    implicitHeight: cardCol.implicitHeight + 16
    radius: Appearance.rounding.large
    color: Appearance.colors.colLayer1
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    ColumnLayout {
        id: cardCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            StyledText {
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer0
                opacity: 0.6
            }
            Item { Layout.fillWidth: true }
            StyledText {
                text: root.value + root.unit
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                color: root.accent
            }
        }

        SparklineCanvas {
            Layout.fillWidth: true
            implicitHeight: 36
            history: root.history
            accent: root.accent
        }
    }
}
