// The file-manager places, as a grid of folder chips. Shared by the dock's
// hover popup over the file-manager icon and the Folders widget window.
//
// Each cell carries its own surface rather than sitting bare on the panel:
// the hover popup tints itself with the app icon's average colour, so a
// bare icon+label washes out against whatever that happens to be.
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

GridLayout {
    id: grid
    property int cellWidth: 88
    property int cellHeight: 72
    /// Surface the chips sit on, so callers can match their own panel.
    property color chipColor: ColorUtils.transparentize(Appearance.colors.colLayer0Base, 0.25)
    property color chipText: Appearance.colors.colOnLayer0

    columns: Math.max(2, DockWidgets.get("places", "columns") ?? 3)
    columnSpacing: 6
    rowSpacing: 6

    Repeater {
        model: Places.entries
        delegate: RippleButton {
            id: cell
            required property var modelData
            Layout.preferredWidth: grid.cellWidth
            implicitHeight: grid.cellHeight
            buttonRadius: Appearance.rounding.small
            colBackground: grid.chipColor
            colBackgroundHover: ColorUtils.mix(grid.chipColor, grid.chipText, 0.85)
            onClicked: Places.open(cell.modelData.path)

            contentItem: ColumnLayout {
                spacing: 2
                IconImage {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 2
                    implicitSize: 30
                    // Papirus ships folder-documents, folder-download, …
                    source: Quickshell.iconPath(
                        `folder-${String(cell.modelData.name).toLowerCase()}`, "folder")
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    Layout.leftMargin: 3
                    Layout.rightMargin: 3
                    horizontalAlignment: Text.AlignHCenter
                    text: cell.modelData.name
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: grid.chipText
                    elide: Text.ElideRight
                }
            }
            StyledToolTip { text: cell.modelData.path }
        }
    }
}
