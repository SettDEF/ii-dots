// StartMenuAppTile — one pinned/recommended app icon in the Start Menu grid.
// Left-click launches (via AppLaunch, same as the dock/overview); right-click
// opens LauncherEntryMenu, reused unmodified from the overview launcher, for
// prioritise/hide/pin bookkeeping.
pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overview
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

RippleButton {
    id: root
    required property var entry
    property real size: 72

    implicitWidth: size
    implicitHeight: size
    buttonRadius: Appearance.rounding.normal
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

    onClicked: {
        GlobalStates.startMenuOpen = false
        AppLaunch.launch(root.entry)
    }
        contentItem: ColumnLayout {
        spacing: 4
        IconImage {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 6
            source: Quickshell.iconPath(AppSearch.guessIcon(root.entry?.id ?? ""), "image-missing")
            implicitSize: 32
        }
        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            text: root.entry?.name ?? ""
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnLayer1
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    StyledToolTip { text: root.entry?.name ?? "" }
}
