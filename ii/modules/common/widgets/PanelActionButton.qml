import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Full-width 32px secondary-action row for settings panels (icon + 11px label).
RippleButton {
    id: root
    property string iconName: ""
    property string buttonLabel: ""

    implicitHeight: 32
    colBackground: Appearance.colors.colLayer1

    contentItem: RowLayout {
        anchors.centerIn: parent
        spacing: 5
        MaterialSymbol {
            visible: root.iconName.length > 0
            text: root.iconName
            iconSize: 15
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            visible: root.buttonLabel.length > 0
            text: root.buttonLabel
            font.pixelSize: 11
            color: Appearance.colors.colOnLayer1
        }
    }
}
