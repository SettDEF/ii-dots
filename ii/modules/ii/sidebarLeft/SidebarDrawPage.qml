// Sidebar Draw tab — fullscreen button (top-left) + drawable mid area
// + the rich draw toolbar (bottom). The middle area is a real DrawCanvas;
// strokes there are local to the sidebar (independent of the fullscreen
// overlay's canvas) but share tool/color via GlobalStates.
import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.screenDraw

Item {
    id: root

    // ── Drawable mid area — fills the sidebar down to the bottom.
    // The DrawCanvas's input MouseArea sets preventStealing:true on press,
    // so SwipeView can't yank the drag away mid-stroke.
    Rectangle {
        id: canvasFrame
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            right: parent.right
            topMargin: 8
            bottomMargin: 8
            leftMargin: 8
            rightMargin: 8
        }
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        clip: true

        // Subtle dotted backdrop — Miro-style
        Canvas {
            anchors.fill: parent
            antialiasing: false
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = Appearance.m3colors.darkmode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
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

        // ── Floating Top-left: open-fullscreen button ─────────────────────
        Rectangle {
            id: fsBtn
            anchors {
                top: parent.top
                left: parent.left
                margins: 8
            }
            width: 28
            height: 28
            radius: 14
            color: fsHov.hovered
                ? Appearance.colors.colSecondaryContainer
                : Appearance.colors.colLayer2
            Behavior on color { ColorAnimation { duration: 120 } }
            z: 10
            property bool hovered: fsHov.hovered
            HoverHandler { id: fsHov }
            TapHandler {
                onTapped: {
                    GlobalStates.sidebarLeftOpen = false
                    GlobalStates.screenDrawFullOpen = true
                }
            }
            MaterialSymbol {
                anchors.centerIn: parent
                text: "open_in_full"
                iconSize: 14
                color: fsHov.hovered ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
            }
            StyledToolTip {
                text: Translation.tr("Fullscreen")
            }
        }

        // Right-click context menu handler (wallpaper-picker style)
        MouseArea {
            id: canvasCtxMenuArea
            anchors.fill: parent
            z: 2 // Sit on top of DrawCanvas to intercept right clicks
            acceptedButtons: Qt.RightButton
            onClicked: event => {
                const sidebarContentRoot = ObjectUtils.findAncestorWith(canvasCtxMenuArea, "showContextMenu");
                if (sidebarContentRoot) {
                    const items = [
                        { icon: "edit", label: Translation.tr("Pen"), onTriggered: () => GlobalStates.drawTool = "pen" },
                        { icon: "brush", label: Translation.tr("Brush"), onTriggered: () => GlobalStates.drawTool = "brush" },
                        { icon: "format_color_fill", label: Translation.tr("Highlighter"), onTriggered: () => GlobalStates.drawTool = "highlighter" },
                        { icon: "ink_eraser", label: Translation.tr("Eraser"), onTriggered: () => GlobalStates.drawTool = "eraser" },
                        { separator: true },
                        { icon: "undo", label: Translation.tr("Undo"), onTriggered: () => GlobalStates.drawUndo() },
                        { icon: "redo", label: Translation.tr("Redo"), onTriggered: () => GlobalStates.drawRedo() },
                        { icon: "delete", danger: true, label: Translation.tr("Clear"), onTriggered: () => GlobalStates.drawClear() },
                        { separator: true },
                        { icon: "save", label: Translation.tr("Save drawing"), onTriggered: () => GlobalStates.drawSave() },
                        { icon: "open_in_full", label: Translation.tr("Fullscreen"), onTriggered: () => {
                            GlobalStates.sidebarLeftOpen = false
                            GlobalStates.screenDrawFullOpen = true
                        }}
                    ];
                    sidebarContentRoot.showContextMenu(canvasCtxMenuArea, event.x, event.y, items);
                }
            }
        }

        DrawCanvas {
            id: mini
            anchors.fill: parent
            tool:        GlobalStates.drawTool
            strokeColor: GlobalStates.drawColor
        }
        // Bridge global toolbar actions to this local canvas while the
        // sidebar tab is the active control surface (overlay also bridges
        // the same signals — at most one canvas reacts at a time because
        // the sidebar closes when fullscreen opens).
        Connections {
            target: GlobalStates
            enabled: GlobalStates.sidebarLeftOpen && !GlobalStates.screenDrawFullOpen
            function onDrawUndo()  { mini.undo() }
            function onDrawRedo()  { mini.redo() }
            function onDrawClear() { mini.clear() }
        }

        // ── Floating Bottom: shared toolbar — tool / color / undo / redo / save / clear
        DrawTools {
            id: tools
            anchors {
                bottom: parent.bottom
                horizontalCenter: parent.horizontalCenter
                bottomMargin: 12
            }
            z: 10
            tool:        GlobalStates.drawTool
            strokeColor: GlobalStates.drawColor
            onToolPicked: function(t) { GlobalStates.drawTool = t }
            onColorCyclePressed: colorPicker.open = !colorPicker.open
            onUndoPressed:  GlobalStates.drawUndo()
            onRedoPressed:  GlobalStates.drawRedo()
            onClearPressed: GlobalStates.drawClear()
            onSavePressed:  GlobalStates.drawSave()
        }

        // Loader, not just visible:false - an instantiated picker keeps its
        // Canvas and bindings alive while the panel is closed.
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
                width: Math.min(implicitWidth, colorPicker.parent.width - 24)
                selectedColor: GlobalStates.drawColor
                onPicked: function(c) { GlobalStates.drawColor = c }
            }
        }
    }
}
