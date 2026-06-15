import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property string label:          ""
    property real   value:          0
    property string unit:           "%"
    property var    history:        []
    property color  accent:         Appearance.colors.colPrimary
    property string secondaryLabel: ""
    property real   secondaryValue: 0
    property string secondaryUnit:  ""

    Layout.fillWidth: true
    implicitHeight: detailCol.implicitHeight + 20
    radius: Appearance.rounding.large
    color: Appearance.colors.colLayer1
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    ColumnLayout {
        id: detailCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            StyledText {
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer0
            }
            Item { Layout.fillWidth: true }
            StyledText {
                text: root.value + root.unit
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.Bold
                color: root.accent
            }
            StyledText {
                visible: root.secondaryLabel !== ""
                text: "  |  " + root.secondaryLabel + ": " + root.secondaryValue + root.secondaryUnit
                font.pixelSize: Appearance.font.pixelSize.normal
                color: root.accent
                opacity: 0.7
            }
        }

        SparklineCanvas {
            Layout.fillWidth: true
            implicitHeight: 80
            history: root.history
            accent: root.accent
            filled: true
        }

        // Gauge bar
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 6
            radius: 3
            color: Appearance.colors.colLayer2

            Rectangle {
                width: parent.width * Math.min(root.value / 100, 1)
                height: parent.height
                radius: parent.radius
                color: root.accent
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }
        }
    }
}
