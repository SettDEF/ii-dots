// Right-click menu for a single window tile in the overview.
//
// The overview could already drag a window to another workspace, and that was
// all it could do: there was no right-click path at all, because the tile's
// MouseArea only accepted Left and Middle. Everything here is a dispatch
// Hyprland already exposes — the overview just never offered it.
//
// A PopupWindow rather than an overlay Item, for the same reason
// LauncherEntryMenu is one: the overview's layer surface masks input to the
// bar band plus two named regions, so an overlay drawn over the workspace
// grid is not reliably clickable. Its own surface has no mask.
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
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
    property int workspaceId: -1

    color: "transparent"

    function openFor(data) {
        if (!data?.address) return
        root.address = String(data.address)
        root.title = String(data.title ?? "")
        root.windowClass = String(data.class ?? "")
        root.isFloating = data.floating === true
        root.isFullscreen = (data.fullscreen ?? 0) !== 0
        root.workspaceId = data.workspace?.id ?? -1
        root.visible = true
    }
    function close() { root.visible = false }

    function dispatch(cmd) {
        HyprDispatch.run(`${cmd}, address:${root.address}`)
        root.close()
    }

    anchor {
        window: anchorItem ? anchorItem.QsWindow.window : null
        gravity: Edges.Right | Edges.Bottom
        edges: Edges.Right | Edges.Bottom
        adjustment: PopupAdjustment.Flip | PopupAdjustment.SlideY
        // mapFromItem() throws if this evaluates before the anchor belongs to
        // a window, hence the guard.
        rect: (root.visible && anchorItem && anchorItem.QsWindow?.window)
            ? Qt.rect(
                anchorItem.QsWindow.mapFromItem(anchorItem, anchorItem.width / 2, anchorItem.height / 2).x,
                anchorItem.QsWindow.mapFromItem(anchorItem, anchorItem.width / 2, anchorItem.height / 2).y,
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
        implicitWidth: 248
        implicitHeight: col.implicitHeight + 16
        radius: Appearance.rounding.small
        // m3surfaceContainer, not colLayer1: colLayer1 is solved against the
        // shell's backdrop, and this popup is its own transparent surface with
        // nothing behind it, so colLayer1 comes out see-through.
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        focus: root.visible
        Keys.onEscapePressed: event => { root.close(); event.accepted = true }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                text: root.title.length > 0 ? root.title : root.windowClass
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.bottomMargin: 4
                text: root.windowClass
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }

            component MenuRow: RippleButton {
                Layout.fillWidth: true
                implicitHeight: 32
                buttonRadius: Appearance.rounding.verysmall
                property string rowIcon: ""
                property string rowLabel: ""
                property color tint: Appearance.colors.colOnLayer1
                contentItem: RowLayout {
                    spacing: 8
                    MaterialSymbol {
                        Layout.leftMargin: 4
                        text: rowIcon
                        iconSize: Appearance.font.pixelSize.large
                        color: tint
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: rowLabel
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: tint
                    }
                }
            }

            MenuRow {
                rowIcon: root.isFloating ? "grid_view" : "picture_in_picture"
                rowLabel: root.isFloating ? Translation.tr("Tile") : Translation.tr("Float")
                onClicked: root.dispatch("togglefloating")
            }
            MenuRow {
                rowIcon: root.isFullscreen ? "fullscreen_exit" : "fullscreen"
                rowLabel: root.isFullscreen ? Translation.tr("Leave fullscreen")
                                            : Translation.tr("Fullscreen")
                onClicked: root.dispatch("fullscreen, 1")
            }
            MenuRow {
                rowIcon: "keep"
                rowLabel: Translation.tr("Pin to every workspace")
                // Pinning only applies to floating windows in Hyprland, so
                // offering it on a tiled one would silently do nothing.
                enabled: root.isFloating
                onClicked: root.dispatch("pin")
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 3
                Layout.bottomMargin: 3
                implicitHeight: 1
                color: Appearance.colors.colLayer0Border
            }

            StyledText {
                Layout.leftMargin: 6
                Layout.bottomMargin: 2
                text: Translation.tr("Move to workspace")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
            // Dragging already moves a window between workspaces, but only to
            // one that is on screen in the grid. This reaches the rest.
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                spacing: 4
                Repeater {
                    model: 10
                    delegate: RippleButton {
                        required property int index
                        readonly property int wsId: index + 1
                        readonly property bool here: wsId === root.workspaceId
                        implicitWidth: 40
                        implicitHeight: 28
                        buttonRadius: Appearance.rounding.verysmall
                        colBackground: here ? Appearance.colors.colPrimary
                                            : Appearance.colors.colLayer2
                        enabled: !here
                        contentItem: StyledText {
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: wsId
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: here ? Appearance.colors.colOnPrimary
                                        : Appearance.colors.colOnLayer2
                        }
                        onClicked: root.dispatch(`movetoworkspacesilent ${wsId}`)
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 3
                Layout.bottomMargin: 3
                implicitHeight: 1
                color: Appearance.colors.colLayer0Border
            }

            MenuRow {
                rowIcon: "close"
                rowLabel: Translation.tr("Close window")
                tint: Appearance.m3colors.m3error
                onClicked: root.dispatch("closewindow")
            }
        }
    }
}
