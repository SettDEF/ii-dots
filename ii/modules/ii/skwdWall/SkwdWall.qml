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
    readonly property real cardHeight: 680
    readonly property real cardRounding: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData

            readonly property bool isFocusedScreen: {
                // See Lock.qml: modelData is briefly null while Variants
                // re-models around a monitor change.
                if (!modelData) return false
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
            // Sit on Top so the launcher (Overlay) can float ABOVE us — skwd
            // is the display, the launcher bar/dropdown is the control on top.
            WlrLayershell.layer: WlrLayer.Top
            // Grant keyboard focus while open so typing in the search field
            // doesn't bleed through — BUT not while the launcher is open, since
            // the launcher owns the keyboard then (its searchbar drives skwd).
            WlrLayershell.keyboardFocus: (win.effectiveOpen && !GlobalStates.overviewOpen)
                ? WlrKeyboardFocus.OnDemand
                : WlrKeyboardFocus.None

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            mask: effectiveOpen ? maskOpen : maskClosed
            Region { id: maskClosed }
            // Everything lives inside the card now (the completion entries
            // are inline in the search panel), so the card region is enough.
            Region {
                id: maskOpen
                item: card
            }

            Timer {
                id: delayGrabTimer
                interval: 200
                repeat: false
                onTriggered: {
                    if (win.effectiveOpen) {
                        // Don't steal keyboard focus from the launcher when it
                        // is the one in charge.
                        if (!GlobalStates.overviewOpen) card.forceActiveFocus()
                        GlobalFocusGrab.addDismissable(win)
                        win.isGrabbed = true
                    }
                }
            }

            onEffectiveOpenChanged: {
                if (effectiveOpen) {
                    delayGrabTimer.restart()
                    // Bring up the launcher bar — skwd has no toolbar of its
                    // own any more, the launcher's search bar is it.
                    if (!GlobalStates.overviewOpen) {
                        const sub = WallpaperHub.lastSub.length > 0
                            ? WallpaperHub.lastSub
                            : (Persistent.states.skwd?.query || "wallpapers")
                        // Only reuse the last typed text if it actually names a
                        // sub — a bare "r/" would leave the bar looking empty.
                        const last = WallpaperHub.lastQuery
                        const useLast = last.replace(/^\/?skwd\s*/i, "").replace(/^r\//i, "").trim().length > 0
                        GlobalStates.requestLauncherSearch(useLast ? last : `r/${sub}`)
                    }
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

            // Floating content — no card, no border, no fill — pinned at top.
            // The only solid surface is the combined metadata+search panel
            // inside SkwdWallContent; the carousel floats over the desktop.
            Item {
                id: card
                focus: true

                // Breathing room between the launcher's details dropdown and
                // the carousel. hyprlandGapsOut is 5px — far too tight to read
                // as separation once a ~300px panel is sitting above.
                readonly property real detailsClearance: 40
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                // Pushed down by whatever the launcher's details dropdown is
                // occupying, so the wallpapers move rather than being covered.
                //
                // Plus a full gap on top of that: clearing the panel's height
                // exactly leaves the carousel butted right against it, which
                // reads as "not moved far enough" rather than as two separate
                // surfaces. The gap only applies while the drawer is open, so
                // the closed layout is untouched.
                anchors.topMargin: Appearance.sizes.barHeight
                    + Appearance.sizes.hyprlandGapsOut
                    + WallpaperHub.detailsHeight
                    + (WallpaperHub.detailsHeight > 1 ? card.detailsClearance : 0)
                Behavior on anchors.topMargin {
                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                }
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
