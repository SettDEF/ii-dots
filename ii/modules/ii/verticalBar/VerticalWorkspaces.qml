import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

/**
 * Workspaces for the vertical bar.
 *
 * Its own widget rather than a `vertical: true` branch inside the horizontal
 * one, for two reasons. The horizontal Workspaces declares `vertical` and then
 * never reads it — every anchor in those 1340 lines is horizontal, which is why
 * it rendered at full width and spilled out of a 40px bar. And half of what it
 * carries (the media marquee, the window-title context slot, the spectrum) has
 * nowhere to go in a bar this narrow anyway.
 *
 * This module already works that way: VerticalMedia, VerticalClockWidget and
 * VerticalDateWidget are all vertical-specific rather than shared branches.
 *
 * The slot list comes from WorkspaceSlots, so the two bars cannot disagree
 * about which workspaces exist or where the group starts.
 */
Item {
    id: root
    property bool vertical: true    // for symmetry with Bar.Workspaces

    readonly property int slotSize: 26
    readonly property int slotSpacing: 3
    readonly property bool alwaysShowNumbers: Config.options.bar.workspaces.alwaysShowNumbers ?? false
    readonly property bool romanNumerals: Config.options.bar.workspaces.romanNumerals ?? false

    // Hovering reveals every slot; at rest only the ones that exist plus the
    // one you are on, so the bar does not carry eight empty boxes.
    property bool hovered: false
    readonly property var shownIndices: {
        const out = [];
        for (let i = 0; i < WorkspaceSlots.slotCount; i++) {
            if (root.hovered || WorkspaceSlots.existsAt(i) || i === WorkspaceSlots.activeIndex)
                out.push(i);
        }
        return out.length > 0 ? out : [Math.max(0, WorkspaceSlots.activeIndex)];
    }

    implicitWidth: root.slotSize
    implicitHeight: slotColumn.implicitHeight

    function roman(n) {
        const table = [[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]];
        let out = "";
        for (const [v, s] of table) { while (n >= v) { out += s; n -= v; } }
        return out;
    }

    HoverHandler {
        onHoveredChanged: root.hovered = hovered
    }

    // Scroll anywhere on the strip to step through workspaces, the same
    // gesture the horizontal bar offers.
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const dir = event.angleDelta.y < 0 ? 1 : -1;
            const next = WorkspaceSlots.activeIndex + dir;
            if (next >= 0 && next < WorkspaceSlots.slotCount) WorkspaceSlots.focusIndex(next);
        }
    }

    ColumnLayout {
        id: slotColumn
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.slotSpacing

        Repeater {
            model: root.shownIndices

            delegate: Rectangle {
                id: slot
                required property int modelData      // index into WorkspaceSlots

                readonly property bool active: modelData === WorkspaceSlots.activeIndex
                readonly property bool occupied: WorkspaceSlots.existsAt(modelData)
                readonly property int wsId: WorkspaceSlots.idAt(modelData)

                Layout.alignment: Qt.AlignHCenter
                implicitWidth: root.slotSize
                implicitHeight: root.slotSize
                radius: width / 2

                color: slot.active ? Appearance.colors.colPrimary
                    : slot.occupied ? Appearance.colors.colLayer2
                    : slotHov.hovered ? Appearance.colors.colLayer1Hover
                    : "transparent"

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                HoverHandler { id: slotHov }
                TapHandler { onTapped: WorkspaceSlots.focusIndex(slot.modelData) }

                StyledText {
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    // Numbers on the active slot, on hover, or always if asked.
                    // An unoccupied slot you are not pointing at is a dot.
                    visible: root.alwaysShowNumbers || root.hovered || slot.active
                    text: {
                        const n = slot.wsId - WorkspaceSlots.groupStart + 1;
                        if (n < 1 || n > WorkspaceSlots.workspacesPerGroup) return String(slot.wsId);
                        return root.romanNumerals ? root.roman(n) : String(n);
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: slot.active ? Appearance.m3colors.m3onPrimary
                                       : Appearance.colors.colOnLayer1
                }

                // The dot an unoccupied slot shows instead of a number.
                Rectangle {
                    anchors.centerIn: parent
                    visible: !(root.alwaysShowNumbers || root.hovered || slot.active)
                    implicitWidth: slot.occupied ? 7 : 4
                    implicitHeight: implicitWidth
                    radius: width / 2
                    color: Appearance.colors.colOnLayer1
                    opacity: slot.occupied ? 0.9 : 0.35
                    Behavior on implicitWidth {
                        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
                    }
                }
            }
        }
    }
}
