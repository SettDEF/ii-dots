// Reusable right-click context menu in the wallpaper-picker style.
//
// Overlays its parent. Each call to `popup(x, y, model)` swaps in a new
// model and shows the panel at the cursor (clamped inside the parent).
//
// Item model:
//   [{ icon, label, danger?, separator?, submenu?, onTriggered }]
//     icon        : Material symbol name (string)
//     iconColor   : optional colour for the icon
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
    visible: false          // coordinate anchor only; the menu draws in `overlay`

    property bool opened: false
    property var menuItems: []
    property real px: 0
    property real py: 0
    property int panelWidth: 226

    // The panel draws in the window's top item, not here: it clamps itself
    // inside `bounds`, and this item fills whatever it was declared in - so
    // inside a tile the menu was clamped to the tile and clipped by it.
    readonly property Item overlayHost: {
        let it = root;
        while (it.parent) it = it.parent;
        return it;
    }

    /// The click, in the overlay's coordinates.
    readonly property point origin: root.opened
        ? root.mapToItem(root.overlayHost, root.px, root.py)
        : Qt.point(0, 0)

    // Keeps the loader alive through the fade-out; without it, dismissing
    // dropped the panel on the spot and the exit animation never ran.
    property bool closing: false

    onOpenedChanged: {
        if (root.opened) { root.closing = false; closeTimer.stop() }
        else if (menuLoader.active) { root.closing = true; closeTimer.restart() }
    }

    Timer {
        id: closeTimer
        interval: 140      // the panel's 110ms fade, plus a frame
        onTriggered: root.closing = false
    }

    property double _openedAt: 0
    function popup(x, y, model) {
        root.menuItems = model
        root.px = x
        root.py = y
        root._openedAt = Date.now()
        root.opened = true
    }
    function dismiss() { root.opened = false }

    Item {
        id: overlay
        parent: root.overlayHost
        anchors.fill: parent
        z: 9000
        visible: root.opened || root.closing

        // Click-outside / scroll catcher. hoverEnabled is true so the catcher
        // steals hover from any tile under the cursor — that fires onExited on
        // the tile and clears its highlight while the menu is up.
        MouseArea {
            anchors.fill: parent
            // Off during the fade-out, or it eats the next click.
            enabled: root.opened
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            propagateComposedEvents: false
            // Not the press that opened it: a popup that widens its input
            // region mid-press can deliver that same press here.
            onPressed: if (Date.now() - root._openedAt > 200) root.dismiss()
            onWheel: wheel => wheel.accepted = true
        }

        // Recreated per popup so every level's open state resets with it.
        Loader {
            id: menuLoader
            active: root.opened || root.closing
            sourceComponent: PopupMenuPanel {
                shown: root.opened
                items: root.menuItems
                bounds: overlay
                originX: root.origin.x
                originW: 0
                desiredY: root.origin.y
                panelWidth: root.panelWidth
                dismissAll: () => root.dismiss()
            }
        }
    }
}
