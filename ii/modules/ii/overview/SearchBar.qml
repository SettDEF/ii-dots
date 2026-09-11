pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

RowLayout {
    id: root
    spacing: 6
    property bool animateWidth: false
    property alias searchInput: searchInput
    property string searchingText

    // Sort & filter dropdown state. Owned by SearchWidget (which hosts the
    // dropdown); mirrored here so the toolbar button can show its toggled
    // state, and toggled back up via the signal.
    property bool sortSettingsOpen: false
    signal sortSettingsToggled()
    // Tab / Shift+Tab; the results list is owned by SearchWidget.
    signal tabNavigate(bool back)

    property bool suppressQuery: false

    // Shows the completion without re-running the search, selected so the next
    // keystroke replaces it.
    function previewText(t) {
        root.suppressQuery = true;
        searchInput.text = t;
        searchInput.select(0, t.length);
        root.suppressQuery = false;
    }

    // Sort mode for clipboard results — also exposed as a prefix `;sort=<mode>` or `;newest`/`;oldest`/`;size`.
    // Values: "newest" | "oldest" | "size".
    property string sortMode: "newest"
    onSortModeChanged: LauncherSearch.clipboardSort = sortMode
    readonly property var sortModes: [
        { id: "newest", label: qsTr("Newest"), icon: "schedule" },
        { id: "oldest", label: qsTr("Oldest"), icon: "history" },
        { id: "size",   label: qsTr("Size"),   icon: "data_usage" },
    ]

    // Detect inline sort hints in the search text (e.g. ";sort=oldest" or ";newest")
    onSearchingTextChanged: {
        const t = root.searchingText.toLowerCase();
        const prefix = (Config.options.search.prefix.clipboard || ";").toLowerCase();
        if (!t.startsWith(prefix)) return;
        const body = t.slice(prefix.length).trim();
        const m = body.match(/^(?:sort\s*[:=]\s*)?(newest|oldest|size)\b/);
        if (m && m[1] !== root.sortMode) root.sortMode = m[1];
    }

    function forceFocus() {
        searchInput.forceActiveFocus();
    }

    enum SearchPrefixType { Action, App, Clipboard, Emojis, Math, ShellCommand, WebSearch, Theme, DefaultSearch }

    // skwd wallpaper-hub mode — `/skwd …` or `r/…`. Shrinks the input and
    // swaps the launcher-specific buttons for skwd's source icons + colours.
    readonly property bool skwdMode: {
        const t = root.searchingText.toLowerCase();
        return t.startsWith("/skwd") || t.startsWith("r/");
    }

    property var searchPrefixType: {
        if (root.searchingText.startsWith(Config.options.search.prefix.action)) return SearchBar.SearchPrefixType.Action;
        if (root.searchingText.startsWith(Config.options.search.prefix.app)) return SearchBar.SearchPrefixType.App;
        if (root.searchingText.startsWith(Config.options.search.prefix.clipboard)) return SearchBar.SearchPrefixType.Clipboard;
        if (root.searchingText.startsWith(Config.options.search.prefix.emojis)) return SearchBar.SearchPrefixType.Emojis;
        if (root.searchingText.startsWith(Config.options.search.prefix.math)) return SearchBar.SearchPrefixType.Math;
        if (root.searchingText.startsWith(Config.options.search.prefix.shellCommand)) return SearchBar.SearchPrefixType.ShellCommand;
        if (root.searchingText.startsWith(Config.options.search.prefix.webSearch)) return SearchBar.SearchPrefixType.WebSearch;
        if (root.searchingText.startsWith(Config.options.search.prefix.theme)) return SearchBar.SearchPrefixType.Theme;
        return SearchBar.SearchPrefixType.DefaultSearch;
    }
    
    MaterialShapeWrappedMaterialSymbol {
        id: searchIcon
        Layout.alignment: Qt.AlignVCenter
        iconSize: Appearance.font.pixelSize.huge
        shape: {
            if (root.skwdMode) return MaterialShape.Shape.Sunny;
            switch(root.searchPrefixType) {
            case SearchBar.SearchPrefixType.Action: return MaterialShape.Shape.Pill;
            case SearchBar.SearchPrefixType.App: return MaterialShape.Shape.Clover4Leaf;
            case SearchBar.SearchPrefixType.Clipboard: return MaterialShape.Shape.Gem;
            case SearchBar.SearchPrefixType.Emojis: return MaterialShape.Shape.Sunny;
            case SearchBar.SearchPrefixType.Math: return MaterialShape.Shape.PuffyDiamond;
            case SearchBar.SearchPrefixType.ShellCommand: return MaterialShape.Shape.PixelCircle;
            case SearchBar.SearchPrefixType.WebSearch: return MaterialShape.Shape.SoftBurst;
            case SearchBar.SearchPrefixType.Theme: return MaterialShape.Shape.Sunny;
            default: return MaterialShape.Shape.Cookie7Sided;
            }
        }
        text: {
            if (root.skwdMode) return "wallpaper";
            switch (root.searchPrefixType) {
            case SearchBar.SearchPrefixType.Action: return "settings_suggest";
            case SearchBar.SearchPrefixType.App: return "apps";
            case SearchBar.SearchPrefixType.Clipboard: return "content_paste_search";
            case SearchBar.SearchPrefixType.Emojis: return "add_reaction";
            case SearchBar.SearchPrefixType.Math: return "calculate";
            case SearchBar.SearchPrefixType.ShellCommand: return "terminal";
            case SearchBar.SearchPrefixType.WebSearch: return "travel_explore";
            case SearchBar.SearchPrefixType.Theme: return "palette";
            case SearchBar.SearchPrefixType.DefaultSearch: return "search";
            default: return "search";
            }
        }

        /*
         * The icon is the launcher's own menu button.
         *
         * It already announces what the query will do — the shape and glyph
         * change with the prefix — so it is the obvious thing to reach for when
         * you want to change *how* searching behaves. Right-click opens the
         * settings dropdown, matching the rest of the shell, where right-click
         * on a thing opens that thing's menu; left-click does the same, because
         * an icon that visibly reacts to hover and does nothing when clicked
         * reads as broken.
         */
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: root.sortSettingsToggled()

            StyledToolTip {
                text: Translation.tr("Launcher settings")
            }
        }
    }

    // ── skwd controls ─────────────────────────────────────────────────
    // The exact same component skwd's own toolbar uses — one definition,
    // shared state (WallpaperHub), so both bars are the same bar.
    // Sources on the left of the input…
    WallpaperControls {
        id: skwdControls
        half: "left"
        Layout.alignment: Qt.AlignVCenter
        visible: root.skwdMode
    }

    // Keeps the input dead-centre in the bar. Everything skwd adds sits on
    // the left, which would shove the text field off to the right — so
    // whichever side is narrower is padded by the difference.
    readonly property real skwdLeftWidth: searchIcon.implicitWidth + root.spacing
        + (skwdControls.visible ? skwdControls.implicitWidth + root.spacing : 0)
    readonly property real skwdRightWidth:
        (skwdActions.visible ? skwdActions.implicitWidth + root.spacing : 0)
        + (hueSelector.visible ? hueSelector.implicitWidth + root.spacing : 0)

    // Breathing room on each side of the input.
    readonly property real skwdSpread: root.skwdMode ? 20 : 0
    // How far the input may be nudged toward the middle. The pickers are much
    // wider than the three action buttons, so fully centring the field would
    // mean a huge empty gap on the right — capped, the bar stays a bar.
    readonly property real skwdBalanceCap: 90

    Item {
        visible: root.skwdMode
        implicitHeight: 1
        implicitWidth: root.skwdSpread + Math.min(root.skwdBalanceCap,
            Math.max(0, root.skwdRightWidth - root.skwdLeftWidth))
    }

    ToolbarTextField { // Search box
        id: searchInput
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        implicitHeight: 40
        focus: GlobalStates.overviewOpen
        font.pixelSize: Appearance.font.pixelSize.small
        placeholderText: Translation.tr("Search, calculate or run")
        // In skwd mode the input shares the bar with the pickers and actions,
        // so it takes a fixed width — wide enough to read a full `r/subreddit`
        // and to fill the middle of the bar rather than leaving a gap.
        implicitWidth: root.skwdMode ? 330
            : (root.searchingText == "" ? Appearance.sizes.searchWidthCollapsed : Appearance.sizes.searchWidth)

        Behavior on implicitWidth {
            id: searchWidthBehavior
            enabled: root.animateWidth
            NumberAnimation {
                duration: 300
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }

        // Fires for USER input only (not programmatic text changes), which is
        // exactly when the subreddit dropdown should be allowed to open.
        onTextEdited: WallpaperHub.dropdownSuppressed = false

        onTextChanged: {
            // Fires for programmatic writes too, so Tab previews are guarded here.
            if (root.suppressQuery)
                return;
            let q = text;
            const prefix = Config.options.search.prefix.clipboard || ";";
            if (q.toLowerCase().startsWith(prefix.toLowerCase())) {
                const body = q.slice(prefix.length);
                const m = body.match(/^(?:sort\s*[:=]\s*)?(newest|latest|oldest|size)\s*/i);
                if (m) {
                    let mode = m[1].toLowerCase();
                    if (mode === "latest") mode = "newest";
                    root.sortMode = mode;
                    q = prefix + body.slice(m[0].length);
                }
            }
            LauncherSearch.query = q;
        }

        onAccepted: {
            if (root.skwdMode) {
                if (WallpaperHub.dropdownVisible) WallpaperHub.submit();  // pick a sub
                else WallpaperHub.applyFocused();                          // apply focused wallpaper
                return;
            }
            if (appResults.count > 0) {
                // The selected row, not row 0.
                const idx = Math.max(0, Math.min(appResults.currentIndex, appResults.count - 1));
                const item = appResults.itemAtIndex(idx) ?? appResults.itemAtIndex(0);
                if (item && item.clicked)
                    item.clicked();
            }
        }

        Keys.onPressed: event => {
            // skwd mode: ↓/↑/Tab move the subreddit dropdown selection;
            // ←/→ browse the open skwd carousel (it can't get the mouse wheel
            // from this window).
            if (root.skwdMode) {
                if (event.key === Qt.Key_Down || (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))) {
                    WallpaperHub.selectNext(); event.accepted = true; return;
                }
                if (event.key === Qt.Key_Up || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                    WallpaperHub.selectPrev(); event.accepted = true; return;
                }
                if (event.key === Qt.Key_Left)  { WallpaperHub.carouselStep(-1); event.accepted = true; return; }
                if (event.key === Qt.Key_Right) { WallpaperHub.carouselStep(1);  event.accepted = true; return; }
            }
            const widget = panelWindow.overviewWidget;
            if (widget != null && root.searchingText === "") {
                // Left/Right step workspaces, Tab/Up/Down cycle the window
                // selection. This has to live here: the search field holds
                // focus, so arrow keys never reach Overview's own handler.
                if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                    event.accepted = true;
                    GlobalFocusGrab.cancelRestore();
                    HyprDispatch.run(event.key === Qt.Key_Left ? "workspace r-1" : "workspace r+1");
                    return;
                }
                if ((event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)) || event.key === Qt.Key_Up) {
                    event.accepted = true;
                    if (widget.visibleWindows.length > 0) {
                        if (widget.keyboardSelectedIndex <= 0) {
                            widget.keyboardSelectedIndex = widget.visibleWindows.length - 1;
                        } else {
                            widget.keyboardSelectedIndex--;
                        }
                    }
                    return;
                }
                if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down) {
                    event.accepted = true;
                    if (widget.visibleWindows.length > 0) {
                        widget.keyboardSelectedIndex = (widget.keyboardSelectedIndex + 1) % widget.visibleWindows.length;
                    }
                    return;
                }
                if (widget.keyboardSelectedIndex >= 0) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        event.accepted = true;
                        const selectedToplevel = widget.visibleWindows[widget.keyboardSelectedIndex];
                        const address = `0x${selectedToplevel.HyprlandToplevel.address}`;
                        GlobalFocusGrab.cancelRestore();
                        GlobalStates.overviewOpen = false;
                        HyprDispatch.run("focuswindow address:" + address);
                        return;
                    }
                    if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                        event.accepted = true;
                        const selectedToplevel = widget.visibleWindows[widget.keyboardSelectedIndex];
                        const address = `0x${selectedToplevel.HyprlandToplevel.address}`;
                        HyprDispatch.run("closewindow address:" + address);
                        if (widget.keyboardSelectedIndex >= widget.visibleWindows.length - 1) {
                            widget.keyboardSelectedIndex = Math.max(-1, widget.visibleWindows.length - 2);
                        }
                        return;
                    }
                    if (event.key === Qt.Key_Escape) {
                        event.accepted = true;
                        widget.keyboardSelectedIndex = -1;
                        return;
                    }
                    // For any printable key, clear keyboard selection so typing registers normally in search input
                    if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 0x20) {
                        widget.keyboardSelectedIndex = -1;
                    }
                }
            }

            if (event.key === Qt.Key_Tab) {
                if (LauncherSearch.results.length === 0) return;
                root.tabNavigate((event.modifiers & Qt.ShiftModifier) !== 0);
                event.accepted = true;
            }
        }
    }

    // ── skwd colour columns (right of the input) ──────────────────────
    // Same component skwd's filter panel uses. Colour filtering is a
    // Wallhaven query parameter, so it's only offered for that source.
    // Mirror of the left-hand padding — this is the one that usually applies,
    // since the pickers are wider than the action buttons.
    Item {
        visible: root.skwdMode
        implicitHeight: 1
        implicitWidth: root.skwdSpread + Math.min(root.skwdBalanceCap,
            Math.max(0, root.skwdLeftWidth - root.skwdRightWidth))
    }

    // …media tabs + actions on the right, so the input sits between two
    // groups of roughly equal width.
    WallpaperControls {
        id: skwdActions
        half: "right"
        Layout.alignment: Qt.AlignVCenter
        visible: root.skwdMode
    }

    WallpaperHueSelector {
        id: hueSelector
        Layout.alignment: Qt.AlignVCenter
        Layout.rightMargin: 6
        visible: root.skwdMode && WallpaperHub.source === "wallhaven"
    }


    IconToolbarButton {
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        visible: !root.skwdMode
        onClicked: {
            GlobalStates.overviewOpen = false;
            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "search"]);
        }
        text: "image_search"
        StyledToolTip {
            text: Translation.tr("Google Lens")
        }
    }

    // Expanding sort button — only relevant in clipboard mode.
    Item {
        id: sortBtn
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        visible: root.searchPrefixType === SearchBar.SearchPrefixType.Clipboard
        property bool open: false
        readonly property int collapsedW: 36
        readonly property int expandedW: 36 + sortChipsRow.implicitWidth + 6
        implicitWidth: open ? expandedW : collapsedW
        implicitHeight: 36
        Behavior on implicitWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Rectangle {
            id: sortPill
            anchors.fill: parent
            radius: 18
            color: sortHov.hovered ? Appearance.colors.colSurfaceContainerHigh
                                   : ColorUtils.transparentize(Appearance.colors.colSurfaceContainerHigh, 0.5)
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            HoverHandler { id: sortHov }
            TapHandler { onTapped: sortBtn.open = !sortBtn.open }

            // Static "sort" icon on the left
            MaterialSymbol {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 9 }
                text: "sort"; iconSize: 18
                color: Appearance.colors.colOnSurfaceVariant
            }

            // Chip strip — clipped so the expansion is smooth.
            Item {
                anchors { left: parent.left; leftMargin: 36; right: parent.right; rightMargin: 6; top: parent.top; bottom: parent.bottom }
                clip: true
                opacity: sortBtn.open ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                Row {
                    id: sortChipsRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Repeater {
                        model: root.sortModes
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool active: root.sortMode === modelData.id
                            implicitWidth: chipText.implicitWidth + 22
                            implicitHeight: 26
                            radius: 13
                            color: active ? Appearance.colors.colPrimary
                                : (chipHov.hovered ? Appearance.colors.colSurfaceContainerHighest : "transparent")
                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                            HoverHandler { id: chipHov }
                            TapHandler {
                                onTapped: {
                                    root.sortMode = modelData.id
                                    sortBtn.open = false
                                }
                            }
                            Row {
                                anchors.centerIn: parent; spacing: 4
                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.icon; iconSize: 13
                                    color: parent.parent.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                                }
                                StyledText {
                                    id: chipText
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: parent.parent.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                                }
                            }
                        }
                    }
                }
            }
        }

    }

    // Launcher sort & filter. Separate button from the clipboard chip expander
    // above: that one flips a single clipboard ordering inline, this opens the
    // full ranking/visibility menu for app results, which is far too much to
    // fit in a chip strip.
    IconToolbarButton {
        id: launcherSortBtn
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        visible: !root.skwdMode
              && root.searchPrefixType !== SearchBar.SearchPrefixType.Clipboard
        text: "sort"
        toggled: root.sortSettingsOpen
        onClicked: root.sortSettingsToggled()

        StyledToolTip {
            text: Translation.tr("Sort & filter results")
        }
    }

    IconToolbarButton {
        id: songRecButton
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        Layout.rightMargin: 4
        visible: !root.skwdMode
        toggled: SongRec.running
        onClicked: SongRec.toggleRunning()
        text: "music_cast"

        StyledToolTip {
            text: Translation.tr("Recognize music")
        }

        colText: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
        background: MaterialShape {
            RotationAnimation on rotation {
                running: songRecButton.toggled
                duration: 12000
                easing.type: Easing.Linear
                loops: Animation.Infinite
                from: 0
                to: 360
            }
            shape: {
                if (songRecButton.down) {
                    return songRecButton.toggled ? MaterialShape.Shape.Circle : MaterialShape.Shape.Square
                } else {
                    return songRecButton.toggled ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Circle
                }
            }
            color: {
                if (songRecButton.toggled) {
                    return songRecButton.hovered ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary
                } else {
                    return songRecButton.hovered ? Appearance.colors.colSurfaceContainerHigh : ColorUtils.transparentize(Appearance.colors.colSurfaceContainerHigh)
                }
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }
}
