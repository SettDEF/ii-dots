import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * A circular level display that is also a volume control.
 *
 * It shows TWO different things at once, deliberately:
 *   • the fill  — the live signal on this channel, which moves with the audio
 *   • the dot   — the volume you have SET, which only moves when you move it
 * Those are not the same number, and conflating them is what makes a plain
 * volume ring useless for spotting a channel that is set correctly but silent.
 *
 * The dot is a drag handle styled to match StyledSlider's: same colPrimary,
 * same full rounding, and it narrows while held, so it reads as the same kind
 * of control rather than as decoration.
 */
Item {
    id: root

    // Live signal level, 0..1. Drives the fill.
    property real level: 0
    // Peak hold, 0..1. Shown as a dot on the rim; -1 hides it. Held rather
    // than instantaneous because the peak is gone before your eye arrives.
    property real peak: -1
    // Volume setting, 0..1. Drives the dot.
    property real value: 0
    property bool muted: false
    property string label: ""
    property string sublabel: ""
    property string tooltipText: ""

    // Off by default: two dots on a 46px rim (one solid handle, one hollow
    // peak) read as debris rather than as controls, and the per-channel
    // sliders below the preview already set volume.
    property bool draggable: false
    // 0.5 = circle (a driver seen face-on), lower = rounded slot. Side-firing
    // speakers are slots in the chassis edge, and drawing them as circles made
    // every device look identical regardless of what it actually is.
    property real cornerFactor: 0.5

    signal moved(real newValue)
    signal tapped()

    implicitWidth: 54
    implicitHeight: 54

    // Knob sweep: 270° starting at bottom-left and running clockwise over the
    // top to bottom-right. Screen coordinates are y-down, so 270° is straight
    // up — the gap sits at the bottom where a knob's gap belongs.
    readonly property real startAngle: 135
    readonly property real sweep: 270
    readonly property real handleRadius: Math.min(width, height) / 2

    function angleFor(v) {
        return root.startAngle + Math.max(0, Math.min(1, v)) * root.sweep;
    }

    Rectangle {
        id: ring
        anchors.fill: parent
        radius: Math.min(width, height) * root.cornerFactor
        color: root.muted
               ? Appearance.colors.colLayer2
               : ColorUtils.mix(Appearance.colors.colLayer2,
                                Appearance.colors.colPrimary, 1 - root.level)
        border.width: 2
        border.color: root.muted ? Appearance.colors.colSubtext
                                 : Appearance.colors.colPrimary
        // Fast attack so a transient is actually visible.
        Behavior on color { ColorAnimation { duration: 90 } }
    }

    StyledText {
        anchors.centerIn: parent
        visible: root.label.length > 0
        text: root.label
        font.pixelSize: Appearance.font.pixelSize.normal
        font.bold: true
        color: Appearance.colors.colOnLayer0
    }
    // Below the ring, not inside it: at 46px there is no room for a value and
    // a label together, and cramming both made the numbers overflow the circle.
    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: 3
        visible: root.sublabel.length > 0
        text: root.sublabel
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.family: Appearance.font.family.monospace
        color: Appearance.colors.colSubtext
    }

    TapHandler {
        // Only fires when the dot was not the target, so testing a channel and
        // setting its volume do not fight each other.
        onTapped: root.tapped()
    }

    // Peak-hold marker on the rim. Distinguished from the volume handle by
    // being hollow: one is a reading, the other is a control, and they must not
    // look like the same affordance.
    Rectangle {
        id: peakDot
        visible: root.peak >= 0
        readonly property real angleRad: root.angleFor(root.peak) * Math.PI / 180
        width: 7; height: 7
        radius: Appearance.rounding.full
        color: "transparent"
        border.width: 2
        border.color: root.peak > 0.92 ? Appearance.m3colors.m3error
                                       : Appearance.colors.colOnLayer0
        x: root.width / 2 + root.handleRadius * Math.cos(angleRad) - width / 2
        y: root.height / 2 + root.handleRadius * Math.sin(angleRad) - height / 2
        Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    }

    // ── Drag handle ─────────────────────────────────────────────────────
    Rectangle {
        id: handle
        visible: root.draggable
        readonly property real angleRad: root.angleFor(root.value) * Math.PI / 180
        width: dragArea.active ? 9 : 12
        height: width
        radius: Appearance.rounding.full
        color: root.muted ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
        x: root.width / 2 + root.handleRadius * Math.cos(angleRad) - width / 2
        y: root.height / 2 + root.handleRadius * Math.sin(angleRad) - height / 2
        // Matches StyledSlider, whose handle also thins while pressed.
        Behavior on width {
            animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        border.width: 2
        border.color: Appearance.colors.colLayer1

        HoverHandler { cursorShape: Qt.PointingHandCursor }

        DragHandler {
            id: dragArea
            target: null
            onCentroidChanged: {
                if (!active) return;
                // Angle of the cursor about the knob centre, unwrapped into the
                // sweep range. Without the unwrap, dragging past the 0°/360°
                // seam makes the value jump from full to empty.
                const p = dragArea.centroid.scenePosition;
                const c = root.mapToScene(Qt.point(root.width / 2, root.height / 2));
                let deg = Math.atan2(p.y - c.y, p.x - c.x) * 180 / Math.PI;
                if (deg < 0) deg += 360;
                if (deg < root.startAngle) deg += 360;
                const v = (deg - root.startAngle) / root.sweep;
                // Outside the sweep entirely: clamp to whichever end is nearer
                // rather than snapping across the gap.
                root.moved(v < 0 ? 0 : v > 1 ? (v > 1.5 ? 0 : 1) : v);
            }
        }

        StyledToolTip {
            extraVisibleCondition: dragArea.active
            alternativeVisibleCondition: dragArea.active
            text: root.tooltipText.length > 0 ? root.tooltipText
                                              : Math.round(root.value * 100) + "%"
        }
    }
}
