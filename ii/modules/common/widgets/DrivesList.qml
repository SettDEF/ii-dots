// The drive places (mount points from Places.drives) as rows with a usage bar,
// for the dock's file-manager popup. A drive is not a folder: what you want
// from it at a glance is whether it is there and how full it is.
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: list
    /// Surface the rows sit on, matching PlacesGrid's so the two read as one panel.
    property color chipColor: ColorUtils.transparentize(Appearance.colors.colLayer0Base, 0.25)
    property color chipText: Appearance.colors.colOnLayer0

    spacing: 6
    visible: Places.drives.length > 0

    Repeater {
        model: Places.drives
        delegate: RippleButton {
            id: row
            required property var modelData
            readonly property var use: Places.usage[Places._strip(row.modelData.path)] ?? null
            readonly property bool mounted: row.use?.mounted ?? false
            readonly property real used: (row.mounted && row.use.size > 0)
                ? 1 - row.use.avail / row.use.size : 0

            Layout.fillWidth: true
            implicitHeight: 46
            buttonRadius: Appearance.rounding.small
            colBackground: list.chipColor
            colBackgroundHover: ColorUtils.mix(list.chipColor, list.chipText, 0.85)
            enabled: row.mounted
            opacity: row.mounted ? 1 : 0.55
            onClicked: Places.open(row.modelData.path)

            contentItem: ColumnLayout {
                spacing: 4
                RowLayout {
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    spacing: 8
                    MaterialSymbol {
                        text: row.mounted ? "hard_drive" : "link_off"
                        iconSize: Appearance.font.pixelSize.larger
                        color: list.chipText
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.name
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: list.chipText
                        elide: Text.ElideRight
                    }
                    StyledText {
                        text: row.mounted
                            ? Translation.tr("%1 free").arg(StringUtils.formatBytes(row.use.avail))
                            : Translation.tr("not connected")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.monospace
                        color: list.chipText
                        opacity: 0.75
                    }
                }
                Rectangle {
                    visible: row.mounted
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    implicitHeight: 4
                    radius: Appearance.rounding.full
                    color: ColorUtils.transparentize(list.chipText, 0.82)
                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: parent.width * Math.max(0, Math.min(1, row.used))
                        radius: parent.radius
                        // Nearly full is the one state worth shouting about.
                        color: row.used > 0.9 ? Appearance.m3colors.m3error : list.chipText
                    }
                }
            }
            StyledToolTip {
                text: row.mounted
                    ? Translation.tr("%1 · %2 of %3 used").arg(row.modelData.path)
                        .arg(StringUtils.formatBytes(row.use.size - row.use.avail))
                        .arg(StringUtils.formatBytes(row.use.size))
                    : Translation.tr("%1 is not mounted").arg(row.modelData.path)
            }
        }
    }
}
