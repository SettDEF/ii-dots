import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
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

            Rectangle {
                id: card
                anchors.centerIn: parent
                implicitWidth: contentRow.implicitWidth + 36
                implicitHeight: 56
                radius: height / 2
                color: Appearance.colors.colLayer1Base
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

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

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.meta.icon
                        iconSize: 22
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
