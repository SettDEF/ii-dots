// Right-click menu for a single window tile in the overview.
//
// The overview could already drag a window to another workspace, and that was
// all it could do: there was no right-click path at all, because the tile's
// MouseArea only accepted Left and Middle. Everything here is a dispatch
// Hyprland already exposes — the overview just never offered it.
//
// The rows are PopupMenuPanel, the same panel as the dock's, the tray's and
// every other context menu, so it looks and sizes like them. It used to draw
// its own smaller rows and a grid of workspace numbers, and read as a
// different app's menu.
//
// A PopupWindow rather than an overlay Item, for the same reason
// LauncherEntryMenu is one: the overview's layer surface masks input to the
// bar band plus two named regions, so an overlay drawn over the workspace
// grid is not reliably clickable. Its own surface has no mask. It is sized
// for the panel plus its "Move to workspace" submenu beside it.
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

PopupWindow {
    id: root

    required property Item anchorItem
    /// The Hyprland address, e.g. "0x55f...". Set by openFor().
    property string address: ""
    property string title: ""
    property string windowClass: ""
    property bool isFloating: false
    property bool isFullscreen: false
    property bool isPinned: false
    property int workspaceId: -1

    readonly property int panelWidth: 240
    /// room left of the panel, so a submenu that flips left still fits
    readonly property int side: 300
    color: "transparent"

    function openFor(data) {
        if (!data?.address) return
        root.address = String(data.address)
        root.title = String(data.title ?? "")
        root.windowClass = String(data.class ?? "")
        root.isFloating = data.floating === true
        root.isFullscreen = (data.fullscreen ?? 0) !== 0
        root.isPinned = data.pinned === true
        root.workspaceId = data.workspace?.id ?? -1
        root.visible = true
    }
    function close() { root.visible = false }

    function dispatch(cmd) {
        HyprDispatch.run(`${cmd}, address:${root.address}`)
    }

    readonly property var menuItems: {
        const name = root.title.length > 0 ? root.title : root.windowClass
        const items = [
            { icon: "open_in_new", label: name.length > 34 ? name.slice(0, 33) + "…" : name,
              onTriggered: () => root.dispatch("focuswindow") },
            { separator: true },
            { icon: root.isFloating ? "grid_view" : "picture_in_picture",
              label: root.isFloating ? Translation.tr("Tile") : Translation.tr("Float"),
              onTriggered: () => root.dispatch("togglefloating") },
            { icon: root.isFullscreen ? "fullscreen_exit" : "fullscreen",
              label: root.isFullscreen ? Translation.tr("Leave fullscreen") : Translation.tr("Fullscreen"),
              onTriggered: () => root.dispatch("fullscreen, 1") },
        ]
        // Hyprland pins floating windows only; on a tiled one it does nothing.
        if (root.isFloating)
            items.push({ icon: "keep", label: root.isPinned ? Translation.tr("Unpin") : Translation.tr("Pin to every workspace"),
                         onTriggered: () => root.dispatch("pin") })
        // Dragging only reaches workspaces on screen in the grid; this reaches the rest.
        const ws = []
        for (let i = 1; i <= 10; i++) {
            if (i === root.workspaceId) continue
            const n = i
            ws.push({ icon: "tab_move", label: Translation.tr("Workspace %1").arg(n),
                      onTriggered: () => root.dispatch(`movetoworkspacesilent ${n}`) })
        }
        items.push({ icon: "move_group", label: Translation.tr("Move to workspace"), submenu: ws })
        items.push({ separator: true })
        items.push({ icon: "close", label: Translation.tr("Close window"), danger: true,
                     onTriggered: () => root.dispatch("closewindow") })
        return items
    }

    anchor {
        window: anchorItem ? anchorItem.QsWindow.window : null
        gravity: Edges.Right | Edges.Bottom
        edges: Edges.Top | Edges.Left
        adjustment: PopupAdjustment.SlideX | PopupAdjustment.SlideY
        // mapFromItem() throws if this evaluates before the anchor belongs to
        // a window, hence the guard.
        rect: (root.visible && anchorItem && anchorItem.QsWindow?.window)
            ? Qt.rect(
                anchorItem.QsWindow.mapFromItem(anchorItem, anchorItem.width / 2, anchorItem.height / 2).x - root.side,
                anchorItem.QsWindow.mapFromItem(anchorItem, anchorItem.width / 2, anchorItem.height / 2).y,
                1, 1)
            : Qt.rect(0, 0, 1, 1)
    }

    // the panel, and room for its submenu beside it
    implicitWidth: root.side + root.panelWidth * 2 + 340
    implicitHeight: 620

    // a click outside the panels closes it
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: root.close()
        onWheel: wheel => wheel.accepted = true
    }

    // NOT named `bounds`: PopupMenuPanel has a `bounds` property of its own, so
    // `bounds: bounds` inside it bound the property to itself (null) and the
    // panel had no size.
    Item {
        id: menuArea
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: event => { root.close(); event.accepted = true }

        // Re-created on every open so it animates in, like the dock's.
        Loader {
            id: menuLoader
            anchors.fill: parent
            active: root.visible
            sourceComponent: Item {
                // the shadow has to be the panel's sibling to anchor to it
                StyledRectangularShadow { target: menuPanel }
                PopupMenuPanel {
                    id: menuPanel
                    items: root.menuItems
                    bounds: menuArea
                    originX: root.side
                    originW: 0
                    desiredY: 8
                    panelWidth: root.panelWidth
                    dismissAll: () => root.close()
                    onChildOpenChanged: if (childOpen) Qt.callLater(() => console.warn("overview menu: submenu open", JSON.stringify({ panelX: x, panelW: width, area: [menuArea.width, menuArea.height] })))
                    // swallow clicks on the panel itself
                    MouseArea { anchors.fill: parent; z: -1; acceptedButtons: Qt.AllButtons }
                }
            }
        }
    }
}
