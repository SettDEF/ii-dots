import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Rounded "chip" tab with optional icon + label, active/hover states.
// Replaces the duplicated chip patterns in HudSubTabButton, MonitorsDialog
// PresetChip, and ShelfSubTabBar delegate.
//
// Two visual flavors via `accent`:
//   "primary"   → m3primaryContainer / m3onPrimaryContainer  (HUD sub tabs)
//   "secondary" → m3secondaryContainer / m3onSecondaryContainer (default)
Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property bool active: false
    property string accent: "secondary"        // "primary" | "secondary"
    property bool showBorder: false             // 1px border when inactive
    property bool dimInactive: false            // fade icon/label when not active
    property color inactiveColor: "transparent" // fill when not active and not hovered
    property real horizontalPadding: 14
    property real verticalPadding: 8
    property real iconSize: Appearance.font.pixelSize.normal
    property real labelSize: Appearance.font.pixelSize.small

    signal triggered()

    readonly property color _activeBg: accent === "primary"
        ? Appearance.colors.colPrimaryContainer
        : Appearance.colors.colSecondaryContainer
    readonly property color _activeFg: accent === "primary"
        ? Appearance.m3colors.m3onPrimaryContainer
        : Appearance.m3colors.m3onSecondaryContainer

    implicitWidth: pillContent.implicitWidth + horizontalPadding * 2
    implicitHeight: pillContent.implicitHeight + verticalPadding * 2
    radius: Appearance.rounding.full

    color: active
        ? _activeBg
        : (hov.hovered ? Appearance.colors.colLayer2Hover : inactiveColor)
    border.width: (!active && showBorder) ? 1 : 0
    border.color: Appearance.colors.colLayer0Border

    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(root) }

    HoverHandler { id: hov }
    TapHandler { onTapped: root.triggered() }

    RowLayout {
        id: pillContent
        anchors.centerIn: parent
        spacing: 5

        MaterialSymbol {
            visible: root.icon.length > 0
            text: root.icon
            iconSize: root.iconSize
            color: root.active ? root._activeFg : Appearance.colors.colOnLayer0
            opacity: (!root.active && root.dimInactive) ? 0.45 : 1
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
        StyledText {
            visible: root.label.length > 0
            text: root.label
            font.pixelSize: root.labelSize
            font.weight: root.active ? Font.Medium : Font.Normal
            color: root.active ? root._activeFg : Appearance.colors.colOnLayer0
            opacity: (!root.active && root.dimInactive) ? 0.55 : 1
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
    }
}
