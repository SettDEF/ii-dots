// Right-click menu for one quick-action chip under the window pill.
//
// A PopupWindow rather than the PopupContextMenu overlay: that one is an Item
// with `anchors.fill: parent` and clamps its panel inside those bounds, and
// this menu's parent is the bar's left section — barHeight tall. The list
// would be squashed into a few pixels. Its own surface has no such ceiling.
// Same reasoning as LauncherEntryMenu and MonitorContextMenu.
//
// Offers only actions NOT already on the bar. Swapping a chip for one sitting
// two chips along is never what was meant, and dropping them keeps the list
// within the ~215px the bar layer actually has beneath the bar — the full
// nine-row catalogue does not fit there.
pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

PopupWindow {
    id: root

    required property Item anchorItem
    property var catalog: []
    property var takenIds: []
    property int slot: -1
    color: "transparent"

    // Where the chip was clicked, so the menu opens at that chip rather than
    // at the pill's origin.
    property real menuX: 0
    property real menuY: 0

    signal picked(int slot, string id)

    readonly property var choices:
        (root.catalog ?? []).filter(a => (root.takenIds ?? []).indexOf(a.id) < 0)

    function openAt(slotIndex, x, y) {
        if (root.choices.length === 0)
            return;
        root.slot = slotIndex;
        root.menuX = x;
        root.menuY = y;
        root.visible = true;
    }
    function close() {
        root.visible = false;
    }

    anchor {
        window: root.anchorItem ? root.anchorItem.QsWindow.window : null
        gravity: Edges.Bottom | Edges.Right
        edges: Edges.Bottom | Edges.Right
        adjustment: PopupAdjustment.Flip | PopupAdjustment.SlideX
        // Guarded: mapFromItem() throws if evaluated before the anchor item
        // belongs to a window.
        rect: (root.visible && root.anchorItem && root.anchorItem.QsWindow?.window)
            ? Qt.rect(root.anchorItem.QsWindow.mapFromItem(root.anchorItem, root.menuX, root.menuY).x,
                      root.anchorItem.QsWindow.mapFromItem(root.anchorItem, root.menuX, root.menuY).y,
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

    StyledRectangularShadow {
        target: panel
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        implicitWidth: 230
        implicitHeight: col.implicitHeight + 12
        radius: Appearance.rounding.small
        // m3surfaceContainer, not colLayer1: colLayer1 is solveOverlayColor()'d
        // against the shell backdrop, so in a window of its own it reads
        // see-through. The tray menu learned this the hard way.
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        focus: root.visible
        Keys.onEscapePressed: event => {
            root.close();
            event.accepted = true;
        }

        ColumnLayout {
            id: col
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 6
            }
            spacing: 1

            StyledText {
                Layout.fillWidth: true
                Layout.margins: 4
                Layout.bottomMargin: 2
                text: Translation.tr("Replace with…")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }

            Repeater {
                model: root.choices

                delegate: RippleButton {
                    id: choiceRow
                    required property var modelData
                    readonly property bool danger: choiceRow.modelData.danger === true

                    Layout.fillWidth: true
                    implicitHeight: 31
                    buttonRadius: Appearance.rounding.verysmall

                    releaseAction: () => {
                        root.picked(root.slot, choiceRow.modelData.id);
                        root.close();
                    }

                    contentItem: RowLayout {
                        spacing: 8
                        MaterialSymbol {
                            Layout.leftMargin: 4
                            text: choiceRow.modelData.icon ?? ""
                            iconSize: Appearance.font.pixelSize.large
                            color: choiceRow.danger
                                ? Appearance.m3colors.m3error
                                : Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: choiceRow.modelData.label ?? ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: choiceRow.danger
                                ? Appearance.m3colors.m3error
                                : Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
