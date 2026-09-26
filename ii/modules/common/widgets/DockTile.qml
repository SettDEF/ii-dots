// An app-icon-shaped tile for a dock widget: same 35px square and squircle as
// the app icons beside it, so widgets sit in the row rather than next to it.
// Each widget picks its own tint and draws its own content.
import qs.services
import qs.modules.common
import Qt5Compat.GraphicalEffects
import QtQuick

Rectangle {
    id: tile
    property color tint: Appearance.colors.colPrimaryContainer
    property string tooltip: ""
    default property alias content: holder.data

    implicitWidth: 35
    implicitHeight: 35
    radius: Appearance.rounding.small
    color: tile.tint

    // clip: true clips to the BOUNDING BOX and ignores radius, so a child
    // reaching the edge — the battery's fill — painted square corners back
    // over the rounded ones. Only a mask rounds child content.
    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: tile.width
            height: tile.height
            radius: tile.radius
        }
    }

    // Publishes to the dock's own tooltip popup: a StyledToolTip here is
    // clipped by the dock surface, which is barely taller than the tile.
    HoverHandler {
        id: hov
        onHoveredChanged: {
            if (hov.hovered) DockTooltip.show(tile, tile.tooltip);
            else DockTooltip.hide(tile);
        }
    }
    Component.onDestruction: DockTooltip.hide(tile)

    Item {
        id: holder
        anchors.fill: parent
    }
}
