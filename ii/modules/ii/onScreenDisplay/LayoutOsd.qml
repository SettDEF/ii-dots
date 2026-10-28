import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    property string layoutId: LayoutService.currentLayout()
    readonly property var meta: {
        const list = LayoutService.availableLayouts
        for (let i = 0; i < list.length; i++) if (list[i].id === root.layoutId) return list[i]
        return list[0]
    }

    property bool shown: false

    Connections {
        target: LayoutService
        function onLayoutChanged(id) {
            root.layoutId = id
            root.shown = true
            hideTimer.restart()
        }
    }

    Timer {
        id: hideTimer
        interval: 1300
        repeat: false
        onTriggered: root.shown = false
    }

    // Follow the focused monitor. Only one PanelWindow alive at a time
    // instead of one per screen. Re-creates on focus change, but layout
    // change events are rare so the surface churn is negligible.
    readonly property var focusedScreens: {
        const fm = Hyprland.focusedMonitor
        if (!fm) return Quickshell.screens.slice(0, 1)
        return Quickshell.screens.filter(s => s.name === fm.name)
    }

    Variants {
        model: root.focusedScreens

        PanelWindow {
            id: osd
            required property ShellScreen modelData
            screen: modelData

            readonly property bool effectiveShow: root.shown

            // Unmapped when idle: an empty overlay still stops a fullscreen game from scanning out directly.
            visible: osd.effectiveShow || card.visible
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:layoutOsd"
            WlrLayershell.layer: WlrLayer.Overlay

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            mask: effectiveShow ? maskShown : maskHidden
            Region { id: maskHidden }
            Region { id: maskShown; item: card }

            StyledRectangularShadow {
                target: card
                opacity: card.opacity
            }

            Rectangle {
                id: card
                // Whole device pixels: centred at 1.6x it sat on a fractional
                // position, and its 1-device-px outline smeared over two rows.
                readonly property real dpr: card.Screen.devicePixelRatio > 0 ? card.Screen.devicePixelRatio : 1
                x: Math.round((parent.width - width) / 2 * dpr) / dpr
                y: Math.round((parent.height - height) / 2 * dpr) / dpr
                implicitWidth: Math.round((contentRow.implicitWidth + 36) * dpr) / dpr
                implicitHeight: Math.round(56 * dpr) / dpr
                radius: height / 2
                // No hairline outline: on a curve its antialiased pixels blend with
                // whatever is behind (a glass terminal shows the wallpaper through),
                // so it read as grainy. A soft shadow separates it, like the shell's
                // other popups.
                color: Appearance.colors.colLayer1Base

                opacity: osd.effectiveShow ? 1 : 0
                visible: opacity > 0.01

                Behavior on implicitWidth {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }

                Row {
                    id: contentRow
                    anchors.centerIn: parent
                    spacing: 12

                    CustomIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22
                        source: `layout-${root.layoutId}-symbolic.svg`
                        colorize: true
                        color: Appearance.m3colors.m3primary
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.meta.label
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }
}
