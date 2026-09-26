import qs.services
import qs.modules.common
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
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
        active: appToplevel.toplevels.length > 0
        // The last window closing takes the MouseArea away mid-hover, so no
        // onExited ever arrives — clear the flag here instead.
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
        lastFocused = (lastFocused + 1) % appToplevel.toplevels.length
        appToplevel.toplevels[lastFocused].activate()
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

            RowLayout {
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
