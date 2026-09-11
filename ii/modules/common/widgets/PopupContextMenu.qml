// Reusable right-click context menu in the wallpaper-picker style.
//
// Overlays its parent. Each call to `popup(x, y, model)` swaps in a new
// model and shows the panel at the cursor (clamped inside the parent).
//
// Item model:
//   [{ icon, label, danger?, separator?, submenu?, onTriggered }]
//     icon        : Material symbol name (string)
//     label       : visible text
//     danger      : when true, label + icon tint red and hover bg uses
//                   m3error at low alpha
//     separator   : true → renders a thin divider instead of a menu row
//     submenu     : array of items → hovering opens a child panel beside this
//                   one. Nests to any depth; see PopupMenuPanel.
//     onTriggered : callback fired on click (after the menu dismisses)
//
// Example
//   PopupContextMenu { id: ctx }
//   MouseArea {
//       acceptedButtons: Qt.RightButton
//       onClicked: e => ctx.popup(e.x, e.y, [
//           { icon: "play_arrow", label: "Resume", onTriggered: () => row.resume() },
//           { icon: "sort", label: "Sort by", submenu: [
//               { icon: "sort_by_alpha", label: "Name", submenu: [
//                   { icon: "arrow_upward", label: "Ascending", onTriggered: () => byName(false) }
//               ]}
//           ]},
//           { separator: true },
//           { icon: "delete", danger: true, label: "Remove",
//             onTriggered: () => row.remove() }
//       ])
//   }
import qs.modules.common
import QtQuick

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

    // Recreated per popup so every level's open state resets with it.
    Loader {
        active: root.opened
        sourceComponent: PopupMenuPanel {
            items: root.menuItems
            bounds: root
            originX: root.px
            originW: 0
            desiredY: root.py
            panelWidth: root.panelWidth
            dismissAll: () => root.dismiss()
        }
    }
}
