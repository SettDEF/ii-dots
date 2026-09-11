pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions

/**
 * The colour-filter swatches, shared by the launcher bar and skwd's own
 * toolbar. Multi-select, editing the single selection in WallpaperHub
 * (Wallhaven's fixed palette codes).
 */
Rectangle {
    id: root

    property bool compact: false
    readonly property real dotSize: root.compact ? 15 : 17
    readonly property real dotSizeActive: root.compact ? 19 : 22

    implicitWidth: hueRow.implicitWidth + 12
    implicitHeight: root.compact ? 34 : 40
    radius: height / 2
    color: ColorUtils.transparentize(Appearance.colors.colSurfaceContainerHigh, 0.5)

    Row {
        id: hueRow
        anchors.centerIn: parent
        spacing: 4

        // "All" — clears the colour filter.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: root.dotSize + 3; height: width; radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: WallpaperHub.colors === "" ? Appearance.colors.colPrimary
                                                     : Appearance.colors.colOutlineVariant
            MaterialSymbol {
                anchors.centerIn: parent
                visible: WallpaperHub.colors !== ""
                text: "clear"; iconSize: 10
                color: Appearance.colors.colOnSurfaceVariant
            }
            TapHandler { onTapped: WallpaperHub.colors = "" }
        }

        Repeater {
            model: WallpaperHub.hues
            delegate: Rectangle {
                id: hueDot
                required property var modelData
                readonly property bool active: WallpaperHub.colorSelected(modelData.wh)
                anchors.verticalCenter: parent.verticalCenter
                width: hueDot.active ? root.dotSizeActive : root.dotSize
                height: width
                radius: width / 2
                // Coerce explicitly — Rectangle.color doesn't always pick up a
                // `var`-typed JS string as a colour.
                color: Qt.color(hueDot.modelData.swatch)
                border.width: hueDot.active ? 2 : (hueHov.hovered ? 2 : 0)
                border.color: hueDot.active ? Appearance.colors.colOnSurface
                                            : ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.4)
                Behavior on width { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                HoverHandler { id: hueHov }
                TapHandler { onTapped: WallpaperHub.toggleColor(hueDot.modelData.wh) }
            }
        }
    }
}
