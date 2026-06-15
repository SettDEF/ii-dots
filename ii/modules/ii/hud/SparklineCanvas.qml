import qs.modules.common
import QtQuick

Canvas {
    id: root
    property var   history: []
    property color accent:  Appearance.colors.colPrimary
    property bool  filled:  false

    // Coalesce all redraw triggers — a single binding rebound on any input
    // change schedules at most one repaint per frame, instead of four
    // separate handlers each calling requestPaint().
    readonly property var _repaintHook: [history, accent, width, height]
    on_RepaintHookChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)

        const pts = root.history
        if (!pts || pts.length < 2) return

        const max = Math.max(...pts, 1)
        const step = width / (pts.length - 1)

        const toY = v => height - (v / max) * (height - 2) - 1

        ctx.beginPath()
        ctx.moveTo(0, toY(pts[0]))
        for (let i = 1; i < pts.length; i++) {
            const cx = (i - 0.5) * step
            ctx.bezierCurveTo(
                cx, toY(pts[i - 1]),
                cx, toY(pts[i]),
                i * step, toY(pts[i])
            )
        }

        if (root.filled) {
            ctx.lineTo(width, height)
            ctx.lineTo(0, height)
            ctx.closePath()
            const grad = ctx.createLinearGradient(0, 0, 0, height)
            grad.addColorStop(0, Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35))
            grad.addColorStop(1, Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.0))
            ctx.fillStyle = grad
            ctx.fill()
            ctx.beginPath()
            ctx.moveTo(0, toY(pts[0]))
            for (let i = 1; i < pts.length; i++) {
                const cx2 = (i - 0.5) * step
                ctx.bezierCurveTo(cx2, toY(pts[i-1]), cx2, toY(pts[i]), i * step, toY(pts[i]))
            }
        }

        ctx.strokeStyle = Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.9)
        ctx.lineWidth = 1.5
        ctx.stroke()
    }
}
