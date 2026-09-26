// Editor content — screenshot as backdrop, DrawCanvas for annotations,
// DrawTools toolbar at the bottom (reused from screenDraw module).
// Save merges the canvas into the original image and overwrites it.
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
    property color  strokeColor: "#ff5a5a"
    property real   strokeSize: 4

    // ── Single card — its 4 px border doubles as the only visible chrome.
    Rectangle {
        id: card
        anchors {
            fill: parent
            margins: 12
        }
        radius: 22
        color: Appearance.m3colors.m3surfaceContainerHigh   // shows as the 4 px "border" around the image
        border.width: 1; border.color: Appearance.colors.colLayer0Border
        clip: true

        Image {
            id: img
            anchors {
                fill: parent
                margins: 4
                bottomMargin: 76   // leaves room for the bottom toolbar inside card
                topMargin: 48      // leaves room for the close button inside card
            }
            source: root.imagePath !== "" ? "file://" + root.imagePath : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            cache: false
        }

        DrawCanvas {
            id: drawCanvas
            anchors.fill: img
            tool: root.tool
            strokeColor: root.strokeColor
            strokeSize: root.strokeSize
        }
    }

    // ── Top-right close ─────────────────────────────────────────────────
    Rectangle {
        anchors { top: parent.top; right: parent.right; margins: 16 }
        width: 32; height: 32; radius: 16
        color: closeHov.hovered ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerHighest
        HoverHandler { margin: Appearance.sizes.touchSlop; id: closeHov }
        TapHandler { margin: Appearance.sizes.touchSlop; onTapped: root.closeRequested() }
        MaterialSymbol {
            anchors.centerIn: parent
            text: "close"
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.m3colors.m3onSurface
            opacity: closeHov.hovered ? 1 : 0.8
        }
    }

    // ── Bottom toolbar (shared component from screenDraw) ──────────────
    DrawTools {
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: 24
        }
        tool: root.tool
        strokeColor: root.strokeColor
        onUndoPressed:  drawCanvas.undo()
        onRedoPressed:  drawCanvas.redo()
        onClearPressed: drawCanvas.clear()
        onToolPicked:   function(t) { root.tool = t }
        onColorCyclePressed: {
            const palette = ["#ff5a5a", "#f5d36e", "#5af7a8", "#5ab8f7",
                             "#c4a4f7", "#f7a8c4", "#ffffff", "#000000"]
            const i = palette.indexOf(String(root.strokeColor))
            root.strokeColor = palette[(i + 1) % palette.length]
        }
        // Save → write to ~/Pictures/Screenshots, copy to clipboard,
        // notify with the path (click the notification to open it).
        onSavePressed: {
            const overlay = "/tmp/quickshell-snip-overlay.png"

            const ts = new Date()
            const stamp = ts.getFullYear() + "-" +
                String(ts.getMonth()+1).padStart(2,"0") + "-" +
                String(ts.getDate()).padStart(2,"0") + "_" +
                String(ts.getHours()).padStart(2,"0") +
                String(ts.getMinutes()).padStart(2,"0") +
                String(ts.getSeconds()).padStart(2,"0")
            const saveDir  = "/home/caesar/Pictures/Screenshots"
            const savePath = saveDir + "/screenshot-" + stamp + ".png"

            const shortPath = savePath.replace(/^\/home\/caesar\//, "~/")
            const cmd = ["bash", "-c", `
                LOG=/tmp/quickshell-snip-debug.log
                exec 2>"$LOG"
                set -x
                src='${root.imagePath}'
                overlay='${overlay}'
                save='${savePath}'
                saveDir='${saveDir}'
                pw=${Math.round(img.paintedWidth)}
                ph=${Math.round(img.paintedHeight)}
                mkdir -p "$saveDir"
                # If the source went away (closed too early or moved) just
                # save the overlay alone — better than failing silently.
                if [ ! -f "$src" ]; then
                    notify-send -a "Screenshot" -u critical \\
                        "Screenshot save failed" "Source missing: $src
See $LOG"
                    exit 1
                fi
                if "$HOME/.local/bin/tinct" image composite "$src" "$overlay" "\${pw}x\${ph}" "$save"; then
                    wl-copy < "$save" 2>/dev/null
                    rm -f "$overlay" "$src" 2>/dev/null
                    act=$(notify-send --wait -a "Screenshot" -i "$save" \\
                            -A "open=Open" -A "folder=Open folder" \\
                            "Screenshot saved" "${shortPath}
Copied to clipboard.")
                    case "$act" in
                        open)   xdg-open "$save" ;;
                        folder) xdg-open "$saveDir" ;;
                    esac
                else
                    notify-send -a "Screenshot" -u critical \\
                        "Screenshot save failed" "tinct failed — see $LOG"
                fi
            `]
            // grabPng's callback fires only after the overlay PNG is on
            // disk, so it can be read.
            drawCanvas.grabPng(overlay, function() {
                Quickshell.execDetached(cmd)
                root.closeRequested()
            })
        }
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
            root.closeRequested()
            event.accepted = true
        }
    }
    focus: true
}
