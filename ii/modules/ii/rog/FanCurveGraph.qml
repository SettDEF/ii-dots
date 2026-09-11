import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * Interactive fan-curve editor. X = temperature (fixed points, matching
 * asusctl's 42/50/55/60/65/70/75/80°C), Y = fan PWM %. Each point is a dot you
 * drag up/down. `floorPwm` (driven by the power slider — more power → higher
 * floor) is a hard lower bound the dots can't cross, drawn as a guide line.
 *
 * Lines live on the Canvas; ALL text is crisp QML StyledText overlaid on top
 * (canvas-drawn text is blurry on HiDPI).
 *
 *   pwmValues : list of 8 ints (0..100), the draggable Y values
 *   tempPoints: the fixed X temps
 *   floorPwm  : safety minimum (dots clamp to it)
 *   liveTemp  : current CPU °C (draws a marker)
 *   signal edited()  → emitted on drag release (read pwmValues)
 */
Item {
    id: root
    implicitHeight: 170

    property var tempPoints: [42, 50, 55, 60, 65, 70, 75, 80]
    property var pwmValues:  [15, 25, 32, 45, 55, 70, 85, 100]
    property int floorPwm: 0
    property int liveTemp: 0
    property int maxRpm: 8900     // right axis: fan RPM at 100% PWM
    signal edited()

    readonly property int tMin: 35
    readonly property int tMax: 90
    property real padL: 30
    property real padR: 48        // room for the RPM (right) axis labels
    property real padT: 8
    property real padB: 20        // room for the temperature labels
    readonly property real plotW: width - padL - padR
    readonly property real plotH: height - padT - padB

    function xAt(temp) { return padL + (temp - tMin) / (tMax - tMin) * plotW }
    function yAt(pwm)  { return padT + (1 - pwm / 100) * plotH }
    function pwmAtY(y) { return Math.round(Math.max(0, Math.min(100, (1 - (y - padT) / plotH) * 100))) }

    // ── Lines only: grid / floor / live marker / curve (antialiased) ─────
    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        property var _pwm: root.pwmValues
        property int _floor: root.floorPwm
        property int _live: root.liveTemp
        on_PwmChanged: requestPaint()
        on_FloorChanged: requestPaint()
        on_LiveChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const rightX = root.width - root.padR;
            // horizontal % grid lines
            ctx.strokeStyle = Qt.alpha(Appearance.colors.colOnLayer0, 0.12);
            ctx.lineWidth = 1;
            for (let p = 0; p <= 100; p += 25) {
                const y = Math.round(root.yAt(p)) + 0.5;   // crisp 1px line
                ctx.beginPath(); ctx.moveTo(root.padL, y); ctx.lineTo(rightX, y); ctx.stroke();
            }
            // floor line (safety minimum)
            if (root.floorPwm > 0) {
                ctx.strokeStyle = Qt.alpha(Appearance.m3colors.m3error, 0.7);
                ctx.lineWidth = 1.5; ctx.setLineDash([4, 3]);
                const fy = root.yAt(root.floorPwm);
                ctx.beginPath(); ctx.moveTo(root.padL, fy); ctx.lineTo(rightX, fy); ctx.stroke();
                ctx.setLineDash([]);
            }
            // live temp marker
            if (root.liveTemp > root.tMin) {
                ctx.strokeStyle = Qt.alpha(Appearance.colors.colPrimary, 0.45);
                ctx.lineWidth = 1.5;
                const lx = root.xAt(Math.min(root.tMax, root.liveTemp));
                ctx.beginPath(); ctx.moveTo(lx, root.padT); ctx.lineTo(lx, root.height - root.padB); ctx.stroke();
            }
            // the curve
            ctx.strokeStyle = Appearance.colors.colPrimary;
            ctx.lineWidth = 2.5; ctx.lineJoin = "round"; ctx.lineCap = "round";
            ctx.beginPath();
            for (let i = 0; i < root.tempPoints.length; i++) {
                const x = root.xAt(root.tempPoints[i]), y = root.yAt(root.pwmValues[i]);
                i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
            }
            ctx.stroke();
        }
    }

    // ── Crisp text overlays (QML, dpr-aware — not blurry like canvas text) ──
    // left axis: PWM % · right axis: corresponding fan RPM
    Repeater {
        model: [0, 25, 50, 75, 100]
        delegate: Item {
            required property int modelData
            anchors.fill: parent
            StyledText {
                x: 3; y: root.yAt(parent.modelData) - height / 2
                text: parent.modelData + "%"
                font.pixelSize: 10
                color: Qt.alpha(Appearance.colors.colOnLayer0, 0.55)
            }
            StyledText {
                x: root.width - width - 3; y: root.yAt(parent.modelData) - height / 2
                text: Math.round(root.maxRpm * parent.modelData / 100 / 100) * 100
                font.pixelSize: 10
                color: Qt.alpha(Appearance.colors.colOnLayer0, 0.45)
            }
        }
    }
    StyledText {
        x: root.width - width - 3; y: root.height - height
        text: "rpm"; font.pixelSize: 9
        color: Qt.alpha(Appearance.colors.colOnLayer0, 0.3)
    }

    // bottom axis: temperature label under each point (the draggable "dots")
    Repeater {
        model: root.tempPoints.length
        delegate: StyledText {
            required property int index
            x: root.xAt(root.tempPoints[index]) - width / 2
            y: root.height - root.padB + 4
            text: root.tempPoints[index] + "°"
            font.pixelSize: 10
            color: Qt.alpha(Appearance.colors.colOnLayer0, 0.7)
        }
    }

    // ── Draggable dots ───────────────────────────────────────────────────
    Repeater {
        model: root.tempPoints.length
        delegate: Rectangle {
            id: dot
            required property int index
            width: 14; height: 14; radius: 7
            antialiasing: true
            color: dragMa.drag.active ? Appearance.colors.colPrimary : Appearance.colors.colLayer0
            border.width: 2; border.color: Appearance.colors.colPrimary
            x: root.xAt(root.tempPoints[index]) - width / 2
            y: root.yAt(root.pwmValues[index]) - height / 2

            MouseArea {
                id: dragMa
                anchors.fill: parent
                anchors.margins: -6           // bigger hit target than the 14px dot
                cursorShape: Qt.SizeVerCursor
                drag.target: dot
                drag.axis: Drag.YAxis
                drag.minimumY: root.yAt(100)
                drag.maximumY: root.yAt(root.floorPwm)   // floor = hard min
                onPositionChanged: {
                    const v = root.pwmAtY(dot.y + dot.height / 2);
                    const arr = root.pwmValues.slice();
                    arr[dot.index] = Math.max(root.floorPwm, v);
                    root.pwmValues = arr;
                }
                onReleased: {
                    root.edited()
                    // Restore the declarative y-binding the drag replaced, so an
                    // external pwmValues change (applying a preset) repositions
                    // this dot again instead of leaving it stuck where dragged.
                    dot.y = Qt.binding(() => root.yAt(root.pwmValues[dot.index]) - dot.height / 2)
                }
            }
        }
    }
}
