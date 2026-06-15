// DrawCanvas — reusable drawing surface used by both the fullscreen
// ScreenDraw overlay and any small embedded widget (sidebar mini-canvas, etc.)
//
// Public API
//   property string tool         pen | brush | highlighter | eraser | cursor
//   property color  strokeColor
//   property real   strokeSize
//   property var    strokes      array of { tool, color, size, points: [[x,y],…] }
//   property var    redoStack
//   function undo()
//   function redo()
//   function clear()
//   function savePng(path)
//
// The component is a single Item — anchor / size it however the caller wants.
import QtQuick

Item {
    id: root

    // ── Public inputs ────────────────────────────────────────────────────
    property string tool: "pen"
    property color  strokeColor: "#ff5a5a"
    property real   strokeSize: 4

    // ── Stroke state ─────────────────────────────────────────────────────
    property var strokes: []
    property var redoStack: []

    // Cursor in cursor-mode passes input through to whatever's behind the
    // surface (the canvas's MouseArea sets mouse.accepted = false).

    function undo() {
        if (strokes.length === 0) return
        const arr = strokes.slice()
        const popped = arr.pop()
        strokes = arr
        const r = redoStack.slice(); r.push(popped); redoStack = r
    }
    function redo() {
        if (redoStack.length === 0) return
        const r = redoStack.slice()
        const last = r.pop()
        redoStack = r
        const arr = strokes.slice(); arr.push(last); strokes = arr
    }
    // Async — writes the rendered canvas PNG to `path` and invokes
    // callback() ONLY after the file has been written. Use this instead of
    // savePng() when you need to chain a process that reads the file.
    function grabPng(path, callback) {
        canvas.grabToImage(function(result) {
            result.saveToFile(path)
            if (callback) callback()
        })
    }
    function clear() {
        redoStack = strokes.slice()
        strokes = []
    }
    function savePng(path) { canvas.save(path) }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        property var liveStroke: null
        readonly property int strokeRev: root.strokes.length
        onStrokeRevChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            for (const s of root.strokes) drawStroke(ctx, s)
            if (liveStroke) drawStroke(ctx, liveStroke)
        }

        function drawStroke(ctx, s) {
            if (!s || !s.points || s.points.length < 1) return
            ctx.save()
            if (s.tool === "eraser") {
                ctx.globalCompositeOperation = "destination-out"
                ctx.strokeStyle = "#000"
            } else {
                ctx.globalCompositeOperation = "source-over"
                ctx.strokeStyle = s.color
                if (s.tool === "highlighter") ctx.globalAlpha = 0.35
            }
            ctx.lineWidth = s.size
            ctx.beginPath()
            const p0 = s.points[0]
            ctx.moveTo(p0[0], p0[1])
            if (s.points.length === 1) {
                ctx.lineTo(p0[0] + 0.01, p0[1] + 0.01)
            } else {
                for (let i = 1; i < s.points.length; i++)
                    ctx.lineTo(s.points[i][0], s.points[i][1])
            }
            ctx.stroke()
            ctx.restore()
        }

        function startStroke(x, y) {
            if (root.tool === "cursor") return
            const sz = root.tool === "brush"        ? root.strokeSize * 2.5
                     : root.tool === "highlighter"  ? root.strokeSize * 4
                     : root.tool === "eraser"       ? root.strokeSize * 4
                     : root.strokeSize
            liveStroke = {
                tool:  root.tool,
                color: String(root.strokeColor),
                size:  sz,
                points: [[x, y]]
            }
            requestPaint()
        }
        function pushPoint(x, y) {
            if (!liveStroke) return
            liveStroke.points.push([x, y])
            requestPaint()
        }
        function endStroke() {
            if (!liveStroke) return
            const arr = root.strokes.slice()
            arr.push(liveStroke)
            root.strokes = arr
            root.redoStack = []
            liveStroke = null
        }

    }

    // Input layer kept OUTSIDE the Canvas so layered parents (SwipeView
    // with OpacityMask, etc.) can't break event delivery to the canvas's
    // child MouseArea. Sits on top via z and converts pointer events
    // straight into stroke calls on `canvas`.
    MouseArea {
        id: drawArea
        anchors.fill: parent
        z: 1
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.ArrowCursor
        // While a stroke is in progress, claim the press so an ancestor
        // Flickable / SwipeView can't yank it away to scroll or change tabs.
        preventStealing: pressed && root.tool !== "cursor"

        onPositionChanged: function(mouse) {
            if (pressed && root.tool !== "cursor")
                canvas.pushPoint(mouse.x, mouse.y)
        }
        onPressed: function(mouse) {
            if (mouse.button !== Qt.LeftButton) { mouse.accepted = false; return }
            if (root.tool === "cursor") { mouse.accepted = false; return }
            canvas.startStroke(mouse.x, mouse.y)
        }
        onReleased: function(mouse) {
            if (root.tool === "cursor") return
            canvas.endStroke()
        }
    }
}
