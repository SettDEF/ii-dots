import QtQuick
import qs.modules.common
import qs.modules.common.functions

// A toolbar icon button with its own theme hue (Appearance.colors.colHue*): tinted on hover, filled while toggled.
ToolbarButton {
    id: root
    property color hue: Appearance.colors.colPrimary
    property string symbol: ""
    readonly property bool lit: root.hovered || root.toggled

    implicitWidth: 40
    colBackgroundHover: ColorUtils.transparentize(root.hue, 0.84)
    colBackgroundToggled: ColorUtils.transparentize(root.hue, 0.72)
    colBackgroundToggledHover: ColorUtils.transparentize(root.hue, 0.62)
    colRipple: ColorUtils.transparentize(root.hue, 0.6)
    colRippleToggled: ColorUtils.transparentize(root.hue, 0.5)

    // no padding and a square glyph box: the icon sits in the middle of the round hover
    padding: 0
    contentItem: Item {
        MaterialSymbol {
            anchors.centerIn: parent
            width: iconSize
            height: iconSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: root.symbol
            iconSize: 20
            fill: root.toggled ? 1 : 0
            color: root.lit ? root.hue : Appearance.colors.colOnSurfaceVariant
            Behavior on color { ColorAnimation { duration: 140 } }
        }
    }
}
