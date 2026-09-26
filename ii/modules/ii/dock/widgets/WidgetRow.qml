import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Label/value line; monospace so ticking figures don't shift the row.
RowLayout {
    id: root
    property string label: ""
    property string value: ""
    property color valueColor: Appearance.colors.colOnLayer0

    Layout.fillWidth: true
    spacing: 8

    StyledText {
        Layout.fillWidth: true
        text: root.label
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        elide: Text.ElideRight
    }
    StyledText {
        text: root.value
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.family: Appearance.font.family.monospace
        color: root.valueColor
    }
}
