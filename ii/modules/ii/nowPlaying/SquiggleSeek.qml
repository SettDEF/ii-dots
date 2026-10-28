import QtQuick
import qs.modules.common

/**
 * Android-12 style seek bar (from Takt Play's SquiggleSeek): the played part is a sine that flows while
 * playing and eases flat when paused, the rest a flat line, a thumb at the playhead. Drag (or click) to
 * seek: `moved` while dragging, `committed` on release. Redraws only while it moves.
 */
Item {
    id: s
    property real value: 0
    property real max: 1
    property bool playing: false
    property real amp: 3.5
    property real speed: 1
    property color played: Appearance.colors.colPrimary
    property color rest: Appearance.colors.colLayer1
    signal moved(real v)
    signal committed(real v)
    implicitHeight: 28

    // while dragging the bar shows the finger, not the song
    property real dragValue: -1
    readonly property real pct: Math.max(0, Math.min(1, (dragValue >= 0 ? dragValue : value) / Math.max(0.001, max)))
    property real curAmp: 0
    property real phase: 0

    // the wave moves on every frame while playing or easing; still otherwise (no idle redraws)
    FrameAnimation {
        running: s.visible && (s.playing || s.curAmp > 0.05)
        onTriggered: {
            const dt = Math.min(0.05, frameTime)
            const target = s.playing ? s.amp : 0
            s.curAmp += (target - s.curAmp) * Math.min(1, dt * 6)
            if (s.playing) s.phase += dt * s.speed * 5
            canvas.requestPaint()
        }
    }
    onPctChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const mid = height / 2, wl = 26, step = 3, px = s.pct * width
            ctx.lineCap = "round"
            // the rest: flat
            ctx.strokeStyle = s.rest; ctx.lineWidth = 4
            ctx.beginPath(); ctx.moveTo(Math.min(width, px + 6), mid); ctx.lineTo(width, mid); ctx.stroke()
            // the played part: the wave
            ctx.strokeStyle = s.played; ctx.lineWidth = 4
            ctx.beginPath(); ctx.moveTo(0, mid)
            for (let x = step; x <= px; x += step)
                ctx.lineTo(x, mid + s.curAmp * Math.sin((x / wl) * Math.PI * 2 - s.phase))
            ctx.stroke()
            // the thumb
            ctx.fillStyle = s.played
            ctx.beginPath(); ctx.roundedRect(px - 3, mid - 10, 6, 20, 3, 3); ctx.fill()
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        function at(x) { return Math.max(0, Math.min(1, x / width)) * s.max }
        onPressed: (m) => { s.dragValue = at(m.x); s.moved(s.dragValue) }
        onPositionChanged: (m) => { if (pressed) { s.dragValue = at(m.x); s.moved(s.dragValue) } }
        onReleased: (m) => { const v = at(m.x); s.dragValue = -1; s.committed(v) }
        onCanceled: s.dragValue = -1
    }
}
