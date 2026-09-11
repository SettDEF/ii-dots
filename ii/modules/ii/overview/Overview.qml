import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt.labs.synchronizer
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false

    PanelWindow {
        id: panelWindow
        property string searchingText: ""
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
        property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
        readonly property var overviewWidget: overviewLoader.item
        visible: GlobalStates.overviewOpen

        WlrLayershell.namespace: "quickshell:overview"
        // Overlay so the launcher floats ABOVE skwd (which sits on Top) — the
        // bar + subreddit dropdown stay on top of skwd's wallpapers.
        WlrLayershell.layer: WlrLayer.Overlay
        // Request keyboard focus from the compositor while the overview is
        // open — otherwise typing still goes to whichever window was focused
        // when Super was pressed, and the search field receives no input.
        // OnDemand (not Exclusive) lets Hyprland keep handling its own
        // shortcuts (e.g. Super+arrow workspace switches) while still routing
        // text keystrokes here. Was previously commented out, which produced
        // the intermittent "can't type in overview" bug.
        WlrLayershell.keyboardFocus: GlobalStates.overviewOpen
            ? WlrKeyboardFocus.OnDemand
            : WlrKeyboardFocus.None
        color: "transparent"

        // Input region: the bar strip, the (narrow) dropdown and the workspace
        // grid — masked separately rather than as one bounding box, so the rest
        // of the screen stays scroll-through and skwd below gets the wheel.
        mask: Region {
            item: GlobalStates.overviewOpen ? searchWidget : null
            height: searchWidget.barBandHeight
            regions: [dropdownRegion, gridRegion, resultsRegion]
        }
        Region { id: dropdownRegion; item: searchWidget.dropdownItem }
        Region { id: gridRegion; item: overviewLoader.item }
        Region { id: resultsRegion; item: searchWidget.resultsItem }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Connections {
            target: GlobalStates
            function onOverviewOpenChanged() {
                if (!GlobalStates.overviewOpen) {
                    searchWidget.disableExpandAnimation();
                    overviewScope.dontAutoCancelSearch = false;
                    GlobalFocusGrab.dismiss();
                } else {
                    if (WallpaperHub.lastQuery.length > 0) {
                        // Reopening lands you where you left off: the query is
                        // back in the field and the wallpapers come back with
                        // it. skwd restores its own sub/index from Persistent,
                        // so we don't re-navigate it (that fought fresh typing).
                        if (WallpaperHub.lastSub.length > 0)
                            GlobalStates.skwdWallOpen = true;
                        // Text selected, so typing replaces rather than appends.
                        searchWidget.restoreSearchingText(WallpaperHub.lastQuery);
                    } else if (!overviewScope.dontAutoCancelSearch) {
                        searchWidget.cancelSearch();
                    }
                    GlobalFocusGrab.addDismissable(panelWindow);
                }
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                GlobalStates.overviewOpen = false;
            }
        }

        // skwd asking for its bar: the launcher opens (if it isn't already)
        // with the wallpaper query in the field, which puts the bar in skwd
        // mode. One bar, and it's this one.
        Connections {
            target: GlobalStates
            function onRequestLauncherSearch(text) {
                overviewScope.dontAutoCancelSearch = true;
                // Restored text must not pop the dropdown open over skwd.
                WallpaperHub.dropdownSuppressed = true;
                searchWidget.restoreSearchingText(text);
                GlobalStates.overviewOpen = true;
            }
        }
        implicitWidth: columnLayout.implicitWidth
        implicitHeight: columnLayout.implicitHeight

        function setSearchingText(text) {
            searchWidget.setSearchingText(text);
            searchWidget.focusFirstItem();
        }

        Column {
            id: columnLayout
            visible: GlobalStates.overviewOpen
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
            }
            spacing: -8

            Keys.onPressed: event => {
                // Left/Right workspace stepping lives in SearchBar's handler —
                // the focused search field consumes arrow keys before they can
                // bubble up to here.
                if (event.key === Qt.Key_Escape) {
                    GlobalStates.overviewOpen = false;
                }
            }

            SearchWidget {
                id: searchWidget
                anchors.horizontalCenter: parent.horizontalCenter
                Synchronizer on searchingText {
                    property alias source: panelWindow.searchingText
                }
            }

            Loader {
                id: overviewLoader
                anchors.horizontalCenter: parent.horizontalCenter
                // Unload the workspace grid while searching — an invisible item
                // still takes space, which kept the window mask tall enough to
                // cover skwd below and swallow its scroll. Gone while typing.
                // Also gone while the sort & filter dropdown is open — it is a
                // full-height panel in the launcher, and leaving the workspace
                // grid below it pushed the dropdown off-screen and looked like
                // two unrelated surfaces stacked.
                active: GlobalStates.overviewOpen && (Config?.options.overview.enable ?? true)
                        && panelWindow.searchingText === ""
                        && !searchWidget.sortSettingsOpen
                sourceComponent: OverviewWidget {
                    screen: panelWindow.screen
                    visible: (panelWindow.searchingText == "") && !searchWidget.sortSettingsOpen
                }
            }
        }

    }

    function toggleClipboard() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.clipboard);
        GlobalStates.overviewOpen = true;
    }

    function toggleEmojis() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.emojis);
        GlobalStates.overviewOpen = true;
    }

    IpcHandler {
        target: "search"

        function toggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function workspacesToggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            GlobalStates.overviewOpen = true;
        }
        function toggleReleaseInterrupt() {
            GlobalStates.superReleaseMightTrigger = false;
        }
        function clipboardToggle() {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"

        onPressed: {
            GlobalStates.overviewOpen = false;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
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
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
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
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "To make sure this works consistently, use binditn = MODKEYS, catchall in an automatically triggered submap that includes everything."

        onPressed: {
            // Hyprland 0.55.4's catchall fires once for the Super press
            // itself; only interrupts arriving clearly after the press are a
            // real "other key pressed while holding Super".
            if (Date.now() - GlobalStates.superPressTime > 80) {
                GlobalStates.superReleaseMightTrigger = false;
            }
        }
    }
    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on overview widget"

        onPressed: {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on overview widget"

        onPressed: {
            overviewScope.toggleEmojis();
        }
    }
}
