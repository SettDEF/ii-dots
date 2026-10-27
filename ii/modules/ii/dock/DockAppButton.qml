import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets

DockButton {
    id: root
    property var appToplevel
    property var appListRoot
    property int lastFocused: -1
    property real iconSize: 35
    property real countDotWidth: 10
    property real countDotHeight: 4
    property bool appIsActive: appToplevel.toplevels.find(t => (t.activated == true)) !== undefined

    readonly property bool isSeparator: appToplevel.appId === "SEPARATOR"
    readonly property var desktopEntry: DesktopEntries.heuristicLookup(appToplevel.appId)
    enabled: !isSeparator
    // RippleButton dims a disabled button to 0.4, which made the separator
    // variant a fainter line than the DockSeparators beside it.
    opacity: 1
    implicitWidth: isSeparator ? 1 : implicitHeight - topInset - bottomInset

    Loader {
        active: isSeparator
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        // Same offset as DockSeparator's Layout.topMargin, halved: this one
        // centres rather than fills.
        anchors.verticalCenterOffset: (Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut) / 2
        sourceComponent: DockSeparator {}
    }

    Loader {
        anchors.fill: parent
        // Always: gating this on having windows meant a pinned app with
        // nothing open could not be hovered at all — and took the folder grid
        // with it, since showFolderGrid exists precisely for a file manager
        // with no windows. It could never fire.
        //
        // It also removes the reason this Loader had a guard: the MouseArea
        // no longer disappears mid-hover when the last window closes.
        active: true
        onActiveChanged: {
            if (!active && appListRoot.lastHoveredButton === root)
                appListRoot.buttonHovered = false
        }
        sourceComponent: MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: {
                appListRoot.lastHoveredButton = root
                appListRoot.buttonHovered = true
                lastFocused = appToplevel.toplevels.length - 1
            }
            onExited: {
                if (appListRoot.lastHoveredButton === root) {
                    appListRoot.buttonHovered = false
                }
            }
        }
    }

    onClicked: {
        if (appToplevel.toplevels.length === 0) {
            AppLaunch.launch(root.desktopEntry);
            return;
        }
        // A minimized window (special:minimized, see hypr custom/scripts/
        // minimize.sh) comes back to the current workspace; activate() alone
        // would open the hidden workspace instead.
        const minimized = appToplevel.toplevels.find(t => root.isMinimized(t));
        if (minimized) {
            root.restore(minimized);
            return;
        }
        lastFocused = (lastFocused + 1) % appToplevel.toplevels.length
        appToplevel.toplevels[lastFocused].activate()
    }

    function addressOf(toplevel) {
        const a = toplevel?.HyprlandToplevel?.address;
        return a ? `0x${a}` : "";
    }
    function isMinimized(toplevel) {
        const a = root.addressOf(toplevel);
        return a.length > 0
            && HyprlandData.windowByAddress[a]?.workspace?.name === "special:minimized";
    }
    function restore(toplevel) {
        const a = root.addressOf(toplevel);
        const here = HyprlandData.activeWorkspace?.id;
        if (a.length === 0 || here === undefined) return;
        HyprDispatch.run(`movetoworkspace ${here}, address:${a}`);
        HyprDispatch.run(`focuswindow address:${a}`);
    }

    middleClickAction: () => {
        AppLaunch.launch(root.desktopEntry);
    }

    // Pin moved into the menu, along with volume, windows and app actions.
    altAction: () => {
        appListRoot.openMenu(root, appToplevel);
    }

    contentItem: Loader {
        active: !isSeparator
        sourceComponent: Item {
            anchors.centerIn: parent

            Loader {
                id: iconImageLoader
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                active: !root.isSeparator
                sourceComponent: IconImage {
                    source: Quickshell.iconPath(AppSearch.guessIcon(appToplevel.appId), "image-missing")
                    implicitSize: root.iconSize
                }
            }

            Loader {
                active: Config.options.dock.monochromeIcons
                anchors.fill: iconImageLoader
                sourceComponent: Item {
                    Desaturate {
                        id: desaturatedIcon
                        visible: false // There's already color overlay
                        anchors.fill: parent
                        source: iconImageLoader
                        desaturation: 0.8
                    }
                    ColorOverlay {
                        anchors.fill: desaturatedIcon
                        source: desaturatedIcon
                        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                    }
                }
            }

            // Download ring around the browser while Downloads sees a .part file.
            // Spins while the size is unknown; fills once progress is reported.
            CircularProgress {
                id: downloadRing
                readonly property bool isBrowser: /zen|firefox|tela/i.test(appToplevel.appId ?? "")
                visible: isBrowser && Downloads.count > 0 && !root.isSeparator
                anchors.centerIn: iconImageLoader
                implicitSize: root.iconSize + 8
                lineWidth: 3
                value: Downloads.progress >= 0 ? Downloads.progress : 0.28
                colPrimary: Appearance.colors.colPrimary
                colSecondary: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
                RotationAnimation on rotation {
                    running: downloadRing.visible && Downloads.progress < 0
                    from: 0; to: 360
                    duration: 1400
                    loops: Animation.Infinite
                }
            }

            // The number for the ring: only once tela-zen reports real progress
            // (downloads.json). Bottom-centre, so it never covers the unread
            // badge in the top-right corner.
            Rectangle {
                id: downloadPct
                visible: downloadRing.visible && Downloads.progress >= 0
                anchors {
                    horizontalCenter: iconImageLoader.horizontalCenter
                    verticalCenter: iconImageLoader.verticalCenter
                    verticalCenterOffset: root.iconSize / 2 - 2
                }
                implicitHeight: 16
                implicitWidth: pctText.implicitWidth + 10
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimary
                border.width: 2
                border.color: Appearance.colors.colLayer0
                StyledText {
                    id: pctText
                    anchors.centerIn: parent
                    text: Math.floor(Downloads.progress * 100) + "%"
                    font.pixelSize: Appearance.font.pixelSize.smallest - 1
                    font.family: Appearance.font.family.monospace
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnPrimary
                }
            }

            // Unread badge: notifications still in the history for this app
            // (AppBadges). Pinned to the icon's top-right corner, ringed in
            // the dock colour so it separates from any icon artwork.
            Rectangle {
                id: badge
                readonly property int count: AppBadges.countFor(appToplevel.appId)
                visible: count > 0 && !root.isSeparator
                anchors {
                    horizontalCenter: iconImageLoader.horizontalCenter
                    horizontalCenterOffset: root.iconSize / 2 - 3
                    verticalCenter: iconImageLoader.verticalCenter
                    verticalCenterOffset: -root.iconSize / 2 + 3
                }
                implicitHeight: 18
                implicitWidth: Math.max(implicitHeight, badgeText.implicitWidth + 9)
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimary
                border.width: 2
                border.color: Appearance.colors.colLayer0
                StyledText {
                    id: badgeText
                    anchors.centerIn: parent
                    text: badge.count > 99 ? "99+" : String(badge.count)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.family: Appearance.font.family.monospace
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnPrimary
                }
            }

            RowLayout {
                visible: !downloadPct.visible
                spacing: 3
                anchors {
                    top: iconImageLoader.bottom
                    topMargin: 2
                    horizontalCenter: parent.horizontalCenter
                }
                Repeater {
                    model: Math.min(appToplevel.toplevels.length, 3)
                    delegate: Rectangle {
                        required property int index
                        radius: Appearance.rounding.full
                        implicitWidth: (appToplevel.toplevels.length <= 3) ? 
                            root.countDotWidth : root.countDotHeight // Circles when too many
                        implicitHeight: root.countDotHeight
                        color: appIsActive ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                    }
                }
            }
        }
    }
}
