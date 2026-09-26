import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// Pure typography, so it reads as a clock face among the icons.
DockTile {
    id: root
    readonly property bool stacked: DockWidgets.get("clock", "stacked") === true
    readonly property bool twelve: DockWidgets.get("clock", "twelveHour") === true
    readonly property bool seconds: DockWidgets.get("clock", "seconds") === true
    readonly property bool showDate: DockWidgets.get("clock", "showDate") === true

    // Own clock: the shared one ticks per minute, which can't show seconds.
    SystemClock {
        id: tick
        precision: root.seconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    readonly property string hourFmt: root.twelve ? "hh" : "HH"
    readonly property string line1: root.stacked
        ? Qt.formatDateTime(tick.date, root.hourFmt)
        : Qt.formatDateTime(tick.date, `${root.hourFmt}:mm${root.seconds ? ":ss" : ""}`)
    readonly property string line2: !root.stacked ? ""
        : root.showDate ? Qt.formatDateTime(tick.date, "dd/MM")
        : root.seconds ? Qt.formatDateTime(tick.date, "mm:ss")
        : Qt.formatDateTime(tick.date, "mm")

    // The palette is monochrome (matugen read a grey wallpaper), so the tiles
    // are told apart by LIGHTNESS, not hue. This one is the light tile.
    tint: Appearance.colors.colPrimary
    tooltip: DateTime.longDate

    ColumnLayout {
        anchors.centerIn: parent
        spacing: -4
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: root.line1
            // Long lines have to drop a size or they run off the tile.
            font.pixelSize: root.line1.length > 2
                ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.large
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnPrimary
        }
        StyledText {
            visible: root.line2.length > 0
            Layout.alignment: Qt.AlignHCenter
            text: root.line2
            font.pixelSize: root.line2.length > 2
                ? Appearance.font.pixelSize.smallest : Appearance.font.pixelSize.large
            color: Appearance.colors.colOnPrimary
        }
    }
}
