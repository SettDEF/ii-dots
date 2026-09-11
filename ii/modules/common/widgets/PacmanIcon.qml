// A drawn Pac-Man, for the pacman-updates button.
//
// Canvas rather than a theme icon, because no icon theme ships a Pac-Man and
// the whole point is the chomp — a static glyph would just be a yellow circle
// with a notch. Two arcs and a fill, repainted only while `chomping` is true,
// so an idle bar costs nothing.
//
// Example
//   PacmanIcon { implicitSize: 20; chomping: hovered; color: "#FFD54F" }
import QtQuick

Item {
    id: root

    property int implicitSize: 20
    property color color: "#FFD54F"          // classic Pac-Man yellow
    property bool chomping: false
    // 0 = closed (full circle), 1 = widest bite.
    property real mouthOpen: 0
    // Which way it faces, in degrees. 0 = right.
    property real facing: 0

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    SequentialAnimation {
        running: root.chomping
        loops: Animation.Infinite
        // Ends closed so stopping mid-cycle never strands a gaping mouth.
        onStopped: root.mouthOpen = 0
        NumberAnimation {
            target: root; property: "mouthOpen"
            from: 0; to: 1; duration: 180; easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root; property: "mouthOpen"
            from: 1; to: 0; duration: 180; easing.type: Easing.InQuad
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        // Repaint is driven by the property change, not by a timer.
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const cx = width / 2
            const cy = height / 2
            const r = Math.min(width, height) / 2

            // Widest bite is 40° either side of the facing direction.
            const half = (root.mouthOpen * 40) * Math.PI / 180
            const face = root.facing * Math.PI / 180

            ctx.beginPath()
            ctx.moveTo(cx, cy)
            ctx.arc(cx, cy, r, face + half, face - half + 2 * Math.PI, false)
            ctx.closePath()
            ctx.fillStyle = root.color
            ctx.fill()

            // The eye rides above the mouth axis and vanishes into the fill if
            // it is drawn in the same colour, so it is punched out instead.
            ctx.globalCompositeOperation = "destination-out"
            ctx.beginPath()
            ctx.arc(cx + r * 0.08, cy - r * 0.42, Math.max(1, r * 0.14), 0, 2 * Math.PI)
            ctx.fill()
        }
    }

    onMouthOpenChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()
    onFacingChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
}
