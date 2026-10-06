// Edit-mode chrome for one widget in a row: an outline, drag-to-reorder, and a
// pair of buttons that appear on hover (configure, remove). Knows no widget
// and no surface; it is handed the widget's item, its id and a registry.
//
// Reordering moves the widget under the pointer. Each time the pointer crosses
// a neighbour, the registry is told the new position and the layout rearranges
// itself; `target.dragOffset` is then re-based so the widget stays glued to the
// pointer instead of jumping to its new slot.
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Item {
    id: root

    /// The widget's own item. Needs `dragOffset` (real), `x`, `width`, `parent`.
    required property Item target
    required property string widgetId
    /// DockWidgets / BarWidgets: entry, moveTo, remove, beginEdit, endEdit, enabled.
    required property var registry
    /// Raised when the gear is pressed; the host decides what "configure" opens.
    signal configure()

    anchors.fill: parent

    readonly property bool dragging: grab.pressed
    readonly property bool configurable: (root.registry.entry(root.widgetId)?.settings ?? []).length > 0
    readonly property bool hot: grab.containsMouse || root.dragging

    // Which sibling is under the dragged widget's centre, and where it sits in
    // the enabled list. Siblings are whatever else in the row declares a
    // widgetId; separators and buttons are skipped by that test.
    function slotUnderCentre() {
        const row = root.target.parent;
        if (!row) return -1;
        const cx = root.target.x + root.target.width / 2 + root.target.dragOffset;
        for (const c of row.children) {
            if (c === root.target || c.widgetId === undefined || !c.visible) continue;
            if (cx >= c.x && cx < c.x + c.width) return root.registry.enabled.indexOf(c.widgetId);
        }
        return -1;
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Appearance.rounding.normal
        color: root.dragging ? Qt.alpha(Appearance.colors.colPrimary, 0.16)
             : root.hot ? Qt.alpha(Appearance.colors.colPrimary, 0.08) : "transparent"
        border.width: root.hot ? 2 : 1
        border.color: root.hot ? Appearance.colors.colPrimary
                               : Qt.alpha(Appearance.colors.colPrimary, 0.45)
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    MouseArea {
        id: grab
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        acceptedButtons: Qt.LeftButton

        property real startX: 0
        property real lastItemX: 0
        /// How far the layout has carried the widget since the press.
        property real shift: 0

        onPressed: mouse => {
            grab.startX = grab.mapToGlobal(mouse.x, 0).x;
            grab.lastItemX = root.target.x;
            grab.shift = 0;
            settle.stop();
            root.registry.beginEdit();
        }
        onPositionChanged: mouse => {
            if (!grab.pressed) return;
            root.target.dragOffset = grab.mapToGlobal(mouse.x, 0).x - grab.startX + grab.shift;
            const slot = root.slotUnderCentre();
            if (slot >= 0) root.registry.moveTo(root.widgetId, slot);
        }
        onReleased: {
            root.registry.endEdit();
            settle.restart();
        }
        onCanceled: { root.registry.endEdit(); settle.restart(); }
    }

    // Layout moved the widget under the pointer: shift the offset back by the
    // same amount so the net on-screen position does not change.
    Connections {
        target: root.target
        function onXChanged() {
            if (grab.pressed) {
                const carried = grab.lastItemX - root.target.x;
                grab.shift += carried;
                root.target.dragOffset += carried;
            }
            grab.lastItemX = root.target.x;
        }
    }

    // Let go: slide the remaining offset to zero rather than snapping.
    NumberAnimation {
        id: settle
        target: root.target
        property: "dragOffset"
        to: 0
        duration: Appearance.animation.elementMoveFast.duration
        easing.type: Easing.OutCubic
    }

    // ── Hover buttons ────────────────────────────────────────────────────
    Row {
        anchors { top: parent.top; right: parent.right; margins: 2 }
        spacing: 2
        visible: root.hot && !root.dragging

        RippleButton {
            visible: root.configurable
            implicitWidth: 20; implicitHeight: 20
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimaryContainer
            onClicked: root.configure()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "tune"; iconSize: 13
                color: Appearance.colors.colOnPrimaryContainer
            }
        }
        RippleButton {
            implicitWidth: 20; implicitHeight: 20
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colErrorContainer
            onClicked: root.registry.remove(root.widgetId)
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "close"; iconSize: 13
                color: Appearance.colors.colOnErrorContainer
            }
        }
    }
}
