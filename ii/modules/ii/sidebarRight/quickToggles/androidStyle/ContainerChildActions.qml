// Reusable edit-mode action overlay for a single container-child cell.
//
// Used by both layouts that render container children (grid for the rog
// tile, vertical list for sliders / phone / etc.). Exposes three actions:
//   • Move backward (← / chevron_left  on grid, expand_less on list)
//   • Move forward  (→ / chevron_right on grid, expand_more on list)
//   • Extract       (↗ / open_in_new)            — pull this child out of
//                                                  the container and place
//                                                  it as a standalone tile.
//
// `style` switches between "grid" (overlay corners, only visible while
// editing, full-cell coverage) and "row" (inline at the right of a list
// row). Buttons fade in only while the cell is hovered, so the rich child
// content stays uncluttered in resting state.
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    // ── Public API ────────────────────────────────────────────────────────
    property int index: 0
    property int totalCount: 1
    property string style: "grid"       // "grid" | "row"
    property bool revealOnHover: true   // false → always visible (e.g. list)
    property bool parentHovered: false  // wire from cell's HoverHandler

    property bool allowReorder: true

    signal moveBack()
    signal moveForward()
    signal extract()

    readonly property bool _canBack:    allowReorder && index > 0
    readonly property bool _canForward: allowReorder && index < totalCount - 1
    readonly property bool _shown: revealOnHover ? parentHovered : true

    // Smooth in/out for grid style
    opacity: _shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    // ─────────────────────────────────────────────────────────────────────
    // Grid style: floating chips pinned to the cell's corners.
    // ─────────────────────────────────────────────────────────────────────
    Item {
        id: gridLayout
        anchors.fill: parent
        visible: root.style === "grid"

        // ↗ Extract (top-right) — primary action, tinted.
        ActionChip {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 4
            icon: "open_in_new"
            tint: Appearance.colors.colPrimary
            onActivated: root.extract()
            tooltipText: qsTr("Extract as standalone")
        }
        // ← Move backward (bottom-left)
        ActionChip {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.margins: 4
            icon: "chevron_left"
            enabled: root._canBack
            onActivated: root.moveBack()
            tooltipText: qsTr("Move backward")
        }
        // → Move forward (bottom-right)
        ActionChip {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: 4
            icon: "chevron_right"
            enabled: root._canForward
            onActivated: root.moveForward()
            tooltipText: qsTr("Move forward")
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Row style: inline three-button strip (used by list-style child rows).
    // ─────────────────────────────────────────────────────────────────────
    RowLayout {
        id: rowLayout
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        visible: root.style === "row"

        ActionChip {
            icon: "expand_less"
            enabled: root._canBack
            onActivated: root.moveBack()
            tooltipText: qsTr("Move up")
        }
        ActionChip {
            icon: "expand_more"
            enabled: root._canForward
            onActivated: root.moveForward()
            tooltipText: qsTr("Move down")
        }
        ActionChip {
            icon: "open_in_new"
            tint: Appearance.colors.colPrimary
            onActivated: root.extract()
            tooltipText: qsTr("Extract as standalone")
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // ActionChip — single 22 px circular icon button. Shared local widget
    // so both layouts get identical sizing, hover/disabled colour treatment
    // and tooltip behaviour without re-inlining a Rectangle every time.
    // ─────────────────────────────────────────────────────────────────────
    component ActionChip: Rectangle {
        id: chip
        property string icon: ""
        property color tint: Appearance.colors.colOnLayer2
        property bool enabled: true
        property string tooltipText: ""
        signal activated()

        width: 22
        height: 22
        radius: 11
        color: root.style === "row" ? "transparent" : Appearance.colors.colLayer1
        border.color: chipMa.containsMouse && enabled ? tint : "transparent"
        border.width: 1.5
        opacity: enabled ? 1 : 0.4
        Behavior on border.color { ColorAnimation { duration: 120 } }

        // MouseArea (not TapHandler) so the press is *consumed* — a parent
        // tile's GroupButton.buttonMouseArea would otherwise race for the
        // same click and also fire its onClicked, which would
        // OpenContainerState.toggle(…) the drawer shut the instant the chip
        // was tapped. MouseArea event delivery is depth-first: the chip
        // accepts the press, the outer MouseArea never sees it.
        MouseArea {
            id: chipMa
            anchors.fill: parent
            hoverEnabled: true
            enabled: chip.enabled
            cursorShape: Qt.PointingHandCursor
            preventStealing: true
            acceptedButtons: Qt.LeftButton
            onClicked: chip.activated()
        }
        MaterialSymbol {
            anchors.centerIn: parent
            text: chip.icon
            iconSize: 14
            color: chip.tint
        }
        StyledToolTip {
            alternativeVisibleCondition: chipMa.containsMouse && tooltipText.length > 0
            text: tooltipText
        }
    }
}
