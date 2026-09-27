pragma ComponentBehavior: Bound

import Qt.labs.synchronizer
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item { // Wrapper
    id: root

    readonly property string xdgConfigHome: Directories.config
    readonly property int typingDebounceInterval: 200
    // Was hardcoded 15. Now driven by the "Maximum results" setting in the
    // sort & filter panel, so that control actually does something.
    readonly property int typingResultLimit: Config.options?.launcher?.maxResults ?? 15

    property string searchingText: LauncherSearch.query
    property bool showResults: searchingText != ""
    // Theme/wallpaper picker mode — query starts with the theme prefix.
    readonly property bool themeMode: searchingText.startsWith(Config.options.search.prefix.theme)
    // skwd wallpaper-hub mode — `/skwd <sub>` or `r/<sub>`. The searchbar stays
    // put but shrinks to make room for skwd's source icons + colour columns
    // (see SearchBar), and the result list is replaced by a wallpaper grid.
    readonly property bool skwdMode: {
        const t = searchingText.toLowerCase();
        return t.startsWith("/skwd") || t.startsWith("r/");
    }
    readonly property string skwdSub: {
        const t = searchingText;
        let s = "";
        if (t.toLowerCase().startsWith("/skwd")) s = t.slice(5).trim();
        else if (t.toLowerCase().startsWith("r/")) s = t.slice(2).trim();
        return s.replace(/[^A-Za-z0-9_]/g, "");
    }
    // Exposed so the subreddit dropdown can gate on the search input's focus.
    readonly property bool searchInputFocused: searchBar.searchInput.activeFocus

    // Remember the last skwd query so reopening the launcher restores it. A
    // non-skwd search clears it; an empty field (close) leaves it intact.
    onSearchingTextChanged: {
        if (skwdMode) WallpaperHub.lastQuery = searchingText;
        else if (searchingText.length > 0) WallpaperHub.lastQuery = "";

        // Typing means you want RESULTS, not settings — close the panel rather
        // than leaving you staring at switches. `/sort` is exempt: that command
        // is how the panel gets opened in the first place.
        // NOTE: merged into this existing handler on purpose. A second
        // onSearchingTextChanged on the same object silently REPLACES this one.
        if (GlobalStates.launcherSortOpen
            && !searchingText.startsWith((Config.options.search.prefix.action ?? "/") + "sort"))
            GlobalStates.launcherSortOpen = false;

        // Emptying the field activates overviewLoader, and instantiating the
        // workspace grid takes focus off the input — so clearing the query left
        // you typing into nothing. callLater so this runs after that load.
        if (searchingText.length === 0 && GlobalStates.overviewOpen)
            Qt.callLater(root.focusSearchInput);
    }
    // Exposed for the launcher window's input region: the bar strip and the
    // dropdown are masked separately so everything else stays scroll-through.
    readonly property real barBandHeight: searchBar.height + searchBar.verticalPadding * 2
        + Appearance.sizes.elevationMargin * 2
    // Open state for the sort & filter dropdown. Read straight off GlobalStates
    // (single source of truth) so the `/sort` command drives it as well as the
    // toolbar button — no local mirror to fall out of sync.
    readonly property bool sortSettingsOpen: GlobalStates.launcherSortOpen

    // Exposed to the launcher window's input mask. Must cover whichever
    // dropdown is currently showing, or its controls render but never receive
    // clicks (the window masks input to the bar band plus named regions).
    readonly property Item dropdownItem: root.sortSettingsOpen
        ? sortSettingsLoader.item
        : wallpapersLoader.item

    // Also exposed to the mask — and this one was simply missing.
    //
    // The window masks input to `searchWidget` CLIPPED TO barBandHeight (the
    // search bar strip), plus the dropdown and the workspace grid. The result
    // rows sit below that band and belonged to no region at all, so they
    // rendered perfectly and received nothing: no click to launch, no hover,
    // and no right-click — which is why the per-entry ranking menu could
    // never open and "prioritised" stayed at 0 no matter what you did.
    readonly property Item resultsItem: appResults.visible ? appResults : null

    implicitWidth: searchWidgetContent.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: searchWidgetContent.implicitHeight + searchBar.verticalPadding * 2 + Appearance.sizes.elevationMargin * 2

    function focusFirstItem() {
        appResults.currentIndex = 0;
    }

    // Tab / Shift+Tab: step the selection and mirror it into the input.
    function stepResult(back) {
        const n = appResults.count;
        if (n <= 0)
            return;
        appResults.currentIndex = back
            ? (appResults.currentIndex - 1 + n) % n
            : (appResults.currentIndex + 1) % n;

        const sel = resultModel.values[appResults.currentIndex];
        if (sel && sel.name)
            searchBar.previewText(sel.name);
    }

    function focusSearchInput() {
        searchBar.forceFocus();
    }

    function disableExpandAnimation() {
        searchBar.animateWidth = false;
    }

    function cancelSearch() {
        searchBar.searchInput.selectAll();
        LauncherSearch.query = "";
        searchBar.animateWidth = true;
    }

    function setSearchingText(text) {
        searchBar.searchInput.text = text;
        LauncherSearch.query = text;
    }

    // Restore text but select it all, so the user's next keystroke REPLACES it
    // instead of appending (which produced malformed queries like
    // "r/wallpaper/wallpapers").
    function restoreSearchingText(text) {
        searchBar.searchInput.text = text;
        LauncherSearch.query = text;
        searchBar.searchInput.selectAll();
    }

    // Drill into a command group: selecting a group result asks LauncherSearch
    // to rewrite the query (e.g. "/power " → its subcommands come into view).
    Connections {
        target: LauncherSearch
        function onRequestQuery(newQuery) {
            root.setSearchingText(newQuery);
            searchBar.forceFocus();
        }
    }

    // When the overview opens (notably via the bare Super-key release), the
    // layer surface and focus grab settle asynchronously. A single focus
    // call loses that race intermittently, leaving the search input "off".
    // Re-assert focus until it actually lands.
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen) {
                focusRetry.ticks = 0;
                focusRetry.restart();
            } else {
                focusRetry.stop();
            }
        }
    }
    Timer {
        id: focusRetry
        interval: 50
        repeat: true
        triggeredOnStart: true
        property int ticks: 0
        onTriggered: {
            searchBar.forceFocus();
            ticks++;
            if ((searchBar.searchInput.activeFocus && ticks >= 3) || ticks >= 14)
                stop();
        }
    }

    Keys.onPressed: event => {
        // Prevent Esc and Backspace from registering
        if (event.key === Qt.Key_Escape)
            return;

        // Handle Backspace: focus and delete character if not focused
        if (event.key === Qt.Key_Backspace) {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                if (event.modifiers & Qt.ControlModifier) {
                    // Delete word before cursor
                    let text = searchBar.searchInput.text;
                    let pos = searchBar.searchInput.cursorPosition;
                    if (pos > 0) {
                        // Find the start of the previous word
                        let left = text.slice(0, pos);
                        let match = left.match(/(\s*\S+)\s*$/);
                        let deleteLen = match ? match[0].length : 1;
                        searchBar.searchInput.text = text.slice(0, pos - deleteLen) + text.slice(pos);
                        searchBar.searchInput.cursorPosition = pos - deleteLen;
                    }
                } else {
                    const si = searchBar.searchInput;
                    const s = si.selectionStart, e = si.selectionEnd;
                    if (s !== e) {
                        // A selection (e.g. the recalled last query) — delete it.
                        si.text = si.text.slice(0, s) + si.text.slice(e);
                        si.cursorPosition = s;
                    } else if (si.cursorPosition > 0) {
                        // Delete the character before the cursor.
                        si.text = si.text.slice(0, si.cursorPosition - 1) + si.text.slice(si.cursorPosition);
                        si.cursorPosition -= 1;
                    }
                }
                // Always move cursor to end after programmatic edit
                searchBar.searchInput.cursorPosition = searchBar.searchInput.text.length;
                event.accepted = true;
            }
            // If already focused, let TextField handle it
            return;
        }

        // Only handle visible printable characters (ignore control chars, arrows, etc.)
        if (event.text && event.text.length === 1 && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Return && event.key !== Qt.Key_Delete && event.text.charCodeAt(0) >= 0x20) // ignore control chars like Backspace, Tab, etc.
        {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                // Insert the character — replacing any selection (e.g. the
                // recalled last query) so type-over works like a focused field.
                const si = searchBar.searchInput;
                const s = si.selectionStart, e = si.selectionEnd;
                si.text = si.text.slice(0, s) + event.text + si.text.slice(e);
                si.cursorPosition = s + 1;
                event.accepted = true;
                root.focusFirstItem();
            }
        }
    }

    StyledRectangularShadow {
        target: searchWidgetContent
    }
    Rectangle { // Background
        id: searchWidgetContent
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            topMargin: Appearance.sizes.elevationMargin
        }
        clip: true
        implicitWidth: columnLayout.implicitWidth
        implicitHeight: columnLayout.implicitHeight
        radius: searchBar.height / 2 + searchBar.verticalPadding
        color: Appearance.colors.colBackgroundSurfaceContainer

        Behavior on implicitHeight {
            id: searchHeightBehavior
            enabled: GlobalStates.overviewOpen && root.showResults
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout {
            id: columnLayout
            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
            }
            spacing: 0

            // clip: true
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: searchWidgetContent.width
                    height: searchWidgetContent.width
                    radius: searchWidgetContent.radius
                }
            }

            SearchBar {
                id: searchBar
                property real verticalPadding: 4
                // The dropdown lives here, so this owns the open state; the bar
                // only reflects it (for the button's toggled look) and asks to
                // flip it.
                sortSettingsOpen: root.sortSettingsOpen
                onSortSettingsToggled: GlobalStates.launcherSortOpen = !GlobalStates.launcherSortOpen
                onTabNavigate: back => root.stepResult(back)
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 4
                Layout.topMargin: verticalPadding
                Layout.bottomMargin: verticalPadding
                Synchronizer on searchingText {
                    property alias source: root.searchingText
                }
            }

            Rectangle {
                // Separator — hidden in skwd mode, where the dropdown collapses
                // to 0 and this 1px line would otherwise linger under the bar.
                visible: root.showResults && !root.skwdMode
                Layout.fillWidth: true
                height: 1
                color: Appearance.colors.colOutlineVariant
            }

            // Theme / wallpaper picker — replaces the result list when the
            // search query uses the theme prefix.
            Loader {
                id: themesLoader
                visible: root.themeMode
                active: root.themeMode
                Layout.fillWidth: true
                Layout.preferredHeight: 420
                sourceComponent: SearchThemes {
                    query: root.searchingText.slice(Config.options.search.prefix.theme.length)
                }
            }

            // skwd subreddit dropdown — one element inside the launcher.
            // Collapses to 0 height when not showing, so the launcher shrinks
            // back to just the bar (skwd shows below).
            Loader {
                id: wallpapersLoader
                visible: root.skwdMode
                active: root.skwdMode && GlobalStates.overviewOpen
                Layout.fillWidth: true
                Layout.preferredHeight: (item ? item.implicitHeight : 0)
                Behavior on Layout.preferredHeight {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
                sourceComponent: SearchWallpapers {
                    sub: root.skwdSub
                    inputFocused: searchBar.searchInput.activeFocus
                }
            }

            // Sort & filter settings — replaces the result list while open,
            // same as the theme/wallpaper pickers above, so it reads as part
            // of the launcher rather than a menu floating over it.
            Loader {
                id: sortSettingsLoader
                visible: root.sortSettingsOpen
                active: root.sortSettingsOpen && GlobalStates.overviewOpen
                Layout.fillWidth: true
                Layout.preferredHeight: (item ? item.implicitHeight : 0)
                Behavior on Layout.preferredHeight {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
                sourceComponent: SearchSortSettings {
                    onRequestClose: GlobalStates.launcherSortOpen = false
                }
            }

            ListView { // App results
                id: appResults
                // Deliberately NOT hidden while the settings panel is open:
                // seeing the list re-order as you change sort mode is the whole
                // point. The panel caps its own height to leave room.
                visible: root.showResults && !root.themeMode && !root.skwdMode
                Layout.fillWidth: true
                // Shorter while the settings panel is open, so both fit and the
                // live re-ordering stays on screen.
                implicitHeight: Math.min(root.sortSettingsOpen ? 260 : 600,
                    appResults.contentHeight + topMargin + bottomMargin)
                clip: true
                topMargin: 10
                bottomMargin: 10
                spacing: 2
                KeyNavigation.up: searchBar
                highlightMoveDuration: 100

                // Category headers (App · Action · Command · Math · Web).
                // Disabled for clipboard results, whose `type` is a per-entry
                // tag rather than a category.
                section.property: root.searchingText.startsWith(Config.options.search.prefix.clipboard)
                    ? "" : "type"
                section.criteria: ViewSection.FullString
                section.delegate: Rectangle {
                    required property string section
                    width: ListView.view ? ListView.view.width : 0
                    implicitHeight: 24
                    color: "transparent"
                    StyledText {
                        anchors {
                            left: parent.left; leftMargin: 10
                            verticalCenter: parent.verticalCenter
                        }
                        text: parent.section
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.45
                    }
                }

                onFocusChanged: {
                    if (focus)
                        appResults.currentIndex = 1;
                }

                Connections {
                    target: root
                    function onSearchingTextChanged() {
                        if (appResults.count > 0)
                            appResults.currentIndex = 0;
                    }
                }

                Timer {
                    id: debounceTimer
                    interval: root.typingDebounceInterval
                    onTriggered: {
                        resultModel.values = LauncherSearch.results ?? [];
                    }
                }

                Connections {
                    target: LauncherSearch
                    function onResultsChanged() {
                        resultModel.values = LauncherSearch.results.slice(0, root.typingResultLimit);
                        root.focusFirstItem();
                        debounceTimer.restart();
                    }
                }

                model: ScriptModel {
                    id: resultModel
                    objectProp: "key"
                }

                // A scroll bar at last — this list had none, so a long result
                // set gave no sign that it continued past the bottom edge.
                //
                // The categories it already groups by (App, Action, Command,
                // Math, Web) become the landmarks, so the bar is a map of the
                // results and a drag snaps to the start of a category.
                ScrollBar.vertical: StyledScrollBar {
                    // Positions are computed rather than approximated from the
                    // index: a section header is 24px and a row is not, so
                    // index/count would put every landmark progressively
                    // further from its heading the further down the list it is.
                    markers: {
                        const vals = resultModel.values ?? [];
                        if (vals.length === 0) return [];
                        if (appResults.section.property === "") return [];

                        const range = appResults.contentHeight
                            - appResults.height + appResults.topMargin;
                        if (range <= 0) return [];

                        // Rows are uniform here, so the row height falls out of
                        // what the headers do not account for.
                        const headerH = 24;
                        let sections = 0;
                        let last = null;
                        for (const v of vals) {
                            const t = String(v?.type ?? "");
                            if (t !== last) { sections++; last = t; }
                        }
                        const rowH = (appResults.contentHeight
                            - sections * headerH
                            - appResults.topMargin - appResults.bottomMargin)
                            / vals.length;
                        if (!(rowH > 0)) return [];

                        const out = [];
                        let y = appResults.topMargin;
                        last = null;
                        for (const v of vals) {
                            const t = String(v?.type ?? "");
                            if (t !== last) {
                                out.push({
                                    at: Math.max(0, Math.min(1, y / range)),
                                    label: t,
                                    major: true
                                });
                                y += headerH;
                                last = t;
                            }
                            y += rowH;
                        }
                        return out;
                    }
                }

                delegate: SearchItem {
                    id: searchItem
                    // The selectable item for each search result
                    required property var modelData
                    anchors.left: parent?.left
                    anchors.right: parent?.right
                    entry: modelData
                    query: StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch])

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Tab) {
                            root.stepResult((event.modifiers & Qt.ShiftModifier) !== 0);
                            event.accepted = true;
                        }
                    }
                }
            }
        }
    }
}
