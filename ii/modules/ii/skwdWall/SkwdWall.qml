pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

Scope {
    id: root

    readonly property real cardWidth: 1280
    readonly property real cardHeight: 540
    readonly property real cardRounding: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData

            readonly property bool isFocusedScreen: {
                if (Hyprland.focusedMonitor) {
                    return Hyprland.focusedMonitor.name === modelData.name
                } else {
                    return Quickshell.screens.length > 0 && modelData.name === Quickshell.screens[0].name
                }
            }
            readonly property bool effectiveOpen: GlobalStates.skwdWallOpen && isFocusedScreen
            property bool isGrabbed: false

            visible: win.effectiveOpen || unloadTimer.running
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:skwdWall"
            WlrLayershell.layer: WlrLayer.Overlay
            // Grant keyboard focus while the panel is open so typing in
            // the search field doesn't bleed through to the terminal /
            // window underneath.
            WlrLayershell.keyboardFocus: win.effectiveOpen
                ? WlrKeyboardFocus.OnDemand
                : WlrKeyboardFocus.None

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            mask: effectiveOpen ? maskOpen : maskClosed
            Region { id: maskClosed }
            Region { id: maskOpen; item: card }

            Timer {
                id: delayGrabTimer
                interval: 200
                repeat: false
                onTriggered: {
                    if (win.effectiveOpen) {
                        card.forceActiveFocus()
                        GlobalFocusGrab.addDismissable(win)
                        win.isGrabbed = true
                    }
                }
            }

            onEffectiveOpenChanged: {
                if (effectiveOpen) {
                    delayGrabTimer.restart()
                } else {
                    delayGrabTimer.stop()
                    GlobalFocusGrab.removeDismissable(win)
                    win.isGrabbed = false
                }
            }
            Component.onDestruction: {
                delayGrabTimer.stop()
                GlobalFocusGrab.removeDismissable(win)
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    if (win.isGrabbed) {
                        GlobalStates.skwdWallOpen = false
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: win.effectiveOpen
                onClicked: GlobalStates.skwdWallOpen = false
            }

            // Floating content — no card, no border, no fill — pinned at top
            Item {
                id: card
                focus: true
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut
                width: Math.min(parent.width - 2 * Appearance.sizes.hyprlandGapsOut, root.cardWidth)
                height: Math.min(parent.height - anchors.topMargin - Appearance.sizes.hyprlandGapsOut, root.cardHeight)

                opacity: win.effectiveOpen ? 1 : 0
                visible: opacity > 0.01
                scale: win.effectiveOpen ? 1 : 0.97
                transformOrigin: Item.Top

                Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on scale   { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                // Lazy + delayed-unload: load on open, keep alive ~260 ms
                // after close so the fade-out can run before the Process
                // objects / wallpaper arrays inside the content are torn
                // down. Reopen re-instantiates and Component.onCompleted
                // inside SkwdWallContent restores the saved state.
                Loader {
                    id: contentLoader
                    anchors.fill: parent
                    active: false
                    asynchronous: true
                    sourceComponent: SkwdWallContent {
                        onClose: GlobalStates.skwdWallOpen = false
                    }
                }
                Timer {
                    id: unloadTimer
                    interval: 260
                    repeat: false
                    onTriggered: if (!win.effectiveOpen) contentLoader.active = false
                }
                Connections {
                    target: win
                    function onEffectiveOpenChanged() {
                        if (win.effectiveOpen) {
                            contentLoader.active = true
                            unloadTimer.stop()
                        } else {
                            unloadTimer.restart()
                        }
                    }
                }
            }
        }
    }

    // GlobalShortcut moved to panelFamilies/Shortcuts.qml.
}
