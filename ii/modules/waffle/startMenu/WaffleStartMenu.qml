import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: root

    Connections {
        target: GlobalStates

        function onSearchOpenChanged() {
            if (GlobalStates.searchOpen) {
                LauncherSearch.query = "";
                panelLoader.active = true;
            }
        }
    }

    Loader {
        id: panelLoader
        active: GlobalStates.searchOpen
        sourceComponent: PanelWindow {
            id: panelWindow
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:wStartMenu"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors {
                bottom: Config.options.waffles.bar.bottom
                top: !Config.options.waffles.bar.bottom
                left: Config.options.waffles.bar.leftAlignApps
            }

            implicitWidth: content.implicitWidth
            implicitHeight: content.implicitHeight

            HyprlandFocusGrab {
                id: focusGrab
                active: true
                windows: [panelWindow]
                onCleared: content.close()
            }

            Connections {
                target: GlobalStates
                function onSearchOpenChanged() {
                    if (!GlobalStates.searchOpen)
                        content.close();
                }
            }

            StartMenuContent {
                id: content
                // the screen less the taskbar and a gap above and below
                maxWidth: (panelWindow.screen?.width ?? 1920) - 32
                maxHeight: (panelWindow.screen?.height ?? 1080) - 96
                anchors.fill: parent
                focus: true

                onClosed: {
                    GlobalStates.searchOpen = false;
                    panelLoader.active = false;
                    LauncherSearch.query = "";
                }
            }
        }
    }

    function toggleClipboard() {
        if (LauncherSearch.query.startsWith(Config.options.search.prefix.clipboard) || !GlobalStates.searchOpen) {
            GlobalStates.searchOpen = !GlobalStates.searchOpen;
        }
        LauncherSearch.ensurePrefix(Config.options.search.prefix.clipboard);
    }
    function toggleEmojis() {
        if (LauncherSearch.query.startsWith(Config.options.search.prefix.emojis) || !GlobalStates.searchOpen) {
            GlobalStates.searchOpen = !GlobalStates.searchOpen;
        }
        LauncherSearch.ensurePrefix(Config.options.search.prefix.emojis);
    }

    IpcHandler {
        id: searchIpc
        target: "search"

        function toggle() {
            GlobalStates.searchOpen = !GlobalStates.searchOpen;
        }
        function close() {
            GlobalStates.searchOpen = false;
        }
        function open() {
            GlobalStates.searchOpen = true;
        }
        function toggleReleaseInterrupt() {
            GlobalStates.superReleaseMightTrigger = false;
        }
        /// Bound to the Super RELEASE: toggles only for a bare tap (no key or click since Super
        /// went down, not held long), as ii's overview does
        function releaseToggle() {
            const interrupted = GlobalStates.superInterruptTime >= GlobalStates.superPressTime - 30;
            if (interrupted || Date.now() - GlobalStates.superPressTime > 800) return;
            GlobalStates.searchOpen = !GlobalStates.searchOpen;
        }
    }

    // What the Super key's release bind sends (hypr keybinds: quickshell:searchReleaseTap). Only
    // ii's overview had it, so in this family tapping Super did nothing.
    GlobalShortcut {
        name: "searchReleaseTap"
        description: "Super tap released: toggle the start menu unless it was a combo"
        // Whichever event arrives, once per Super press.
        property real handledPress: -1
        function handle() {
            if (GlobalStates.superPressTime === handledPress) return;
            handledPress = GlobalStates.superPressTime;
            searchIpc.releaseToggle();
        }
        onPressed: handle()
        onReleased: handle()
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            GlobalStates.searchOpen = !GlobalStates.searchOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on release"

        onPressed: {
            GlobalStates.superPressTime = Date.now();
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            GlobalStates.searchOpen = !GlobalStates.searchOpen;
        }
    }
    GlobalShortcut {
        name: "superComboInterrupt"
        description: "Cancels the pending Super-tap toggle because another key was pressed while Super was held. Bound per-combo (see hypr lua/hyprland/super_interrupts.lua) since 0.56 restricts catchall binds to submaps."

        onPressed: {
            // No timing guard, unlike searchToggleReleaseInterrupt: this only
            // ever fires from a real SUPER+<key> bind, so there is no
            // self-fire from the Super press to filter out.
            GlobalStates.superReleaseMightTrigger = false;
            // releaseToggle() reads this, not the flag above
            GlobalStates.superInterruptTime = Date.now();
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "To make sure this works consistently, use binditn = MODKEYS, catchall in an automatically triggered submap that includes everything."

        onPressed: {
            // Ignore Hyprland 0.55.4's phantom catchall on the Super press
            // itself (see Overview.qml).
            if (Date.now() - GlobalStates.superPressTime > 80) {
                GlobalStates.superReleaseMightTrigger = false;
            }
            GlobalStates.superInterruptTime = Date.now();
        }
    }

    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on overview widget"

        onPressed: {
            root.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on overview widget"

        onPressed: {
            root.toggleEmojis();
        }
    }
}
