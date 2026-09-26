pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.shelf

Scope {
    id: bar
    property bool showBarBackground: Config.options.bar.showBackground

    Variants {
        // For each monitor
        model: {
            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }
        LazyLoader {
            id: barLoader
            active: GlobalStates.barOpen && !GlobalStates.screenLocked
            required property ShellScreen modelData
            component: PanelWindow { // Bar window
                id: barRoot
                screen: barLoader.modelData

                Timer {
                    id: showBarTimer
                    interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
                    repeat: false
                    onTriggered: {
                        barRoot.superShow = true
                    }
                }
                Connections {
                    target: GlobalStates
                    function onSuperDownChanged() {
                        if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable) return;
                        if (GlobalStates.superDown) showBarTimer.restart();
                        else {
                            showBarTimer.stop();
                            barRoot.superShow = false;
                        }
                    }
                }
                property bool superShow: false
                property bool mustShow: hoverRegion.containsMouse || superShow

                // Per MONITOR, not per focused workspace: a game fullscreen
                // on one display must not blank the bar on the other.
                readonly property bool fullscreenHere: {
                    if (!(Config?.options.bar.autoHide.onFullscreen ?? true)) return false;
                    const mon = (HyprlandData.monitors ?? []).find(m => m?.name === barRoot.screen?.name);
                    const wsId = mon?.activeWorkspace?.id;
                    if (wsId === undefined || wsId === null) return false;
                    return (HyprlandData.workspaceById?.[wsId]?.hasfullscreen) === true;
                }
                // Hovering the edge still reveals it.
                readonly property bool hidden: !mustShow
                    && ((Config?.options.bar.autoHide.enable ?? false) || barRoot.fullscreenHere)
                readonly property real shelfHeight: Math.round(barRoot.screen.height * 0.20)
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: (barRoot.fullscreenHere || (Config?.options.bar.autoHide.enable && (!mustShow || !Config?.options.bar.autoHide.pushWindows))) ? 0 :
                    Appearance.sizes.baseBarHeight + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
                    + (GlobalStates.shelfOpen ? barRoot.shelfHeight : 0)
                WlrLayershell.namespace: "quickshell:bar"
                // Always full height — never resize the Wayland window, clip shelf internally
                implicitHeight: Appearance.sizes.barHeight + Appearance.rounding.screenRounding + barRoot.shelfHeight
                mask: Region {
                    item: hoverMaskRegion
                }
                color: "transparent"

                // Positioning
                anchors {
                    top: !Config.options.bar.bottom
                    bottom: Config.options.bar.bottom
                    left: true
                    right: true
                }

                margins {
                    right: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * -1
                    bottom: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * -1
                }

                // Include in focus grab
                Component.onCompleted: {
                    GlobalFocusGrab.addPersistent(barRoot);
                }
                Component.onDestruction: {
                    GlobalFocusGrab.removePersistent(barRoot);
                }

                MouseArea  {
                    id: hoverRegion
                    hoverEnabled: true
                    propagateComposedEvents: true
                    anchors {
                        fill: parent
                        rightMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * 1
                        bottomMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * 1
                    }

                    Item {
                        id: hoverMaskRegion
                        anchors.left: parent.left
                        anchors.right: parent.right
                        y: barContent.y - Config.options.bar.autoHide.hoverRegionWidth
                        height: barContent.height + Config.options.bar.autoHide.hoverRegionWidth * 2
                            + shelfClip.shelfClipHeight
                    }

                    BarContent {
                        id: barContent
                        
                        implicitHeight: Appearance.sizes.barHeight
                        anchors {
                            right: parent.right
                            left: parent.left
                            top: parent.top
                            bottom: undefined
                            topMargin: barRoot.hidden ? -Appearance.sizes.barHeight : 0
                            bottomMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * -1
                            rightMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * -1
                        }
                        Behavior on anchors.topMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on anchors.bottomMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: barContent
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: parent.bottom
                                }
                            }
                            PropertyChanges {
                                target: barContent
                                anchors.topMargin: 0
                                anchors.bottomMargin: barRoot.hidden ? -Appearance.sizes.barHeight : 0
                            }
                        }
                    }

                    // Round decorators
                    Loader {
                        id: roundDecorators
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: barContent.bottom
                            bottom: undefined
                        }
                        height: Appearance.rounding.screenRounding
                        active: showBarBackground && Config.options.bar.cornerStyle === 0 // Hug

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: roundDecorators
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: barContent.top
                                }
                            }
                        }

                        sourceComponent: Item {
                            implicitHeight: Appearance.rounding.screenRounding
                            RoundCorner {
                                id: leftCorner
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: parent.left
                                }

                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? Appearance.colors.colLayer0 : "transparent"

                                corner: RoundCorner.CornerEnum.TopLeft
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges {
                                        leftCorner.corner: RoundCorner.CornerEnum.BottomLeft
                                    }
                                }
                            }
                            RoundCorner {
                                id: rightCorner
                                anchors {
                                    right: parent.right
                                    top: !Config.options.bar.bottom ? parent.top : undefined
                                    bottom: Config.options.bar.bottom ? parent.bottom : undefined
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? Appearance.colors.colLayer0 : "transparent"

                                corner: RoundCorner.CornerEnum.TopRight
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges {
                                        rightCorner.corner: RoundCorner.CornerEnum.BottomRight
                                    }
                                }
                            }
                        }
                    }

                    // Shelf panel — clips height internally, window never resizes
                    Item {
                        id: shelfClip
                        anchors {
                            top: barContent.bottom
                            left: parent.left
                            right: parent.right
                        }
                        height: shelfClipHeight
                        clip: true

                        property real shelfClipHeight: GlobalStates.shelfOpen ? barRoot.shelfHeight : 0
                        Behavior on shelfClipHeight { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                        Rectangle {
                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                            }
                            height: barRoot.shelfHeight
                            color: Appearance.colors.colLayer0
                            // Border removed — the 1px colLayer0Border read as a
                            // hard separator between the bar and the shelf body.
                            border.width: 0

                            // ShelfContent is heavy (file tree + media + battle).
                            // Don't instantiate until first open; keep it loaded
                            // during the close animation, then unload after idle.
                            Timer {
                                id: shelfUnloadTimer
                                interval: 350           // matches close animation
                                repeat: false
                            }
                            Connections {
                                target: GlobalStates
                                function onShelfOpenChanged() {
                                    if (!GlobalStates.shelfOpen) shelfUnloadTimer.restart()
                                    else                          shelfUnloadTimer.stop()
                                }
                            }

                            Loader {
                                anchors.fill: parent
                                active: GlobalStates.shelfOpen || shelfUnloadTimer.running
                                asynchronous: true
                                sourceComponent: ShelfContent {
                                    transform: Translate {
                                        y: GlobalStates.shelfOpen ? 0 : -12
                                        Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "shelf"
        function toggle(): void { GlobalStates.shelfOpen = !GlobalStates.shelfOpen }
        function open(): void   { GlobalStates.shelfOpen = true }
        function close(): void  { GlobalStates.shelfOpen = false }
    }

    GlobalShortcut {
        name: "shelfToggle"
        description: "Toggle file shelf"
        onPressed: GlobalStates.shelfOpen = !GlobalStates.shelfOpen
    }

    // Shelf-tab shortcuts are *contextual* — they only switch tabs when
    // the shelf is already open. With shelf closed they do nothing,
    // which lets the same keys be bound to other things globally
    // without conflict (and matches how vi-style modal keybinds work).
    GlobalShortcut {
        name: "shelfTabFiles"
        description: "Switch shelf to Files tab (only when shelf is open)"
        onPressed: { if (GlobalStates.shelfOpen) GlobalStates.shelfTab = "files" }
    }

    GlobalShortcut {
        name: "shelfTabBattle"
        description: "Switch shelf to Battle tab (only when shelf is open)"
        onPressed: { if (GlobalStates.shelfOpen) GlobalStates.shelfTab = "battle" }
    }

    GlobalShortcut {
        name: "shelfTabMedia"
        description: "Switch shelf to Media tab (only when shelf is open)"
        onPressed: { if (GlobalStates.shelfOpen) GlobalStates.shelfTab = "media" }
    }

    IpcHandler {
        target: "bar"

        function toggle(): void {
            GlobalStates.barOpen = !GlobalStates.barOpen
        }

        function close(): void {
            GlobalStates.barOpen = false
        }

        function open(): void {
            GlobalStates.barOpen = true
        }
    }

    GlobalShortcut {
        name: "barToggle"
        description: "Toggles bar on press"

        onPressed: {
            GlobalStates.barOpen = !GlobalStates.barOpen;
        }
    }

    GlobalShortcut {
        name: "barOpen"
        description: "Opens bar on press"

        onPressed: {
            GlobalStates.barOpen = true;
        }
    }

    GlobalShortcut {
        name: "barClose"
        description: "Closes bar on press"

        onPressed: {
            GlobalStates.barOpen = false;
        }
    }

}
