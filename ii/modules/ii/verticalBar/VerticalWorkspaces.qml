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

        // The active indicator SLIDES between slots rather than each slot
        // colouring itself in place — the same thing the horizontal bar does,
        // and the reason switching workspace there reads as one object moving
        // instead of two lights blinking.
        //
        // Drawn behind the slots, so their numbers sit on top of it.
        Rectangle {
            id: activeIndicator
            z: -1
            parent: slotColumn

            // itemAt() is not itself reactive, so both of these are named to
            // force a re-read when the list or the selection changes.
            readonly property int shownIdx: {
                void root.shownIndices;
                return root.shownIndices.indexOf(WorkspaceSlots.activeIndex);
            }
            readonly property Item target: shownIdx >= 0 ? slotRepeater.itemAt(shownIdx) : null

            visible: activeIndicator.target !== null
            width: root.slotSize
            height: root.slotSize
            radius: width / 2
            color: Appearance.colors.colPrimary

            x: activeIndicator.target ? activeIndicator.target.x : 0
            y: activeIndicator.target ? activeIndicator.target.y : 0

            // No Behavior on x: the column is one slot wide, so x never moves
            // and an animation on it could only ever add a frame of lag.
            Behavior on y {
                NumberAnimation {
                    duration: Appearance.animationCurves.expressiveFastSpatialDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                }
            }
        }

        Repeater {
            id: slotRepeater
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

                // Transparent when active: the sliding indicator behind
                // supplies that fill. Colouring it here as well would make the
                // destination light up before the indicator arrived.
                color: slot.active ? "transparent"
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

                // Same label rules and same typography as the horizontal
                // bar — numbers family, extra bold — so this reads as the
                // workspaces you already have, turned on its side.
                StyledText {
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    visible: root.alwaysShowNumbers || root.hovered || slot.active
                    text: WorkspaceSlots.labelAt(slot.modelData)
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family.numbers
                    font.weight: Font.ExtraBold
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
