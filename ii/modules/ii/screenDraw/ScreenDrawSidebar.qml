// ScreenDrawSidebar — wider drawing sidebar (520 px) anchored to the right
// edge. Layout:
//
//   ┌─────────────────────────────────────────┐
//   │ ╭─╮  ┌───────────────────────────────┐  │
//   │ │•│  │                               │  │
//   │ │•│  │       Tab content area        │  │
//   │ │•│  │   (Draw / Notes / Saved)      │  │
//   │ │•│  │                               │  │
//   │ │•│  └───────────────────────────────┘  │
//   │ ╰─╯  ┌─ tools ─────────────────────┐    │
//   │      │ ⟲ ⟳ ✎ 🖌 ✏ ⌫ 🎨 💾 🗑      │    │
//   │      └─────────────────────────────┘    │
//   └─────────────────────────────────────────┘
//
// Vertical pill tab rail on the left edge (peach pills, image-style).
// Bottom toolbar exists only when the Draw tab is active.

pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Qt5Compat.GraphicalEffects

Item {
    id: root
    signal closeRequested()
    signal fullscreenRequested()

    readonly property string home: "/home/caesar"
    readonly property string saveDir: home + "/.cache/quickshell/screendraw"
    readonly property string notesFile: home + "/.local/state/quickshell/screendraw-notes.json"

    property string activeTab: "draw"   // draw | notes | saved
    property string tool: "pen"
    property color  strokeColor: "#ff5a5a"
    property real   strokeSize: 4
    // When true, the card has a margin on the right so it visually "pops out"
    // from the screen edge — a poor-man's float since layer-shell can't drag.
    property bool floating: false

    // ── Notes persistence ────────────────────────────────────────────────
    property string notesText: ""
    property var savedDrawings: []

    function refreshSaved() {
        savedScanProc.command = ["bash", "-c",
            `mkdir -p '${saveDir}'; find '${saveDir}' -maxdepth 1 -type f -iname '*.png' -printf '%T@ %p\\n' | sort -rn | awk '{print $2}' | head -n 40`]
        savedScanProc.running = true
    }
    function loadNotes() {
        notesLoadProc.command = ["bash", "-c",
            `f='${notesFile}'; [ -f "$f" ] && cat "$f" || echo '{}'`]
        notesLoadProc.running = true
    }
    function saveNotes() {
        const txt = JSON.stringify({ text: root.notesText }).replace(/'/g, "'\\''")
        notesSaveProc.command = ["bash", "-c",
            `mkdir -p "$(dirname '${notesFile}')" && printf '%s' '${txt}' > '${notesFile}'`]
        notesSaveProc.running = true
    }

    Process {
        id: savedScanProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.savedDrawings = text.trim().length === 0
                    ? [] : text.trim().split("\n")
            }
        }
    }
    Process {
        id: notesLoadProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text)
                    if (j.text !== undefined) root.notesText = j.text
                } catch(e) {}
            }
        }
    }
    Process { id: notesSaveProc }

    Timer { id: notesSaveDeb; interval: 400; onTriggered: root.saveNotes() }
    onNotesTextChanged: notesSaveDeb.restart()

    Component.onCompleted: { refreshSaved(); loadNotes() }

    // ── Card background ─────────────────────────────────────────────────
    Rectangle {
        anchors {
            fill: parent
            margins: 12
        }
        // Floating: margin on the left side too so the card pulls away from
        // the screen edge. Otherwise flush to the left.
        anchors.leftMargin: root.floating ? 24 : 12
        radius: 22
        color: Qt.rgba(0.10, 0.10, 0.13, 0.97)
        border.width: 1; border.color: Appearance.colors.colLayer0Border
        Behavior on anchors.leftMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        // ── Vertical pill tab rail (image-style: chevron + dot +
        //     elongated active pill + short inactive pills) ───────────────
        Column {
            id: rail
            anchors {
                left: parent.left; leftMargin: 8
                top: parent.top; topMargin: 16
            }
            spacing: 6
            z: 5

            // Chevron toggle (closes sidebar)
            Item {
                width: 16; height: 16
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "chevron_right"
                    iconSize: 16
                    color: "#f0c8a8"
                }
                HoverHandler { id: chevHov }
                TapHandler { onTapped: root.closeRequested() }
            }

            // Tiny indicator dot — represents the current selection
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 8; height: 8; radius: 4
                color: "#f0c8a8"
            }

            // ── Tab pills ──
            // Active = tall elongated pill, inactive = short squarish pill.
            component RailPill: Rectangle {
                id: pill
                required property string tabId
                property bool active: root.activeTab === pill.tabId
                signal pressed()
                anchors.horizontalCenter: parent.horizontalCenter
                width: 16
                height: active ? 80 : 22
                radius: 8
                color: active ? "#f0c8a8" : "#5a3528"
                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on color  { ColorAnimation  { duration: 140 } }
                opacity: pillHov.hovered || active ? 1 : 0.85
                Behavior on opacity { NumberAnimation { duration: 100 } }

                HoverHandler { id: pillHov }
                TapHandler { onTapped: pill.pressed() }
            }

            RailPill {
                tabId: "draw"
                onPressed: root.activeTab = "draw"
            }
            RailPill {
                tabId: "notes"
                onPressed: root.activeTab = "notes"
            }
            RailPill {
                tabId: "saved"
                onPressed: { root.activeTab = "saved"; root.refreshSaved() }
            }

        }

        // ── Top-right action row: drag / fullscreen / close ─────────────
        Row {
            anchors { top: parent.top; right: parent.right; margins: 14 }
            spacing: 6

            component HeadBtn: Rectangle {
                id: hb
                required property string icon
                signal pressed()
                width: 30; height: 30; radius: 15
                color: hbHov.hovered ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerHighest
                Behavior on color { ColorAnimation { duration: 100 } }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: hb.icon
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.m3colors.m3onSurface
                    opacity: hbHov.hovered ? 1 : 0.8
                }
                HoverHandler { id: hbHov }
                TapHandler { onTapped: hb.pressed() }
            }

            HeadBtn {
                icon: root.floating ? "dock_to_left" : "drag_indicator"
                onPressed: root.floating = !root.floating
            }
            HeadBtn {
                icon: "open_in_full"
                onPressed: root.fullscreenRequested()
            }
            HeadBtn {
                icon: "close"
                onPressed: root.closeRequested()
            }
        }

        // ── Tab content area ─────────────────────────────────────────────
        Item {
            id: content
            anchors {
                left: rail.right; leftMargin: 14
                right: parent.right; rightMargin: 14
                top: parent.top; topMargin: 56
                bottom: toolbar.visible ? toolbar.top : parent.bottom
                bottomMargin: 14
            }

            // Subtle dotted backdrop — Miro-style
            Canvas {
                anchors.fill: parent
                visible: root.activeTab === "draw"
                antialiasing: false
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.fillStyle = Qt.rgba(1,1,1,0.06)
                    const step = 22
                    for (let y = step; y < height; y += step)
                        for (let x = step; x < width; x += step) {
                            ctx.beginPath(); ctx.arc(x, y, 0.9, 0, Math.PI*2); ctx.fill()
                        }
                }
                Component.onCompleted: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
            }

            // ── Draw tab — DrawCanvas + saved-on-demand ────────────────
            DrawCanvas {
                id: drawCanvas
                anchors.fill: parent
                visible: root.activeTab === "draw"
                tool: root.tool
                strokeColor: root.strokeColor
                strokeSize: root.strokeSize
            }

            // ── Notes tab ─────────────────────────────────────────────
            ScrollView {
                anchors.fill: parent
                visible: root.activeTab === "notes"
                TextArea {
                    text: root.notesText
                    onTextChanged: root.notesText = text
                    wrapMode: TextArea.Wrap
                    color: Appearance.m3colors.m3onSurface
                    background: Rectangle {
                        color: Qt.rgba(1,1,1,0.05)
                        radius: 12
                        border.width: 1; border.color: Appearance.colors.colLayer0Border
                    }
                    font.pixelSize: Appearance.font.pixelSize.small
                    placeholderText: qsTr("Type notes here — saved automatically.")
                    placeholderTextColor: Qt.rgba(1,1,1,0.35)
                }
            }

            // ── Saved drawings tab ────────────────────────────────────
            ListView {
                anchors.fill: parent
                visible: root.activeTab === "saved"
                model: root.savedDrawings
                spacing: 6
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    required property string modelData
                    width: ListView.view.width
                    height: 90
                    radius: 10
                    color: thHov.hovered ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainer
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Image {
                        anchors.fill: parent; anchors.margins: 6
                        source: "file://" + modelData
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true; smooth: true; cache: false
                    }
                    StyledText {
                        anchors { left: parent.left; bottom: parent.bottom; leftMargin: 8; bottomMargin: 6 }
                        text: modelData.split("/").pop()
                        font.pixelSize: Appearance.font.pixelSize.smaller - 2
                        color: Appearance.m3colors.m3onSurface; opacity: 0.85
                        elide: Text.ElideMiddle
                    }
                    HoverHandler { id: thHov }
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: root.activeTab === "saved" && root.savedDrawings.length === 0
                text: qsTr("No drawings saved yet")
                color: Appearance.m3colors.m3onSurface; opacity: 0.4
                font.pixelSize: Appearance.font.pixelSize.normal
            }
        }

        // ── Bottom toolbar — shared component ────────────────────────────
        DrawTools {
            visible: root.activeTab === "draw"
            anchors {
                bottom: parent.bottom
                horizontalCenter: parent.horizontalCenter
                bottomMargin: 14
            }
            tool: root.tool
            strokeColor: root.strokeColor
            onUndoPressed:  drawCanvas.undo()
            onRedoPressed:  drawCanvas.redo()
            onClearPressed: drawCanvas.clear()
            onToolPicked:  function(t) { root.tool = t }
            onColorCyclePressed: {
                const palette = ["#ff5a5a", "#f5d36e", "#5af7a8", "#5ab8f7",
                                 "#c4a4f7", "#f7a8c4", "#ffffff", "#000000"]
                const i = palette.indexOf(String(root.strokeColor))
                root.strokeColor = palette[(i + 1) % palette.length]
            }
            onSavePressed: {
                const ts = new Date()
                const stamp = ts.getFullYear() + "-" +
                    String(ts.getMonth()+1).padStart(2,"0") + "-" +
                    String(ts.getDate()).padStart(2,"0") + "_" +
                    String(ts.getHours()).padStart(2,"0") +
                    String(ts.getMinutes()).padStart(2,"0") +
                    String(ts.getSeconds()).padStart(2,"0")
                const out = root.saveDir + "/drawing-" + stamp + ".png"
                drawCanvas.savePng(out)
                Qt.callLater(root.refreshSaved)
            }
        }
    }
}
