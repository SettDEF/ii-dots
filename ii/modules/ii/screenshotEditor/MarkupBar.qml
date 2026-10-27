pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

// The screenshot editor's markup bar, as Windows' Snipping Tool: pens, shapes, text, redact and
// crop; the colours of the theme and a size; undo / redo; the text actions (copy all the text, hide
// e-mails and numbers); copy and save. Each tool its own theme hue.
Toolbar {
    id: root
    property string tool: "pen"
    property color strokeColor: Appearance.colors.colHueRed
    property real strokeSize: 4
    property bool busy: false
    signal toolPicked(string t)
    signal colorPicked(color c)
    signal sizePicked(real s)
    signal undo()
    signal redo()
    signal copyText()
    signal quickRedact()
    signal copyImage()
    signal save()
    signal close()

    readonly property var groups: [
        [{ t: "pen", icon: "edit", tip: Translation.tr("Pen"), hue: Appearance.colors.colHueBlue },
         { t: "highlighter", icon: "ink_highlighter", tip: Translation.tr("Highlighter"), hue: Appearance.colors.colHueYellow },
         { t: "eraser", icon: "ink_eraser", tip: Translation.tr("Eraser"), hue: Appearance.colors.colHueMagenta }],
        [{ t: "rect", icon: "rectangle", tip: Translation.tr("Rectangle"), hue: Appearance.colors.colHueCyan },
         { t: "ellipse", icon: "circle", tip: Translation.tr("Ellipse"), hue: Appearance.colors.colHueCyan },
         { t: "arrow", icon: "arrow_outward", tip: Translation.tr("Arrow"), hue: Appearance.colors.colHueCyan },
         { t: "line", icon: "horizontal_rule", tip: Translation.tr("Line"), hue: Appearance.colors.colHueCyan },
         { t: "text", icon: "title", tip: Translation.tr("Text: click, type, Enter"), hue: Appearance.colors.colHueGreen }],
        [{ t: "redact", icon: "visibility_off", tip: Translation.tr("Redact: drag over what to hide"), hue: Appearance.colors.colHueRed },
         { t: "crop", icon: "crop", tip: Translation.tr("Crop: drag what to keep"), hue: Appearance.colors.colHueGreen }],
    ]
    readonly property var swatches: [Appearance.colors.colHueRed, Appearance.colors.colHueYellow, Appearance.colors.colHueGreen,
                                     Appearance.colors.colHueBlue, Appearance.colors.colHueMagenta, "#ffffff", "#000000"]

    Repeater {
        model: root.groups
        delegate: RowLayout {
            id: grp
            required property var modelData
            required property int index
            Layout.fillHeight: true
            spacing: 2
            Rectangle { visible: grp.index > 0; Layout.alignment: Qt.AlignVCenter; implicitWidth: 1; implicitHeight: 22; color: Appearance.colors.colOutlineVariant }
            Repeater {
                model: grp.modelData
                delegate: HueToolbarButton {
                    id: tb
                    required property var modelData
                    hue: tb.modelData.hue
                    symbol: tb.modelData.icon
                    toggled: root.tool === tb.modelData.t
                    onClicked: root.toolPicked(tb.modelData.t)
                    StyledToolTip { text: tb.modelData.tip }
                }
            }
        }
    }

    Rectangle { Layout.alignment: Qt.AlignVCenter; implicitWidth: 1; implicitHeight: 22; color: Appearance.colors.colOutlineVariant }

    // the theme's colours, and the size (scroll or click it)
    Row {
        Layout.alignment: Qt.AlignVCenter
        spacing: 4
        Repeater {
            model: root.swatches
            delegate: Rectangle {
                id: sw
                required property color modelData
                width: 20; height: 20; radius: 10
                color: sw.modelData
                border.width: Qt.colorEqual(root.strokeColor, sw.modelData) ? 2 : 1
                border.color: Qt.colorEqual(root.strokeColor, sw.modelData) ? Appearance.colors.colOnLayer0 : Appearance.colors.colOutlineVariant
                scale: swm.containsMouse ? 1.15 : 1
                Behavior on scale { NumberAnimation { duration: 120 } }
                MouseArea { id: swm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.colorPicked(sw.modelData) }
            }
        }
    }
    ToolbarButton {
        implicitWidth: 40
        padding: 0
        onClicked: root.sizePicked(root.strokeSize >= 12 ? 2 : root.strokeSize * 2)
        WheelHandler { onWheel: e => root.sizePicked(Math.max(1, Math.min(16, root.strokeSize + (e.angleDelta.y > 0 ? 1 : -1)))) }
        contentItem: Item {
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(22, root.strokeSize * 1.6 + 3); height: width; radius: width / 2
                color: root.strokeColor
            }
        }
        StyledToolTip { text: Translation.tr("Size %1 (click or scroll)").arg(root.strokeSize) }
    }

    Rectangle { Layout.alignment: Qt.AlignVCenter; implicitWidth: 1; implicitHeight: 22; color: Appearance.colors.colOutlineVariant }

    HueToolbarButton { symbol: "undo"; onClicked: root.undo(); StyledToolTip { text: Translation.tr("Undo (Ctrl+Z)") } }
    HueToolbarButton { symbol: "redo"; onClicked: root.redo(); StyledToolTip { text: Translation.tr("Redo (Ctrl+Y)") } }

    Rectangle { Layout.alignment: Qt.AlignVCenter; implicitWidth: 1; implicitHeight: 22; color: Appearance.colors.colOutlineVariant }

    // text actions
    HueToolbarButton {
        hue: Appearance.colors.colHueGreen
        symbol: root.busy ? "hourglass_top" : "content_paste_go"
        onClicked: root.copyText()
        StyledToolTip { text: Translation.tr("Copy all the text in it") }
    }
    HueToolbarButton {
        hue: Appearance.colors.colHueRed
        symbol: "shield_lock"
        onClicked: root.quickRedact()
        StyledToolTip { text: Translation.tr("Quick redact: hide e-mails, phone and card numbers, IPs") }
    }

    Rectangle { Layout.alignment: Qt.AlignVCenter; implicitWidth: 1; implicitHeight: 22; color: Appearance.colors.colOutlineVariant }

    HueToolbarButton { hue: Appearance.colors.colHueBlue; symbol: "content_copy"; onClicked: root.copyImage(); StyledToolTip { text: Translation.tr("Copy (Ctrl+C)") } }
    HueToolbarButton { hue: Appearance.colors.colHueBlue; symbol: "save"; onClicked: root.save(); StyledToolTip { text: Translation.tr("Save to Pictures/Screenshots (Ctrl+S)") } }
    HueToolbarButton { hue: Appearance.colors.colHueRed; symbol: "close"; onClicked: root.close(); StyledToolTip { text: Translation.tr("Close (Esc)") } }
}
