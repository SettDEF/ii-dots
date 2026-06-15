// Reusable right-click context menu in the wallpaper-picker style.
//
// Overlays its parent. Each call to `popup(x, y, model)` swaps in a new
// model and shows the panel at the cursor (clamped inside the parent).
//
// Item model:
//   [{ icon, label, danger?, separator?, onTriggered }]
//     icon        : Material symbol name (string)
//     label       : visible text
//     danger      : when true, label + icon tint red and hover bg uses
//                   m3error at low alpha
//     separator   : true → renders a thin divider instead of a menu row
//     onTriggered : callback fired on click (after the menu dismisses)
//
// Example
//   PopupContextMenu { id: ctx }
//   MouseArea {
//       acceptedButtons: Qt.RightButton
//       onClicked: e => ctx.popup(e.x, e.y, [
//           { icon: "play_arrow", label: "Resume", onTriggered: () => row.resume() },
//           { separator: true },
//           { icon: "delete", danger: true, label: "Remove",
//             onTriggered: () => row.remove() }
//       ])
//   }
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    anchors.fill: parent
    z: 9000
    visible: opened

    property bool opened: false
    property var menuItems: []
    property real px: 0
    property real py: 0
    property int panelWidth: 226

    function popup(x, y, model) {
        root.menuItems = model
        root.px = x
        root.py = y
        root.opened = true
    }
    function dismiss() { root.opened = false }

    // Click-outside / scroll catcher. hoverEnabled is true so the catcher
    // steals hover from any tile under the cursor — that fires onExited on
    // the tile and clears its highlight while the menu is up.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        propagateComposedEvents: false
        onPressed: root.dismiss()
        onWheel: wheel => wheel.accepted = true
    }

    Rectangle {
        id: panel
        width: root.panelWidth
        implicitHeight: menuCol.implicitHeight + 10
        height: implicitHeight
        x: Math.max(6, Math.min(root.px, root.width - width - 6))
        y: Math.max(6, Math.min(root.py, root.height - height - 6))
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        opacity: root.opened ? 1 : 0
        scale: root.opened ? 1 : 0.93
        transformOrigin: Item.TopLeft
        Behavior on opacity { NumberAnimation { duration: 110 } }
        Behavior on scale  { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: menuCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 5 }
            spacing: 1

            Repeater {
                model: root.menuItems
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: modelData.separator ? 7 : 32
                    radius: 6
                    color: (rowMa.containsMouse && !modelData.separator)
                        ? (modelData.danger
                           ? ColorUtils.transparentize(Appearance.m3colors.m3error, 0.84)
                           : Appearance.colors.colLayer2)
                        : "transparent"

                    Rectangle {
                        visible: row.modelData.separator === true
                        anchors.verticalCenter: parent.verticalCenter
                        anchors { left: parent.left; right: parent.right; leftMargin: 8; rightMargin: 8 }
                        height: 1
                        color: Appearance.colors.colLayer0Border
                    }

                    RowLayout {
                        visible: !row.modelData.separator
                        anchors { fill: parent; leftMargin: 9; rightMargin: 11 }
                        spacing: 9
                        MaterialSymbol {
                            text: row.modelData.icon ?? ""
                            iconSize: 17
                            color: row.modelData.danger
                                ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.label ?? ""
                            font.pixelSize: Appearance.font.pixelSize.small
                            elide: Text.ElideRight
                            color: row.modelData.danger
                                ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                        }
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        enabled: !row.modelData.separator
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const fn = row.modelData.onTriggered
                            root.dismiss()
                            if (fn) fn()
                        }
                    }
                }
            }
        }
    }
}
