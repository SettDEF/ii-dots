import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// One cell of a popup's tile grid: caption on top, reading below, or custom
// children instead. Fixed width, because StyledPopup only clamps its left
// edge — a grid that grows with its text gets clipped off-screen near the
// right of the display.
Rectangle {
    id: root
    property string icon: ""
    property string label: ""
    property string value: ""
    property color valueColor: Appearance.colors.colOnSurfaceVariant
    property bool wide: false
    default property alias content: inner.data

    readonly property int unit: 94
    Layout.preferredWidth: root.wide ? root.unit * 2 + 6 : root.unit
    Layout.fillWidth: root.wide
    implicitHeight: inner.implicitHeight + 16
    radius: Appearance.rounding.small
    color: Appearance.colors.colLayer1

    ColumnLayout {
        id: inner
        anchors {
            left: parent.left; right: parent.right
            verticalCenter: parent.verticalCenter
            margins: 8
        }
        spacing: 1

        // Hidden when empty so a tile given custom children is sized only by them.
        RowLayout {
            visible: root.icon !== "" || root.label !== ""
            Layout.fillWidth: true
            spacing: 4
            MaterialSymbol {
                visible: root.icon !== ""
                text: root.icon
                iconSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }
        StyledText {
            visible: root.value !== ""
            Layout.fillWidth: true
            text: root.value
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: root.valueColor
            elide: Text.ElideRight
        }
    }
}
