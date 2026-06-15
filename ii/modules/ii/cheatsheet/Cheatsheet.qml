import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.synchronizer
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    property var tabButtonList: [
        {
            "icon": "keyboard",
            "name": Translation.tr("Keybinds")
        },
        {
            "icon": "swipe",
            "name": Translation.tr("Swipes")
        },
        {
            "icon": "menu_book",
            "name": Translation.tr("Cheatsheets")
        },
        {
            "icon": "experiment",
            "name": Translation.tr("Elements")
        },
    ]

    property bool open: false

    Timer {
        id: closeTimer
        interval: 250
        repeat: false
    }

    onOpenChanged: {
        if (!open) {
            closeTimer.start();
        }
    }

    Loader {
        id: cheatsheetLoader
        active: root.open || closeTimer.running

        sourceComponent: PanelWindow { // Window
            id: cheatsheetRoot
            visible: root.open

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            function hide() {
                root.open = false;
            }
            exclusiveZone: 0
            implicitWidth: cheatsheetBackground.width + Appearance.sizes.elevationMargin * 2
            implicitHeight: cheatsheetBackground.height + Appearance.sizes.elevationMargin * 2
            WlrLayershell.namespace: "quickshell:cheatsheet"
            // Hyprland 0.49: Focus is always exclusive and setting this breaks mouse focus grab
            // WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            mask: Region {
                item: cheatsheetBackground
            }

            Component.onCompleted: {
                GlobalFocusGrab.addDismissable(cheatsheetRoot);
            }
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(cheatsheetRoot);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    cheatsheetRoot.hide();
                }
            }

            // Background
            StyledRectangularShadow {
                target: cheatsheetBackground
            }
            Rectangle {
                id: cheatsheetBackground
                anchors.centerIn: parent
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                radius: Appearance.rounding.windowRounding
                
                opacity: 0
                scale: 0.95

                states: [
                    State {
                        name: "visible"
                        when: cheatsheetRoot.visible
                        PropertyChanges { target: cheatsheetBackground; opacity: 1; scale: 1 }
                    },
                    State {
                        name: "hidden"
                        when: !cheatsheetRoot.visible
                        PropertyChanges { target: cheatsheetBackground; opacity: 0; scale: 0.95 }
                    }
                ]

                transitions: [
                    Transition {
                        from: "hidden"; to: "visible"
                        ParallelAnimation {
                            NumberAnimation { properties: "opacity"; duration: 200; easing.type: Easing.OutCubic }
                            NumberAnimation { properties: "scale"; duration: 250; easing.type: Easing.OutBack }
                        }
                    },
                    Transition {
                        from: "visible"; to: "hidden"
                        ParallelAnimation {
                            NumberAnimation { properties: "opacity"; duration: 180; easing.type: Easing.InCubic }
                            NumberAnimation { properties: "scale"; duration: 200; easing.type: Easing.InCubic }
                        }
                    }
                ]
                property real padding: 20
                // Lock the window to a stable size up front. Tabs are
                // lazy-loaded (`active: SwipeView.isCurrentItem`), so a
                // content-driven implicitWidth/Height starts at near-zero
                // and grows as the active tab loads — that produced the
                // "starts small then jumps larger" bug. A fixed target
                // (capped at 92 % of the screen for safety) avoids the
                // race entirely; content scrolls inside if it overflows.
                readonly property real maxW: (cheatsheetRoot.screen?.width  ?? 1920) * 0.92
                readonly property real maxH: (cheatsheetRoot.screen?.height ?? 1080) * 0.92
                readonly property real targetW: 1200
                readonly property real targetH: 800
                implicitWidth:  Math.min(maxW, targetW)
                implicitHeight: Math.min(maxH, targetH)

                Keys.onPressed: event => { // Esc to close
                    if (event.key === Qt.Key_Escape) {
                        cheatsheetRoot.hide();
                    }
                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_PageDown) {
                            tabBar.incrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageUp) {
                            tabBar.decrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab) {
                            tabBar.setCurrentIndex((tabBar.currentIndex + 1) % root.tabButtonList.length);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backtab) {
                            tabBar.setCurrentIndex((tabBar.currentIndex - 1 + root.tabButtonList.length) % root.tabButtonList.length);
                            event.accepted = true;
                        }
                    }
                }

                RippleButton { // Close button
                    id: closeButton
                    focus: cheatsheetRoot.visible
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    anchors {
                        top: parent.top
                        right: parent.right
                        topMargin: 20
                        rightMargin: 20
                    }

                    onClicked: {
                        cheatsheetRoot.hide();
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.title
                        text: "close"
                    }
                }

                ColumnLayout { // Real content
                    id: cheatsheetColumnLayout
                    // Fill the card (with the background's padding) instead
                    // of centerIn — centerIn lets the column be wider
                    // than its container, which then renders past the
                    // rounded card edges. fill clamps it to the card.
                    anchors.fill: parent
                    anchors.margins: cheatsheetBackground.padding
                    spacing: 10

                    Toolbar {
                        Layout.alignment: Qt.AlignHCenter
                        enableShadow: false
                        ToolbarTabBar {
                            id: tabBar
                            tabButtonList: root.tabButtonList

                            Synchronizer on currentIndex {
                                property alias source: swipeView.currentIndex
                            }
                        }
                    }

                    SwipeView { // Content pages
                        id: swipeView
                        Layout.topMargin: 5
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10
                        currentIndex: Persistent.states.cheatsheet.tabIndex
                        onCurrentIndexChanged: {
                            Persistent.states.cheatsheet.tabIndex = currentIndex;
                        }

                        // Cap implicit size to the *card's* available space,
                        // not the screen's. Content larger than that scrolls
                        // inside the page's own ScrollView.
                        implicitWidth:  Math.max(0,
                            cheatsheetBackground.width - cheatsheetBackground.padding * 2)
                        implicitHeight: Math.max(0,
                            cheatsheetBackground.height - cheatsheetBackground.padding * 2 - 80)

                        clip: true
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: swipeView.width
                                height: swipeView.height
                                radius: Appearance.rounding.small
                            }
                        }

                        // Each page wrapped in ScrollView so it scrolls
                        // gracefully when content is taller than the window.
                        // Pages — order MUST match tabButtonList above.
                        TabLoader { active: SwipeView.isCurrentItem; sourceComponent: keybindsComp }
                        TabLoader { active: SwipeView.isCurrentItem; sourceComponent: swipesComp }
                        TabLoader { active: SwipeView.isCurrentItem; sourceComponent: markdownComp }
                        TabLoader { active: SwipeView.isCurrentItem; sourceComponent: elementsComp }
                    }
                    // Page Components live OUTSIDE the SwipeView so they
                    // aren't treated as pages themselves.
                    Component { id: keybindsComp
                        ScrollView {
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                            clip: true
                            CheatsheetKeybinds {}
                        }
                    }
                    Component { id: elementsComp
                        ScrollView {
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                            clip: true
                            CheatsheetPeriodicTable {}
                        }
                    }
                    Component { id: markdownComp; CheatsheetMarkdown {} }
                    Component { id: swipesComp;   CheatsheetSwipes   {} }
                }
            }
        }
    }

    IpcHandler {
        target: "cheatsheet"

        function toggle(): void {
            root.open = !root.open;
        }

        function close(): void {
            root.open = false;
        }

        function open(): void {
            root.open = true;
        }
    }

    GlobalShortcut {
        name: "cheatsheetToggle"
        description: "Toggles cheatsheet on press"

        onPressed: {
            root.open = !root.open;
        }
    }

    GlobalShortcut {
        name: "cheatsheetOpen"
        description: "Opens cheatsheet on press"

        onPressed: {
            root.open = true;
        }
    }

    GlobalShortcut {
        name: "cheatsheetClose"
        description: "Closes cheatsheet on press"

        onPressed: {
            root.open = false;
        }
    }
}
