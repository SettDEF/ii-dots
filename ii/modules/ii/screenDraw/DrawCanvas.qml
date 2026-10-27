// DrawCanvas — reusable drawing surface used by both the fullscreen
// ScreenDraw overlay and any small embedded widget (sidebar mini-canvas, etc.)
//
// Public API
//   property string tool         pen | brush | highlighter | eraser | cursor
//                                rect | ellipse | arrow | line | redact (drag) · text (click, type)
//                                crop (drag: sets `crop`, not drawn into the picture)
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
    /// crop: { x, y, w, h } in this item's coordinates, or null
    property var crop: null
    readonly property var dragTools: ["rect", "ellipse", "arrow", "line", "redact", "crop"]
    function addStrokes(list) {
        root.strokes = root.strokes.concat(list)
        root.redoStack = []
    }

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
            if (s.tool === "text") return drawText(ctx, s)
            if (root.dragTools.includes(s.tool)) return drawShape(ctx, s)
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

        // rectangle, ellipse, arrow, line and redact: two points, the press and where it is now
        function drawShape(ctx, s) {
            if (s.points.length < 2 || s.tool === "crop") return
            const [a, b] = s.points
            const x = Math.min(a[0], b[0]), y = Math.min(a[1], b[1]), w = Math.abs(b[0] - a[0]), h = Math.abs(b[1] - a[1])
            ctx.save()
            ctx.strokeStyle = s.color
            ctx.fillStyle = s.color
            ctx.lineWidth = s.size
            if (s.tool === "redact") {
                ctx.fillStyle = "#111111"
                ctx.fillRect(x, y, w, h)
            } else if (s.tool === "rect") {
                ctx.strokeRect(x, y, w, h)
            } else if (s.tool === "ellipse") {
                ctx.beginPath()
                ctx.ellipse(x, y, w, h)
                ctx.stroke()
            } else {
                ctx.beginPath()
                ctx.moveTo(a[0], a[1])
                ctx.lineTo(b[0], b[1])
                ctx.stroke()
                if (s.tool === "arrow") {
                    const ang = Math.atan2(b[1] - a[1], b[0] - a[0]), len = Math.max(12, s.size * 4)
                    ctx.beginPath()
                    ctx.moveTo(b[0], b[1])
                    ctx.lineTo(b[0] - len * Math.cos(ang - 0.45), b[1] - len * Math.sin(ang - 0.45))
                    ctx.lineTo(b[0] - len * Math.cos(ang + 0.45), b[1] - len * Math.sin(ang + 0.45))
                    ctx.closePath()
                    ctx.fill()
                }
            }
            ctx.restore()
        }
        function drawText(ctx, s) {
            ctx.save()
            ctx.fillStyle = s.color
            ctx.font = `bold ${Math.round(s.size * 4 + 8)}px sans-serif`
            ctx.textBaseline = "top"
            const lines = String(s.text).split("\n")
            for (let i = 0; i < lines.length; i++) ctx.fillText(lines[i], s.points[0][0], s.points[0][1] + i * (s.size * 4 + 12))
            ctx.restore()
        }

        function startStroke(x, y) {
            if (root.tool === "cursor") return
            if (root.tool === "text") return textInput.begin(x, y)
            if (root.dragTools.includes(root.tool)) {
                liveStroke = { tool: root.tool, color: String(root.strokeColor), size: root.strokeSize, points: [[x, y], [x, y]] }
                if (root.tool === "crop") root.crop = null
                return requestPaint()
            }
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
            if (root.dragTools.includes(liveStroke.tool)) {
                liveStroke.points[1] = [x, y]
                if (liveStroke.tool === "crop") root.crop = cropOf(liveStroke)
            } else {
                liveStroke.points.push([x, y])
            }
            requestPaint()
        }
        function cropOf(s) {
            const [a, b] = s.points
            return { x: Math.min(a[0], b[0]), y: Math.min(a[1], b[1]), w: Math.abs(b[0] - a[0]), h: Math.abs(b[1] - a[1]) }
        }
        function endStroke() {
            if (!liveStroke) return
            // a crop is a frame, not a mark; a drag too short to see is no shape
            if (liveStroke.tool === "crop") {
                const c = cropOf(liveStroke)
                root.crop = c.w > 8 && c.h > 8 ? c : null
                liveStroke = null
                return requestPaint()
            }
            if (root.dragTools.includes(liveStroke.tool)) {
                const c = cropOf(liveStroke)
                if (c.w < 3 && c.h < 3) { liveStroke = null; return requestPaint() }
            }
            const arr = root.strokes.slice()
            arr.push(liveStroke)
            root.strokes = arr
            root.redoStack = []
            liveStroke = null
        }

    }

    // the text tool: typed where it was clicked; Enter places it (Shift+Enter a new line), Esc drops it
    TextInput {
        id: textInput
        z: 2
        visible: false
        color: root.strokeColor
        font.pixelSize: Math.round(root.strokeSize * 4 + 8)
        font.bold: true
        width: Math.max(40, contentWidth + 8)
        property real px: 0
        property real py: 0
        function begin(x, y) {
            if (visible) commit()
            px = x; py = y; this.x = x; this.y = y
            text = ""
            visible = true
            forceActiveFocus()
        }
        function commit() {
            if (!visible) return
            visible = false
            if (text.trim().length > 0)
                root.addStrokes([{ tool: "text", text: text, color: String(root.strokeColor), size: root.strokeSize, points: [[px, py]] }])
            text = ""
        }
        Keys.onPressed: e => {
            if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) { commit(); e.accepted = true }
            else if (e.key === Qt.Key_Escape) { visible = false; text = ""; e.accepted = true }
        }
        onActiveFocusChanged: if (!activeFocus) commit()
        Rectangle { anchors.fill: parent; anchors.margins: -4; z: -1; color: "transparent"; border.width: 1; border.color: root.strokeColor; radius: 4; opacity: 0.6 }
    }

    // the crop: what stays, framed; the rest dimmed (not part of the picture: grabPng takes the canvas)
    Item {
        z: 1.5
        anchors.fill: parent
        visible: !!root.crop
        readonly property var c: root.crop ?? { x: 0, y: 0, w: 0, h: 0 }
        Rectangle { x: 0; y: 0; width: parent.width; height: parent.c.y; color: "#99000000" }
        Rectangle { x: 0; y: parent.c.y + parent.c.h; width: parent.width; height: parent.height - y; color: "#99000000" }
        Rectangle { x: 0; y: parent.c.y; width: parent.c.x; height: parent.c.h; color: "#99000000" }
        Rectangle { x: parent.c.x + parent.c.w; y: parent.c.y; width: parent.width - x; height: parent.c.h; color: "#99000000" }
        Rectangle { x: parent.c.x; y: parent.c.y; width: parent.c.w; height: parent.c.h; color: "transparent"; border.width: 2; border.color: "white" }
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
