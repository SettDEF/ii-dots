// DrawTools — the expanding bottom-pill toolbar for drawing surfaces.
// Used by both ScreenDrawContent (fullscreen overlay) and the wider
// ScreenDrawSidebar so toolbar code lives in one place.
//
// Public API
//   property string tool                  pen | brush | highlighter | eraser
//   property color  strokeColor
//   signal undoPressed()
//   signal redoPressed()
//   signal savePressed()
//   signal clearPressed()
//   signal toolPicked(string newTool)
//   signal colorCyclePressed()
import QtQuick
import QtQuick.Shapes
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    // ── Public state ─────────────────────────────────────────────────────
    property string tool: "pen"
    property color  strokeColor: "#ff5a5a"

    // ── Public signals ───────────────────────────────────────────────────
    signal undoPressed()
    signal redoPressed()
    signal savePressed()
    signal clearPressed()
    signal toolPicked(string newTool)
    signal colorCyclePressed()

    // ── Tool shapes mapping ──────────────────────────────────────────────
    readonly property var toolShapes: ({
        "pen": MaterialShape.Shape.Pill,
        "brush": MaterialShape.Shape.Clover4Leaf,
        "highlighter": MaterialShape.Shape.SoftBurst,
        "eraser": MaterialShape.Shape.Cookie7Sided
    })

    readonly property var toolIcons: ({
        "pen": "edit",
        "brush": "brush",
        "highlighter": "format_color_fill",
        "eraser": "ink_eraser"
    })

    // ── Sizing & Sates ───────────────────────────────────────────────────
    readonly property real availableWidth: parent ? parent.width : 420
    
    // Auto-collapse on hover leave, toggle manually on tap.
    property bool manualOpen: false

    // What the expanded row actually needs, derived from the same numbers the
    // groups below are built from. The gate used to be a hardcoded 440, which
    // the 460px left sidebar never reaches once its gaps and margins come off —
    // so the expand button silently did nothing there.
    readonly property int btnSize: 36
    readonly property int btnGap: 4
    readonly property int historyWidth: btnSize + btnGap + btnSize + btnGap + 1
    readonly property int toolsWidth: 4 * btnSize + 3 * btnGap
    readonly property int actionsWidth: 1 + btnGap + btnSize + btnGap + btnSize
    readonly property int expandedWidth:
        historyWidth + toolsWidth + btnSize + actionsWidth + 3 * btnGap + 16

    readonly property bool expanded:
        (manualOpen || hoverArea.hovered) && availableWidth >= root.expandedWidth

    implicitHeight: 50
    implicitWidth: Math.min(mainRow.implicitWidth + 16, Math.max(0, availableWidth - 16))
    radius: 25
    clip: true
    color: Appearance.m3colors.m3surfaceContainerHigh
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    Behavior on implicitWidth { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

    HoverHandler { id: hoverArea }

    Row {
        id: mainRow
        anchors.centerIn: parent
        spacing: 4

        // 1. History Group (collapsible)
        Item {
            width: root.expanded ? (36 + 4 + 36 + 4 + 1) : 0
            opacity: root.expanded ? 1 : 0
            clip: true
            height: 36
            anchors.verticalCenter: parent.verticalCenter
            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Row {
                spacing: 4
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                TbBtn { icon: "undo"; restRadius: 12; onPressed: root.undoPressed() }
                TbBtn { icon: "redo"; restRadius: 12; onPressed: root.redoPressed() }
                Rectangle { width: 1; height: 24; color: Appearance.colors.colOutline; opacity: 0.5; anchors.verticalCenter: parent.verticalCenter }
            }
        }

        // 2. Tools Group (active tool always visible, others slide out)
        Item {
            width: root.expanded ? (4 * 36 + 3 * 4) : 36
            clip: true
            height: 36
            anchors.verticalCenter: parent.verticalCenter
            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

            Row {
                spacing: 4
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    // Place the active tool at index 0 so it stays visible when collapsed
                    model: [root.tool].concat(["pen", "brush", "highlighter", "eraser"].filter(t => t !== root.tool))
                    delegate: ShapedButton {
                        id: sBtn
                        required property string modelData
                        shape: root.toolShapes[modelData]
                        icon: root.toolIcons[modelData]
                        active: root.tool === modelData
                        onPressed: {
                            root.toolPicked(modelData)
                            root.manualOpen = false
                        }
                    }
                }
            }
        }

        // 3. Swatch (always visible)
        Rectangle {
            id: swatch
            width: 36; height: 36; radius: 18
            color: root.strokeColor
            border.width: 2
            border.color: colHov.hovered ? Appearance.m3colors.m3onSurface : Appearance.colors.colOutline
            anchors.verticalCenter: parent.verticalCenter
            scale: tap2.pressed ? 0.88 : 1
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            HoverHandler { id: colHov }
            TapHandler   { id: tap2; onTapped: root.colorCyclePressed() }
        }

        // 4. Actions Group (collapsible)
        Item {
            width: root.expanded ? (1 + 4 + 36 + 4 + 36) : 0
            opacity: root.expanded ? 1 : 0
            clip: true
            height: 36
            anchors.verticalCenter: parent.verticalCenter
            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Row {
                spacing: 4
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                Rectangle { width: 1; height: 24; color: Appearance.colors.colOutline; opacity: 0.5; anchors.verticalCenter: parent.verticalCenter }
                TbBtn { icon: "save"; restRadius: 12; onPressed: root.savePressed() }
                TbBtn { icon: "delete"; restRadius: 12; danger: true; onPressed: root.clearPressed() }
            }
        }

        // 5. Expand/Collapse Chevron (always visible)
        TbBtn {
            id: toggleBtn
            icon: "chevron_left"
            restRadius: 18
            active: root.manualOpen
            rotation: root.expanded ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            onPressed: root.manualOpen = !root.manualOpen
        }
    }

    // Button template component inside mainRow
    component TbBtn: Rectangle {
        id: btn
        required property string icon
        property bool active: false
        property bool danger: false
        property real restRadius: 18
        property real pressedRadius: 10
        property real activeRadius: 14
        signal pressed()
        width: 36; height: 36
        radius: tap.pressed ? pressedRadius
              : active ? activeRadius
              : restRadius
        Behavior on radius { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
        color: active ? Appearance.colors.colPrimary
             : (btnHov.hovered ? Appearance.m3colors.m3surfaceContainerHighest : "transparent")
        Behavior on color { ColorAnimation { duration: 140 } }
        scale: tap.pressed ? 0.92 : 1
        Behavior on scale  { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        MaterialSymbol {
            anchors.centerIn: parent
            text: btn.icon
            iconSize: Appearance.font.pixelSize.normal
            color: btn.active
                ? Appearance.m3colors.m3onPrimary
                : (btn.danger ? Appearance.m3colors.m3error : Appearance.m3colors.m3onSurface)
        }
        HoverHandler { id: btnHov }
        TapHandler   { id: tap; onTapped: btn.pressed() }
    }
}
