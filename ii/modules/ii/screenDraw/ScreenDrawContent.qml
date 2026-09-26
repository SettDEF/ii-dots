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

    readonly property string home: `${Quickshell.env("HOME")}`
    readonly property string saveDir: home + "/.cache/quickshell/screendraw"
    readonly property string notesFile: home + "/.local/state/quickshell/screendraw-notes.json"

    // ── Drawing state proxies — bound to GlobalStates so the sidebar
    // toolbar (in the left sidebar's Draw tab) drives the same tool/color.
    property string tool:        GlobalStates.drawTool
    property color  strokeColor: GlobalStates.drawColor
    property real   strokeSize:  4

    // Bridge sidebar action signals → this overlay's canvas.
    Connections {
        target: GlobalStates
        function onDrawUndo()  { drawCanvas.undo() }
        function onDrawRedo()  { drawCanvas.redo() }
        function onDrawClear() { drawCanvas.clear() }
        function onDrawSave() {
            const ts = new Date()
            const stamp = ts.getFullYear() + "-" +
                String(ts.getMonth()+1).padStart(2,"0") + "-" +
                String(ts.getDate()).padStart(2,"0") + "_" +
                String(ts.getHours()).padStart(2,"0") +
                String(ts.getMinutes()).padStart(2,"0") +
                String(ts.getSeconds()).padStart(2,"0")
            drawCanvas.savePng(root.saveDir + "/drawing-" + stamp + ".png")
        }
    }

    // ── Sidebar state ────────────────────────────────────────────────────
    // Tab: "tools" (default collapsed peek) | "drawings" | "notes"
    property string sidebarTab: ""        // "" = collapsed
    property var    savedDrawings: []
    property string notesText: ""

    function refreshSavedDrawings() {
        savedScanProc.command = ["bash", "-c",
            `mkdir -p '${saveDir}'; find '${saveDir}' -maxdepth 1 -type f \\( -iname '*.png' \\) -printf '%T@ %p\\n' | sort -rn | awk '{print $2}' | head -n 40`]
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
    Process { id: saveDrawingProc }

    Component.onCompleted: {
        refreshSavedDrawings()
        loadNotes()
    }

    Timer {
        id: notesSaveDeb
        interval: 400
        onTriggered: root.saveNotes()
    }
    onNotesTextChanged: notesSaveDeb.restart()

    // Mouse position for the cursor preview (when tool === pen/eraser)
    property real cursorX: -100
    property real cursorY: -100
    // True while the mouse is over any UI chrome (toolbar / color popup /
    // sidebar). Hides the brush preview ring so it doesn't poke through.
    // Counter pattern because child handlers can swallow hover events from
    // the parent — each chrome element bumps the counter on enter/leave.
    property int  chromeHoverCount: 0
    readonly property bool overChrome: chromeHoverCount > 0

    // ── Background dim layer (lets the desktop show through subtly) ─────
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.05)
    }

    // ── Drawing canvas (shared component) ────────────────────────────────
    DrawCanvas {
        id: drawCanvas
        anchors.fill: parent
        tool:        root.tool
        strokeColor: root.strokeColor
        strokeSize:  root.strokeSize
    }

    // (Brush-size preview ring removed — the system cursor stays visible
    // everywhere, including over the toolbar/sidebar/color popup.)

    // ── Top-right: zoom + close ──────────────────────────────────────────
    RowLayout {
        anchors { top: parent.top; right: parent.right; margins: 16 }
        spacing: 8

        Rectangle {
            implicitWidth: 36; implicitHeight: 36; radius: 18
            color: closeHov.hovered ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerHighest
            border.width: 1; border.color: Appearance.colors.colLayer0Border
            HoverHandler { id: closeHov; onHoveredChanged: hovered ? root.chromeHoverCount++ : root.chromeHoverCount-- }
            TapHandler { onTapped: root.closeRequested() }
            MaterialSymbol {
                anchors.centerIn: parent
                text: "close"; iconSize: Appearance.font.pixelSize.normal
                color: closeHov.hovered ? Appearance.colors.colOnLayer1 : Appearance.m3colors.m3onSurface
            }
        }
    }


    // ── Bottom-left: sidebar tab pills ──────────────────────────────────
    Rectangle {
        id: sidebarRow
        anchors {
            bottom: parent.bottom
            left: parent.left
            bottomMargin: 18
            leftMargin: 18
        }
        height: 50
        implicitWidth: srRow.implicitWidth + 14
        radius: 25
        color: Appearance.m3colors.m3surfaceContainerHigh
        border.width: 1; border.color: Appearance.colors.colLayer0Border

        Row {
            id: srRow
            anchors.centerIn: parent
            spacing: 4

            component SrBtn: Rectangle {
                id: sb
                required property string icon
                property bool active: false
                signal pressed()
                width: 36; height: 36; radius: 18
                color: active ? Appearance.colors.colPrimary
                     : (sbHov.hovered ? Appearance.m3colors.m3surfaceContainerHighest : "transparent")
                Behavior on color { ColorAnimation { duration: 100 } }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: sb.icon
                    iconSize: Appearance.font.pixelSize.normal
                    color: sb.active ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurface
                }
                HoverHandler { id: sbHov; onHoveredChanged: hovered ? root.chromeHoverCount++ : root.chromeHoverCount-- }
                TapHandler { onTapped: sb.pressed() }
            }

            SrBtn {
                icon: "image"
                active: root.sidebarTab === "drawings"
                onPressed: { root.sidebarTab = root.sidebarTab === "drawings" ? "" : "drawings"; root.refreshSavedDrawings() }
            }
            SrBtn {
                icon: "edit_note"
                active: root.sidebarTab === "notes"
                onPressed: { root.sidebarTab = root.sidebarTab === "notes" ? "" : "notes" }
            }
        }
    }

    // ── Pop-up content panel above the tab row ──────────────────────────
    Rectangle {
        id: tabPanel
        visible: root.sidebarTab !== ""
        anchors {
            bottom: sidebarRow.top; left: sidebarRow.left
            bottomMargin: 8
        }
        width: 320; height: 360
        radius: 14
        color: Appearance.m3colors.m3surfaceContainerHigh
        border.width: 1; border.color: Appearance.colors.colLayer0Border
        HoverHandler { onHoveredChanged: hovered ? root.chromeHoverCount++ : root.chromeHoverCount-- }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 10; spacing: 8
            visible: root.sidebarTab === "drawings"
            StyledText {
                text: qsTr("Saved drawings")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: Appearance.m3colors.m3onSurface; opacity: 0.8
            }
            StyledText {
                visible: root.savedDrawings.length === 0
                Layout.fillWidth: true
                text: qsTr("No drawings yet — use 'Save' on the toolbar.")
                font.pixelSize: Appearance.font.pixelSize.smaller - 2
                color: Appearance.m3colors.m3onSurface; opacity: 0.5
                wrapMode: Text.WordWrap
            }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true
                visible: root.savedDrawings.length > 0
                model: root.savedDrawings
                spacing: 6
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    required property string modelData
                    width: ListView.view.width
                    height: 70; radius: 8
                    color: dHov.hovered ? Appearance.m3colors.m3surfaceContainerHighest : "transparent"
                    Image {
                        anchors.fill: parent; anchors.margins: 4
                        source: "file://" + modelData
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true; smooth: true; cache: false
                    }
                    StyledText {
                        anchors { left: parent.left; bottom: parent.bottom; leftMargin: 6; bottomMargin: 4 }
                        text: modelData.split("/").pop()
                        font.pixelSize: Appearance.font.pixelSize.smaller - 3
                        color: Appearance.m3colors.m3onSurface; opacity: 0.85; elide: Text.ElideMiddle
                    }
                    HoverHandler { id: dHov }
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 10; spacing: 8
            visible: root.sidebarTab === "notes"
            StyledText {
                text: qsTr("Notes")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: Appearance.m3colors.m3onSurface; opacity: 0.8
            }
            ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true
                TextArea {
                    text: root.notesText
                    onTextChanged: root.notesText = text
                    wrapMode: TextArea.Wrap
                    color: Appearance.m3colors.m3onSurface
                    background: Rectangle {
                        color: Qt.rgba(1,1,1,0.05)
                        radius: 8
                        border.width: 1; border.color: Appearance.colors.colLayer0Border
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    placeholderText: qsTr("Type notes here — saved automatically.")
                    placeholderTextColor: Qt.rgba(1,1,1,0.35)
                }
            }
        }
    }

    // ── Bottom-center: drawing tools (shared component) ─────────────────
    DrawTools {
        id: tools
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: 18
        }
        tool: root.tool
        strokeColor: root.strokeColor
        HoverHandler { onHoveredChanged: hovered ? root.chromeHoverCount++ : root.chromeHoverCount-- }
        onUndoPressed:  drawCanvas.undo()
        onRedoPressed:  drawCanvas.redo()
        onClearPressed: drawCanvas.clear()
        onToolPicked:  function(t) { GlobalStates.drawTool = t }
        // The swatch opens the picker, same as the sidebar. It used to step
        // through a hardcoded list, which is why the fullscreen overlay had no
        // way to reach the palettes at all.
        onColorCyclePressed: colorPicker.open = !colorPicker.open
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
            saveDrawingProc.command = ["bash", "-c", `mkdir -p '${root.saveDir}'`]
            saveDrawingProc.running = true
            Qt.callLater(root.refreshSavedDrawings)
        }
    }

    // Loader, not visible:false — an instantiated picker keeps its Canvas and
    // bindings alive while it is closed.
    Loader {
        id: colorPicker
        property bool open: false
        active: open
        visible: open
        z: 11
        anchors {
            bottom: tools.top
            horizontalCenter: parent.horizontalCenter
            bottomMargin: 10
        }
        sourceComponent: ZenColorPicker {
            selectedColor: GlobalStates.drawColor
            onPicked: function(c) { GlobalStates.drawColor = c }
        }
    }

    // Esc closes
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
            root.closeRequested()
            event.accepted = true
        }
    }
    focus: true
}
