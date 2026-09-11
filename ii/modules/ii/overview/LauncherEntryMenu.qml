// Right-click menu for a single launcher result.
//
// This is where manual priority actually gets set — without it, the
// priorityApps list in Config could never be populated from the UI and the
// "prioritised entries float to top" option in LauncherSortMenu would have
// nothing to act on.
//
// A PopupWindow rather than the existing PopupContextMenu Item overlay: the
// overview's layer surface masks input to the bar band plus two named regions
// (Overview.qml), so an overlay drawn over the results list is not reliably
// clickable. Its own surface has no mask. Same reasoning as LauncherSortMenu.
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
    property string entryId: ""
    property string entryName: ""
    color: "transparent"

    readonly property bool prioritised: (Config.options.launcher.priorityApps ?? []).indexOf(root.entryId) >= 0
    readonly property bool hidden: (Config.options.launcher.hiddenApps ?? []).indexOf(root.entryId) >= 0

    function openFor(id, name) {
        if (!id || id.length === 0) return   // actions/commands have no id
        root.entryId = id
        root.entryName = name ?? ""
        root.visible = true
    }
    function close() { root.visible = false }

    anchor {
        window: anchorItem ? anchorItem.QsWindow.window : null
        // Beside the row, not under it: anchored below, the menu covered the
        // very entry it acts on plus the results under it. Flip lets it swap to
        // the left when there is no room on the right.
        gravity: Edges.Right
        edges: Edges.Right
        adjustment: PopupAdjustment.Flip | PopupAdjustment.SlideY
        // mapFromItem() throws if this evaluates before the anchor belongs to a
        // window, hence the guard.
        rect: (root.visible && anchorItem && anchorItem.QsWindow?.window)
            ? Qt.rect(
                anchorItem.QsWindow.mapFromItem(anchorItem, anchorItem.width, 0).x,
                anchorItem.QsWindow.mapFromItem(anchorItem, anchorItem.width, 0).y,
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
        implicitWidth: 260
        implicitHeight: col.implicitHeight + 16
        radius: Appearance.rounding.small
        // m3surfaceContainer, NOT colLayer1: colLayer1 is solveOverlayColor()'d
        // against colLayer0Base, so it only reads correctly when composited over
        // the shell's own backdrop. This popup is its own window with a
        // transparent surface — there is nothing behind it, so colLayer1 came
        // out see-through. The raw m3 role is opaque.
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

            // Header: which entry this menu is acting on, and its count.
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.bottomMargin: 2
                text: root.entryName
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.bottomMargin: 4
                text: {
                    LauncherRanking.revision   // re-read after a mutation
                    const n = LauncherRanking.count(root.entryId)
                    return n === 0 ? Translation.tr("Never launched")
                                   : Translation.tr("Launched %1×").arg(n)
                }
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
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
                rowIcon: root.prioritised ? "star" : "star_outline"
                rowLabel: root.prioritised ? Translation.tr("Remove priority")
                                        : Translation.tr("Prioritise")
                tint: root.prioritised ? Appearance.colors.colPrimary
                                       : Appearance.colors.colOnLayer1
                onClicked: { LauncherRanking.togglePriority(root.entryId); root.close() }
            }

            MenuRow {
                visible: root.prioritised
                rowIcon: "keyboard_arrow_up"
                rowLabel: Translation.tr("Move up in priority")
                onClicked: LauncherRanking.raisePriority(root.entryId)
            }

            MenuRow {
                rowIcon: root.hidden ? "visibility" : "visibility_off"
                rowLabel: root.hidden ? Translation.tr("Unhide") : Translation.tr("Hide from launcher")
                onClicked: { LauncherRanking.toggleHidden(root.entryId); root.close() }
            }

            MenuRow {
                enabled: LauncherRanking.count(root.entryId) > 0
                rowIcon: "restart_alt"
                rowLabel: Translation.tr("Reset launch count")
                tint: Appearance.m3colors.m3error
                onClicked: { LauncherRanking.resetOne(root.entryId); root.close() }
            }
        }
    }
}
