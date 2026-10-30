// Editor content — the screenshot with a DrawCanvas over exactly the shown picture, the markup bar
// on top (MarkupBar.qml). Save / copy merge the marks into the picture at its full size (and crop
// it when a crop is set); the text actions read it with tesseract.
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.screenDraw
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root
    property string imagePath: ""
    signal closeRequested()

    property string tool: "pen"
    property color  strokeColor: Appearance.colors.colHueRed
    property real   strokeSize: 4

    Rectangle {
        id: card
        anchors { fill: parent; margins: 12 }
        radius: 22
        color: Appearance.m3colors.m3surfaceContainerHigh
        border.width: 1; border.color: Appearance.colors.colLayer0Border
        clip: true

        Image {
            id: img
            anchors { fill: parent; margins: 4; topMargin: 72 }
            source: root.imagePath !== "" ? "file://" + root.imagePath : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            cache: false
        }

        // over the painted picture only, so marks map 1:1 onto it (scaled by `scale` when saved)
        DrawCanvas {
            id: drawCanvas
            x: img.x + (img.width - img.paintedWidth) / 2
            y: img.y + (img.height - img.paintedHeight) / 2
            width: img.paintedWidth
            height: img.paintedHeight
            tool: root.tool
            strokeColor: root.strokeColor
            strokeSize: root.strokeSize
        }
    }
    /// picture pixels per canvas pixel
    readonly property real scale: img.paintedWidth > 0 ? img.sourceSize.width / img.paintedWidth : 1

    MarkupBar {
        id: bar
        anchors { top: parent.top; topMargin: 22; horizontalCenter: parent.horizontalCenter }
        tool: root.tool
        strokeColor: root.strokeColor
        strokeSize: root.strokeSize
        busy: ocr.running
        onToolPicked: t => root.tool = t
        onColorPicked: c => root.strokeColor = c
        onSizePicked: s => root.strokeSize = s
        onUndo: drawCanvas.undo()
        onRedo: drawCanvas.redo()
        onCopyText: root.readText("copy")
        onQuickRedact: root.readText("redact")
        onCopyImage: root.exportImage(false)
        onSave: root.exportImage(true)
        onClose: root.closeRequested()
    }

    // ── export: marks merged in at full size, cropped, to the clipboard (and saved) ──
    function exportImage(keep) {
        const overlay = "/tmp/quickshell-snip-overlay.png"
        const ts = new Date()
        const p = n => String(n).padStart(2, "0")
        const stamp = `${ts.getFullYear()}-${p(ts.getMonth() + 1)}-${p(ts.getDate())}_${p(ts.getHours())}${p(ts.getMinutes())}${p(ts.getSeconds())}`
        const saveDir = `${Quickshell.env("HOME")}/Pictures/Screenshots`
        const out = keep ? `${saveDir}/screenshot-${stamp}.png` : "/tmp/quickshell-snip-copy.png"
        const c = drawCanvas.crop
        const crop = c ? `${Math.round(c.w * root.scale)}x${Math.round(c.h * root.scale)}+${Math.round(c.x * root.scale)}+${Math.round(c.y * root.scale)}` : ""
        const cmd = ["bash", "-c", `
            src="$1"; overlay="$2"; out="$3"; crop="$4"; keep="$5"
            [ -f "$src" ] || { notify-send -a Screenshot -u critical "Screenshot not saved" "The picture is gone: $src"; exit 1; }
            mkdir -p "$(dirname "$out")"
            size=$(magick identify -format "%wx%h" "$src")
            # the released tinct has no image command: ImageMagick merges the marks then
            "$HOME/.local/bin/tinct" image composite "$src" "$overlay" "$size" "$out" 2>/dev/null || magick "$overlay" -resize "$size!" "$src" +swap -composite "$out" || { notify-send -a Screenshot -u critical "Screenshot not saved" "could not merge the marks"; exit 1; }
            [ -n "$crop" ] && magick "$out" -crop "$crop" +repage "$out"
            wl-copy < "$out"
            rm -f "$overlay"
            if [ "$keep" = 1 ]; then
                act=$(notify-send --wait -a Screenshot -i "$out" -A open=Open -A folder="Open folder" "Screenshot saved" "\${out/#$HOME/\\~}  ·  copied")
                case "$act" in open) xdg-open "$out" ;; folder) xdg-open "$(dirname "$out")" ;; esac
            fi`, "_", root.imagePath, overlay, out, crop, keep ? "1" : "0"]
        drawCanvas.grabPng(overlay, function() {
            Quickshell.execDetached(cmd)
            if (keep) root.closeRequested()
        })
    }

    // ── text actions: tesseract's words with their boxes ──
    property string ocrMode: ""
    function readText(mode) {
        if (ocr.running || !root.imagePath) return
        root.ocrMode = mode
        ocr.command = ["bash", "-c", mode === "copy" ? 'tesseract "$1" - 2>/dev/null' : 'tesseract "$1" - tsv 2>/dev/null', "_", root.imagePath]
        ocr.running = true
    }
    Process {
        id: ocr
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.ocrMode === "copy") {
                    const t = text.trim()
                    if (t.length) Quickshell.clipboardText = t
                    Quickshell.execDetached(["notify-send", "-a", "Screenshot", t.length ? "Text copied" : "No text found", t.length ? `${t.split("\n").length} lines` : ""])
                } else {
                    const boxes = root.sensitive(text)
                    drawCanvas.addStrokes(boxes.map(b => ({ tool: "redact", color: "#111111", size: 1,
                        points: [[b.x / root.scale - 2, b.y / root.scale - 2], [(b.x + b.w) / root.scale + 2, (b.y + b.h) / root.scale + 2]] })))
                    Quickshell.execDetached(["notify-send", "-a", "Screenshot", boxes.length ? `Hid ${boxes.length} thing${boxes.length === 1 ? "" : "s"}` : "Nothing to hide found", boxes.length ? "Undo takes one back" : "No e-mails, phone or card numbers, IPs"])
                }
            }
        }
    }
    /// From tesseract's TSV: the boxes (picture pixels) of e-mails, phone and card numbers, IBANs, IPs.
    function sensitive(tsv) {
        const lines = {}
        for (const row of tsv.split("\n").slice(1)) {
            const f = row.split("\t")
            if (f.length < 12 || f[0] !== "5" || !f[11].trim()) continue
            const key = `${f[2]}.${f[3]}.${f[4]}`
            ;(lines[key] = lines[key] ?? []).push({ x: +f[6], y: +f[7], w: +f[8], h: +f[9], t: f[11] })
        }
        const pats = [/[\w.+-]+@[\w-]+\.[\w.]+/g, /\+?\d[\d ()\/-]{7,}\d/g, /\b[A-Z]{2}\d{2}[ ]?(?:[A-Z0-9]{4}[ ]?){3,7}\b/g, /\b\d{1,3}(?:\.\d{1,3}){3}\b/g]
        const out = []
        for (const words of Object.values(lines)) {
            // the line's text, with where each word starts in it
            let s = "", at = []
            for (const w of words) { at.push(s.length); s += (s ? " " : "") + w.t; if (at.length > 1) at[at.length - 1] += 1 }
            for (const re of pats) {
                re.lastIndex = 0
                let m
                while ((m = re.exec(s)) !== null) {
                    const a = m.index, b = m.index + m[0].length
                    const hit = words.filter((w, i) => at[i] < b && at[i] + w.t.length > a)
                    if (!hit.length) continue
                    const x = Math.min(...hit.map(w => w.x)), y = Math.min(...hit.map(w => w.y))
                    out.push({ x, y, w: Math.max(...hit.map(w => w.x + w.w)) - x, h: Math.max(...hit.map(w => w.y + w.h)) - y })
                }
            }
        }
        return out
    }

    Keys.onPressed: function(event) {
        const ctrl = event.modifiers & Qt.ControlModifier
        if (event.key === Qt.Key_Escape) root.closeRequested()
        else if (ctrl && event.key === Qt.Key_Z) drawCanvas.undo()
        else if (ctrl && event.key === Qt.Key_Y) drawCanvas.redo()
        else if (ctrl && event.key === Qt.Key_C) root.exportImage(false)
        else if (ctrl && event.key === Qt.Key_S) root.exportImage(true)
        else return
        event.accepted = true
    }
    focus: true
}
