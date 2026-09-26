import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RowLayout {
    id: root
    required property string icon
    required property string label
    required property string value
    /// Lets one row carry meaning the others don't — a reading that is bad
    /// news reads as bad news. Defaults to the normal colour, so every
    /// existing caller is unaffected.
    property color valueColor: Appearance.colors.colOnSurfaceVariant
    property bool emphasized: false
    spacing: 4

    MaterialSymbol {
        text: root.icon
        color: root.valueColor
        iconSize: Appearance.font.pixelSize.large
    }
    StyledText {
        text: root.label
        color: Appearance.colors.colOnSurfaceVariant
    }
    StyledText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
        visible: root.value !== ""
        color: root.valueColor
        font.weight: root.emphasized ? Font.DemiBold : Font.Normal
        text: root.value
    }
}
