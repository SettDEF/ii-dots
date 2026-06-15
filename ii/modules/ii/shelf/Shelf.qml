pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    Variants {
        model: {
            const screens = Quickshell.screens
            const list = Config.options.bar.screenList
            if (!list || list.length === 0) return screens
            return screens.filter(s => list.includes(s.name))
        }

        LazyLoader {
            id: shelfLoader
            required property ShellScreen modelData
            active: true

            component: PanelWindow {
                id: shelfWin
                screen: shelfLoader.modelData

                readonly property HyprlandMonitor hyprMonitor: Hyprland.monitorFor(shelfLoader.modelData)
                readonly property bool isActiveMonitor: Hyprland.focusedMonitor?.id === hyprMonitor?.id

                readonly property real shelfHeight: 500
                readonly property real shelfWidth:  700

                // Position: top-left, just below the bar
                anchors.top:  !Config.options.bar.bottom
                anchors.bottom: Config.options.bar.bottom
                anchors.left: true
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: "quickshell:shelf"
                // OnDemand keyboard focus — path editor TextInput in
                // ShelfManagePaths needs key events to reach it.
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
                exclusionMode: ExclusionMode.Normal
                // Each monitor reserves its zone whenever the shelf is open,
                // independent of which monitor is currently focused. Coupling
                // the zone to `isActiveMonitor` made Hyprland retile every
                // window on every focused-monitor change (mouse jitter at the
                // boundary with mouse_move_focuses_monitor=1 → infinite loop).
                exclusiveZone: GlobalStates.shelfOpen ? shelfWin.shelfHeight : 0
                color: "transparent"

                implicitWidth:  shelfWin.shelfWidth
                implicitHeight: shelfWin.shelfHeight

                margins.top: Appearance.sizes.barHeight
                    + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)

                // Only the card area receives input
                mask: Region { item: shelfWin.isActiveMonitor ? shelfPanel : null }

                Component.onCompleted: GlobalFocusGrab.addDismissable(shelfWin)
                Component.onDestruction: GlobalFocusGrab.removeDismissable(shelfWin)
                Connections {
                    target: GlobalFocusGrab
                    function onDismissed() { GlobalStates.shelfOpen = false }
                }

                // ── The panel ─────────────────────────────────────────────
                Item {
                    id: shelfPanel
                    anchors { top: parent.top; left: parent.left }
                    width:  shelfWin.shelfWidth
                    height: contentClip.height + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)

                    // Drop shadow
                    StyledRectangularShadow {
                        anchors.fill: contentClip
                        target: contentClip
                        visible: GlobalStates.shelfOpen
                    }

                    // Clip container — height animates
                    Rectangle {
                        id: contentClip
                        anchors { top: parent.top; left: parent.left }
                        anchors.topMargin: Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0
                        anchors.leftMargin: Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0
                        width: shelfWin.shelfWidth - (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
                        height: (GlobalStates.shelfOpen && shelfWin.isActiveMonitor) ? shelfWin.shelfHeight : 0
                        clip: true
                        color: "transparent"

                        Behavior on height {
                            NumberAnimation {
                                duration: 340
                                easing.type: Easing.OutCubic
                            }
                        }

                        // Content slides + fades in
                        Item {
                            id: contentWrapper
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            height: shelfWin.shelfHeight
                            opacity: (GlobalStates.shelfOpen && shelfWin.isActiveMonitor) ? 1 : 0
                            transform: Translate {
                                y: (GlobalStates.shelfOpen && shelfWin.isActiveMonitor) ? 0 : -20
                                Behavior on y {
                                    NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                                }
                            }
                            Behavior on opacity {
                                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                            }

                            // Lazy: only build the shelf body for the monitor
                            // that's currently focused, and only after the
                            // shelf has been opened at least once. Without
                            // this gate, ShelfContent (file watchers, media
                            // taps, Battle Repeater + per-path inotifywaits)
                            // is duplicated per monitor at quickshell start.
                            Loader {
                                anchors.fill: parent
                                active: shelfWin.isActiveMonitor
                                    && (GlobalStates.shelfOpen || _hasBeenOpen)
                                property bool _hasBeenOpen: false
                                Connections {
                                    target: GlobalStates
                                    function onShelfOpenChanged() {
                                        if (GlobalStates.shelfOpen) parent._hasBeenOpen = true
                                    }
                                }
                                sourceComponent: ShelfContent { anchors.fill: parent }
                            }
                        }
                    }
                }
            }
        }
    }

    // IpcHandler + GlobalShortcut moved to panelFamilies/Shortcuts.qml so they
    // stay registered while this panel is unloaded by LazyPanelLoader.
}
