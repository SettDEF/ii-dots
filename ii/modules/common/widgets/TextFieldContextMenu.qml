// Themed replacement for Qt's built-in text context menu.
//
// Qt 6.9 gave TextInput/TextField a DEFAULT context menu, drawn by Qt with no
// styling hook — on this shell it appears as a stock grey Undo/Redo/Cut/Copy/
// Paste/Delete/Select-All list that matches nothing around it. There is no
// `contextMenu` property to turn it off (QQuickTextField exposes none, and this
// Qt build ships no Controls qmltypes to declare one), so the only reliable
// suppression is to consume the right-click before the field sees it — see
// ToolbarTextField, which puts a RightButton-only MouseArea above the content.
//
// A PopupWindow rather than an in-window overlay because the hosts of this
// widget (notably the launcher) mask their layer-surface input to specific
// regions, where an overlay renders but never receives clicks.
import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

PopupWindow {
    id: root

    // The text field this menu acts on.
    required property Item field
    color: "transparent"

    function openAt(x, y) {
        root._x = x
        root._y = y
        root.visible = true
    }
    function close() { root.visible = false }

    property real _x: 0
    property real _y: 0

    readonly property bool hasSelection: (field?.selectedText ?? "").length > 0
    readonly property bool hasText: (field?.text ?? "").length > 0
    readonly property bool canPaste: (Quickshell.clipboardText ?? "").length > 0

    anchor {
        window: field ? field.QsWindow.window : null
        gravity: Edges.Bottom | Edges.Right
        edges: Edges.Bottom | Edges.Right
        adjustment: PopupAdjustment.Flip | PopupAdjustment.SlideX
        // Guarded: mapFromItem() throws if evaluated before the field belongs
        // to a window.
        rect: (root.visible && field && field.QsWindow?.window)
            ? Qt.rect(field.QsWindow.mapFromItem(field, root._x, root._y).x,
                      field.QsWindow.mapFromItem(field, root._x, root._y).y,
                      1, 1)
            : Qt.rect(0, 0, 1, 1)
    }

    implicitWidth: panel.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: panel.implicitHeight + Appearance.sizes.elevationMargin * 2

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: root.close()
        onWheel: wheel => wheel.accepted = true
    }

    StyledRectangularShadow { target: panel }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        implicitWidth: 190
        implicitHeight: col.implicitHeight + 12
        radius: Appearance.rounding.small
        // m3surfaceContainer, not colLayer1: colLayer1 is solveOverlayColor()'d
        // against the shell backdrop and reads see-through in its own window.
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        focus: root.visible
        Keys.onEscapePressed: event => { root.close(); event.accepted = true }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            spacing: 1

            component Row_: RippleButton {
                Layout.fillWidth: true
                implicitHeight: 30
                buttonRadius: Appearance.rounding.verysmall
                property string rowIcon: ""
                property string rowLabel: ""
                // `icon` and `label` are FINAL on Button — hence the row* names.
                contentItem: RowLayout {
                    spacing: 8
                    MaterialSymbol {
                        Layout.leftMargin: 4
                        text: rowIcon
                        iconSize: Appearance.font.pixelSize.large
                        color: enabled ? Appearance.colors.colOnLayer1
                                       : Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: rowLabel
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: enabled ? Appearance.colors.colOnLayer1
                                       : Appearance.colors.colSubtext
                    }
                }
            }

            Row_ {
                rowIcon: "content_cut"
                rowLabel: Translation.tr("Cut")
                enabled: root.hasSelection
                onClicked: { root.field.cut(); root.close() }
            }
            Row_ {
                rowIcon: "content_copy"
                rowLabel: Translation.tr("Copy")
                enabled: root.hasSelection
                onClicked: { root.field.copy(); root.close() }
            }
            Row_ {
                rowIcon: "content_paste"
                rowLabel: Translation.tr("Paste")
                enabled: root.canPaste
                onClicked: { root.field.paste(); root.close() }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 3
                Layout.bottomMargin: 3
                implicitHeight: 1
                color: Appearance.colors.colLayer0Border
            }
            Row_ {
                rowIcon: "select_all"
                rowLabel: Translation.tr("Select all")
                enabled: root.hasText
                onClicked: { root.field.selectAll(); root.close() }
            }
            Row_ {
                rowIcon: "backspace"
                rowLabel: Translation.tr("Clear")
                enabled: root.hasText
                onClicked: { root.field.clear(); root.close() }
            }
        }
    }
}
