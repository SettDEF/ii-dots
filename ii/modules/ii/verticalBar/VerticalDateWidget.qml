import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Shapes
import QtQuick.Layouts
import qs.modules.ii.bar as Bar

Item { // Full hitbox
    id: root

    implicitHeight: content.implicitHeight
    implicitWidth: Appearance.sizes.verticalBarWidth
    property var dayOfMonth: DateTime.shortDate.split(/[-\/]/)[0]  // What if 🍔murica🦅? good question
    property var monthOfYear: DateTime.shortDate.split(/[-\/]/)[1]

    Item { // Boundaries for date numbers
        id: content
        anchors.centerIn: parent
        // 26x32, not 24x30: at 13px the two numbers were touching the
        // diagonal they are meant to sit either side of.
        implicitWidth: 26
        implicitHeight: 32

        Shape {
            id: diagonalLine
            property real padding: 4
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 1.2
                strokeColor: Appearance.colors.colSubtext
                fillColor: "transparent"
                startX: content.width - diagonalLine.padding
                startY: diagonalLine.padding
                PathLine {
                    x: diagonalLine.padding
                    y: content.height - diagonalLine.padding
                }
            }
        }

        StyledText {
            id: dayText
            anchors {
                top: parent.top
                left: parent.left
            }
            font.pixelSize: 13
            font.family: Appearance.font.family.numbers
            font.features: ({ "tnum": 1 })
            color: Appearance.colors.colOnLayer1
            text: dayOfMonth
        }

        StyledText {
            id: monthText
            anchors {
                bottom: parent.bottom
                right: parent.right
            }
            font.pixelSize: 13
            font.family: Appearance.font.family.numbers
            font.features: ({ "tnum": 1 })
            color: Appearance.colors.colOnLayer1
            text: monthOfYear
        }
    }
}
