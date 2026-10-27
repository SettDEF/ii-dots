//@ pragma UseQApplication
//@ pragma AppId ii-settings
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF

ApplicationWindow {

    // browser-like scrolling for every list in the window (Momentum.qml)

    MomentumInjector { root: parent }
    id: root
    // The window opens narrow and then takes its real size; animating the
    // rail through that made the tab labels slide in on every open.
    property bool railReady: false
    Timer { running: true; interval: 500; onTriggered: root.railReady = true }
    property string firstRunFilePath: CF.FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property real contentPadding: 8
    /// The gap between the page list and the content pane, which holds the list's scrollbar.
    readonly property real railGutter: 25
    /// Ctrl+F: the header opens and the search takes the keyboard
    property bool searchWanted: false

    /// The window buttons' look, from ii-decor's config (its colours follow the wallpaper), so
    /// they match the other windows' exactly.
    property var decor: ({ size: 12, gap: 8, minimize: "#dbc762", maximize: "#79cb90", close: "#ffb4ab" })
    FileView {
        path: `${Quickshell.env("HOME")}/.config/hypr/ii-decor.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text());
                // "rgb(rrggbb)" / "rgba(rrggbbaa)" -> a QML colour
                const qml = s => {
                    const h = String(s ?? "").replace(/^rgba?\(|\)$/g, "");
                    return h.length === 8 ? `#${h.slice(6)}${h.slice(0, 6)}` : `#${h}`;
                };
                root.decor = {
                    size: j.buttonSize ?? 12,
                    gap: j.buttonGap ?? 8,
                    minimize: qml(j.colors?.minimize),
                    maximize: qml(j.colors?.maximize),
                    close: qml(j.colors?.close),
                };
            } catch (e) {}
        }
    }
    property bool showNextTime: false
    // each group its own hue (the theme's terminal colours, so they follow it): Setup, Look,
    // Behaviour, Machine
    function groupColor(i) {
        const hues = [Appearance.m3colors.term5, Appearance.m3colors.term4, Appearance.m3colors.term2, Appearance.m3colors.term3];
        let g = -1;
        for (let k = 0; k <= i && k < root.pages.length; k++) if (root.pages[k].group) g++;
        return hues[Math.max(0, g) % hues.length];
    }
    // `group` is the heading drawn ABOVE a page, so only the first page of each
    // group carries one. Ordered by how often each is needed.
    property var pages: [
        {
            group: Translation.tr("Setup"),
            name: Translation.tr("Quick"),
            icon: "instant_mix",
            component: "modules/settings/QuickConfig.qml"
        },
        {
            name: Translation.tr("System"),
            icon: "tune",
            component: "modules/settings/SystemConfig.qml"
        },
        {
            group: Translation.tr("Look"),
            name: Translation.tr("Bar"),
            icon: "toast",
            iconRotation: 180,
            component: "modules/settings/BarConfig.qml"
        },
        {
            name: Translation.tr("Background"),
            icon: "texture",
            component: "modules/settings/BackgroundConfig.qml"
        },
        {
            name: Translation.tr("Interface"),
            icon: "bottom_app_bar",
            component: "modules/settings/InterfaceConfig.qml"
        },
        {
            group: Translation.tr("Behaviour"),
            name: Translation.tr("General"),
            icon: "browse",
            component: "modules/settings/GeneralConfig.qml"
        },
        {
            name: Translation.tr("Pointer"),
            icon: "mouse",
            component: "modules/settings/PointerConfig.qml"
        },
        {
            name: Translation.tr("Services"),
            icon: "settings",
            component: "modules/settings/ServicesConfig.qml"
        },
        {
            group: Translation.tr("Machine"),
            name: Translation.tr("Performance"),
            icon: "speed",
            component: "modules/settings/PerformanceConfig.qml"
        },
        {
            name: Translation.tr("Advanced"),
            icon: "construction",
            component: "modules/settings/AdvancedConfig.qml"
        },
        {
            name: Translation.tr("About"),
            icon: "info",
            component: "modules/settings/About.qml"
        }
    ]
    property int currentPage: 0
    // A new page has different items; the old match list points at gone ones.
    onCurrentPageChanged: if (root.findQuery.length > 0) findDebounce.restart()


    // ── Find on page ────────────────────────────────────────────────────
    /// What is being highlighted, and where we are in it.
    property string findQuery: ""
    property var findMatches: []
    property int findIndex: 0
    readonly property int findCount: root.findMatches.length

    /// Every visible item carrying a short label. Invisible ones are skipped:
    /// a match you cannot see is one you cannot be scrolled to. Long ones are
    /// skipped too — highlighting a paragraph says nothing.
    function collectLabels(item, out) {
        if (!item || item.visible === false) return out;
        const t = item.text === undefined ? "" : String(item.text);
        if (t.length > 0 && t.length <= 60) out.push(item);
        const kids = item.children ?? [];
        for (let i = 0; i < kids.length; ++i) root.collectLabels(kids[i], out);
        return out;
    }

    function runFind(q) {
        root.findQuery = String(q ?? "").trim();
        root.findIndex = 0;
        root.findMatches = [];
        if (root.findQuery.length === 0) { root.pushMatchMarkers(); return; }
        findDebounce.restart();
    }

    function _rebuildFind() {
        const flick = pageLoader.item;
        if (!flick || root.findQuery.length === 0) { root.findMatches = []; return; }

        // The same matcher the index uses, or a query that fuzzy-matched its way
        // to this page finds nothing once it arrives.
        const prepared = root.collectLabels(flick, []).map(it =>
            ({ item: it, key: CF.Fuzzy.prepare(String(it.text)) }));
        const hits = CF.Fuzzy.go(root.findQuery, prepared, { all: false, key: "key" });

        // Document order, so next and previous run down the page rather than by
        // score.
        const items = hits.map(h => h.obj.item);
        items.sort((a, b) => a.mapToItem(flick.contentItem, 0, 0).y
                           - b.mapToItem(flick.contentItem, 0, 0).y);
        root.findMatches = items;
        root.pushMatchMarkers();
        if (items.length > 0) root.scrollToMatch(0);
    }

    /// Put the matches on the page's own scroll bar, so a hit off screen is
    /// still findable — the browser trick of ticking the gutter.
    function pushMatchMarkers() {
        const flick = pageLoader.item;
        if (!flick || flick.scrollMarkers === undefined) return;
        const span = flick.contentHeight;
        if (span <= 0 || root.findMatches.length === 0) {
            flick.scrollMarkers = [];
            return;
        }
        const out = [];
        for (let i = 0; i < root.findMatches.length; ++i) {
            const it = root.findMatches[i];
            if (!it) continue;
            out.push({
                at: Math.max(0, Math.min(1,
                    it.mapToItem(flick.contentItem, 0, 0).y / span)),
                label: String(it.text ?? ""),
                major: i === root.findIndex,
                color: i === root.findIndex ? Appearance.colors.colPrimary
                                            : Appearance.m3colors.m3tertiary
            });
        }
        flick.scrollMarkers = out;
    }

    function stepFind(delta) {
        if (root.findCount === 0) return;
        root.scrollToMatch((root.findIndex + delta + root.findCount) % root.findCount);
    }

    function scrollToMatch(i) {
        root.findIndex = i;
        Qt.callLater(root.pushMatchMarkers);
        const target = root.findMatches[i];
        const flick = pageLoader.item;
        if (!target || !flick) return;
        const pos = target.mapToItem(flick.contentItem, 0, 0);
        const maxY = Math.max(0, flick.contentHeight - flick.height);
        // A third down rather than flush to the top, so the match has context
        // above it.
        findScroll.to = Math.max(0, Math.min(pos.y - flick.height / 3, maxY));
        findScroll.target = flick;
        findScroll.restart();
    }

    Timer {
        id: findDebounce
        interval: 200          // let the page finish laying out before measuring
        onTriggered: root._rebuildFind()
    }

    NumberAnimation {
        id: findScroll
        property: "contentY"
        duration: 220
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
    }

    /// Typing goes straight to the best match: switch page if it is elsewhere,
    /// then highlight every similar label on it.
    function runSearch(text) {
        const q = String(text ?? "").trim();
        if (q.length === 0) { root.runFind(""); return; }
        const hit = (SettingsIndex.search(q, 1) ?? [])[0];
        const page = hit ? SettingsIndex.pageIndexOf(hit) : -1;
        if (page >= 0 && page !== root.currentPage) root.currentPage = page;
        root.runFind(q);
    }

    Timer {
        id: searchDebounce
        interval: 260          // a page switch per keystroke is unreadable
        onTriggered: root.runSearch(searchField.text)
    }

    visible: true
    onClosing: Qt.quit()
    title: "illogical-impulse Settings"

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Config.readWriteDelay = 0 // Settings app always only sets one var at a time so delay isn't needed
        // Search maps an indexed row back to a page; derive it from the page
        // list above rather than hardcoding the mapping a second time.
        const map = ({});
        for (let i = 0; i < root.pages.length; ++i)
            map[String(root.pages[i].component).split("/").pop()] = i;
        SettingsIndex.pageForFile = map;
    }

    minimumWidth: 750
    minimumHeight: 500
    width: 1100
    height: 750
    color: Appearance.m3colors.m3background

    ColumnLayout {
        anchors {
            fill: parent
            margins: contentPadding
        }

        Keys.onPressed: (event) => {
            if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_F) {
                    root.searchWanted = true;
                    Qt.callLater(() => searchField.inputItem.forceActiveFocus());
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_PageDown) {
                    root.currentPage = Math.min(root.currentPage + 1, root.pages.length - 1)
                    event.accepted = true;
                } 
                else if (event.key === Qt.Key_PageUp) {
                    root.currentPage = Math.max(root.currentPage - 1, 0)
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_Tab) {
                    root.currentPage = (root.currentPage + 1) % root.pages.length;
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_Backtab) {
                    root.currentPage = (root.currentPage - 1 + root.pages.length) % root.pages.length;
                    event.accepted = true;
                }
            }
        }

        Item { // Titlebar
            // Above the content pane, which is a LATER sibling in this column
            // and so paints over this whole subtree. The search results hang
            // below the box, outside the titlebar's own bounds, and were being
            // covered — z inside searchWrapper cannot reach across parents.
            id: titlebar
            z: 600
            visible: Config.options?.windows.showTitlebar
            Layout.fillWidth: true
            Layout.fillHeight: false
            // Collapsed to a thin strip until the pointer comes over it; it stays open while
            // the search is in use (focus, text, a find running).
            readonly property real fullHeight: Math.max(titleText.implicitHeight, windowControlsRow.implicitHeight)
            readonly property bool open: titleHover.hovered || collapseDelay.running
                || root.searchWanted || searchField.activeFocus || searchField.text.length > 0 || root.findQuery.length > 0
            implicitHeight: open ? fullHeight : 10
            Behavior on implicitHeight {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            HoverHandler { id: titleHover }
            // Drag the window by its header. This sits behind everything else in the bar, so only
            // the empty parts move the window; the buttons and the search box keep their clicks.
            Item {
                anchors.fill: parent
                z: -1
                DragHandler {
                    target: null
                    acceptedButtons: Qt.LeftButton
                    onActiveChanged: if (active) root.startSystemMove()
                }
            }
            Timer {
                // a short grace before closing, so passing over the edge does not flicker
                id: collapseDelay
                interval: 350
            }
            Connections {
                target: titleHover
                function onHoveredChanged() { if (!titleHover.hovered) collapseDelay.restart() }
            }
            // its contents fade with it, and take no clicks while hidden
            property real contentOpacity: open ? 1 : 0
            Behavior on contentOpacity { NumberAnimation { duration: 140 } }
            // a hint where it is while collapsed: a short handle in the middle
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 3
                width: 36
                height: 4
                radius: 2
                color: Appearance.colors.colSubtext
                opacity: (1 - titlebar.contentOpacity) * 0.5
            }
            // Rail toggle and the config-file shortcut, in the header rather
            // than stacked above the page list.
            Row {
                id: headerActions
                opacity: titlebar.contentOpacity
                enabled: titlebar.open
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                // Lines the first icon up with the page-list icons below: the
                // rail sits 5px inside this bar, and a rail button centres its
                // icon 28px in, against 20px for these 40px buttons.
                anchors.leftMargin: 5 + 28 - 20
                spacing: 2

                NavigationRailExpandButton {
                    anchors.verticalCenter: parent.verticalCenter
                    Layout.leftMargin: 0
                    rail: navRail
                    focus: root.visible
                }

                RippleButton {
                    id: configButton
                    property bool justCopied: false

                    anchors.verticalCenter: parent.verticalCenter
                    // Same box and same glyph size as the rail toggle beside it.
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full

                    onClicked: Qt.openUrlExternally(
                        `${Directories.config}/illogical-impulse/config.json`)
                    altAction: () => {
                        Quickshell.clipboardText = CF.FileUtils.trimFileProtocol(
                            `${Directories.config}/illogical-impulse/config.json`);
                        configButton.justCopied = true;
                        revertTextTimer.restart();
                    }

                    contentItem: MaterialSymbol {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: configButton.justCopied ? "check" : "edit_document"
                        iconSize: 24
                        color: Appearance.colors.colOnLayer0
                    }

                    Timer {
                        id: revertTextTimer
                        interval: 1500
                        onTriggered: configButton.justCopied = false
                    }
                    StyledToolTip {
                        text: configButton.justCopied
                            ? Translation.tr("Path copied")
                            : Translation.tr("Open the config file\nRight-click to copy its path")
                    }
                }
            }

            StyledText {
                id: titleText
                opacity: titlebar.contentOpacity
                anchors {
                    left: Config.options.windows.centerTitle ? undefined : headerActions.right
                    horizontalCenter: Config.options.windows.centerTitle ? parent.horizontalCenter : undefined
                    verticalCenter: parent.verticalCenter
                    leftMargin: 10
                }
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("Settings")
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    variableAxes: Appearance.font.variableAxes.title
                }
            }
            // ── Search over every setting ───────────────────────────
            // Find controls: the counter and the two steppers, shown only once
            // a find is running. Left of the box, like a browser's.
            Row {
                id: findBar
                opacity: titlebar.contentOpacity
                visible: root.findQuery.length > 0
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: searchWrapper.left
                anchors.rightMargin: 6
                spacing: 2

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    rightPadding: 4
                    text: root.findCount > 0
                        ? `${root.findIndex + 1}/${root.findCount}`
                        : Translation.tr("none")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.numbers
                    color: root.findCount > 0 ? Appearance.colors.colOnLayer0
                                              : Appearance.colors.colSubtext
                }

                component FindStep: RippleButton {
                    property string glyph: ""
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.full
                    enabled: root.findCount > 0
                    contentItem: MaterialSymbol {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: glyph
                        iconSize: 18
                        color: enabled ? Appearance.colors.colOnLayer0
                                       : Appearance.colors.colSubtext
                    }
                }

                FindStep {
                    glyph: "keyboard_arrow_up"
                    onClicked: root.stepFind(-1)
                    StyledToolTip { text: Translation.tr("Previous match (Shift+Enter)") }
                }
                FindStep {
                    glyph: "keyboard_arrow_down"
                    onClicked: root.stepFind(1)
                    StyledToolTip { text: Translation.tr("Next match (Enter)") }
                }
                FindStep {
                    glyph: "close"
                    enabled: true
                    onClicked: { root.runFind(""); searchField.text = "" }
                    StyledToolTip { text: Translation.tr("Stop finding (Esc)") }
                }
            }

            Item {
                id: searchWrapper
                opacity: titlebar.contentOpacity
                enabled: titlebar.open
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: windowControlsRow.left
                anchors.rightMargin: 8
                implicitWidth: 230
                implicitHeight: 34

                // Enter steps forward, Shift+Enter back, Esc stops — the keys a
                // browser's find bar answers to.
                Keys.onPressed: event => {
                    if (root.findQuery.length === 0) return;
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.stepFind((event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        root.runFind(""); searchField.text = "";
                        event.accepted = true;
                    }
                }

                PillTextField {
                    id: searchField
                    // Re-read pages, packs and shaders when you start typing —
                    // FolderListModel does not watch directories, so without
                    // this a newly added effect would be missing from search.
                    onActiveFocusChanged: {
                        if (activeFocus) SettingsIndex.refresh();
                        else root.searchWanted = false;
                    }
                    onTextChanged: searchDebounce.restart()
                    anchors.fill: parent
                    placeholderText: Translation.tr("Search settings…")
                    leadingIcon: "search"
                    onCleared: searchField.inputItem.forceActiveFocus()
                }

            }

            // The window's buttons as ii-decor draws them elsewhere, but here in the header: in the
            // middle of the collapsed strip, and moving with it as it opens. (The plugin leaves this
            // window alone: ii-decor.json lists ^ii-settings$.) The plugin has no bar for it, so the
            // buttons do what its buttons do: minimise asks Wayland (the plugin sends any window's
            // own minimise where its button would), maximise toggles, close closes.
            Row {
                id: windowControlsRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 6
                spacing: root.decor.gap
                Repeater {
                    model: ["minimize", "maximize", "close"]
                    delegate: Rectangle {
                        id: decorButton
                        required property string modelData
                        width: root.decor.size
                        height: width
                        radius: width / 2
                        color: buttonHover.hovered ? Qt.darker(root.decor[modelData], 1.25) : root.decor[modelData]
                        Behavior on color { ColorAnimation { duration: 120 } }
                        HoverHandler { id: buttonHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                if (decorButton.modelData === "close")
                                    root.close();
                                else if (decorButton.modelData === "minimize")
                                    decorButton.Window.window.showMinimized();
                                else
                                    Quickshell.execDetached(["hyprctl", "eval", `hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized" }))`]);
                            }
                        }
                    }
                }
            }
        }

        RowLayout { // Window content with navigation rail and content pane
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: contentPadding
            Item {
                id: navRailWrapper
                Layout.fillHeight: true
                Layout.margins: 5
                // room for the list's scrollbar, with space on both sides of it
                Layout.rightMargin: root.railGutter - root.contentPadding
                // 56 is NavigationRailButton.baseSize — the collapsed rail is
                // one button wide.
                implicitWidth: navRail.expanded ? 196 : 56
                Behavior on implicitWidth {
                    enabled: root.railReady
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                NavigationRail { // Window content with navigation rail and content pane
                    id: navRail
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                    }
                    spacing: 10
                    expanded: root.width > 900
                    
                    // Scrollable: eleven pages plus four headings is ~840px
                    // against a ~690px content area.
                    // A sibling, not an attached bar: attached lives inside the
                    // flickable and pushes the entries aside. Out here it sits
                    // in the gap that was already there.
                    // Edge fades instead of a hard clip: a strip in the window
                    // colour over each edge, shown only where more entries exist.
                    // Overlays, not a layer mask: the mask version hid the list.
                    Repeater {
                        model: [true, false]   // top, bottom
                        delegate: Rectangle {
                            required property bool modelData
                            readonly property bool isTop: modelData
                            parent: navRailWrapper
                            z: 2
                            x: navRail.x + railFlick.x
                            width: railFlick.width
                            height: 28
                            y: isTop ? navRail.y + railFlick.y
                                     : navRail.y + railFlick.y + railFlick.height - height
                            visible: railFlick.interactive
                            opacity: (isTop ? !railFlick.atYBeginning : !railFlick.atYEnd) ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                            gradient: Gradient {
                                GradientStop { position: 0; color: isTop ? root.color : "transparent" }
                                GradientStop { position: 1; color: isTop ? "transparent" : root.color }
                            }
                        }
                    }
                    StyledScrollBar {
                        id: railScroll

                        // navRailWrapper, not navRail: the rail is a
                        // ColumnLayout and anchors inside one are undefined.
                        parent: navRailWrapper
                        flickable: railFlick
                        alwaysVisible: true
                        orientation: Qt.Vertical
                        hitWidth: 14

                        // Centred in the gap between the rail and the content pane; from the
                        // first heading's line down to the pane's bottom (the wrapper stops
                        // 5px short of it), with no padding at the ends of the track.
                        x: navRailWrapper.width + (root.railGutter - hitWidth) / 2
                        y: navRail.y + railFlick.y
                        height: navRailWrapper.height + 5 - y
                        topPadding: 0
                        bottomPadding: 0

                        size: railFlick.height / Math.max(1, railFlick.contentHeight)
                        position: railFlick.contentY / Math.max(1, railFlick.contentHeight)
                        onPositionChanged: if (pressed)
                            railFlick.contentY = position * railFlick.contentHeight

                        // Always there when the list overflows, but plain: no marker dots
                        // (a dot per entry beside a list you can read only repeated it).
                        policy: railFlick.contentHeight > railFlick.height + 2
                            ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                        currentMarker: root.currentPage
                        onMarkerActivated: index => root.currentPage = index

                        /// Scroll the current entry into view, if it is not.
                        function revealCurrent() {
                            const b = (railFlick.navContent.buttons ?? [])[root.currentPage];
                            const span = railFlick.contentHeight;
                            if (!b || span <= 0) return;
                            if (b.y < railFlick.contentY)
                                railScroll.snapAnimTo(Math.max(0, b.y / span));
                            else if (b.y + b.height > railFlick.contentY + railFlick.height)
                                railScroll.snapAnimTo(Math.max(0,
                                    (b.y + b.height - railFlick.height) / span));
                        }

                        /// Landmarks come from the buttons: only they know what a
                        /// group heading measured.
                        function rebuildMap() { railScroll.markers = [] }

                        // Coalesced: expanding the rail moves every button at once.
                        Timer {
                            id: mapRebuild
                            interval: 80
                            onTriggered: railScroll.rebuildMap()
                        }
                        Component.onCompleted: railScroll.rebuildMap()
                        Connections {
                            target: railFlick
                            function onContentHeightChanged() { mapRebuild.restart() }
                            function onHeightChanged() { mapRebuild.restart() }
                        }
                        Connections {
                            target: navRail
                            function onExpandedChanged() { mapRebuild.restart() }
                        }
                        Connections {
                            target: root
                            function onCurrentPageChanged() { railScroll.revealCurrent() }
                        }
                    }

                    StyledFlickable {
                        id: railFlick
                        // Wide window: the desktop-style list. Narrow: the icon rail.
                        readonly property Item navContent: navRail.expanded ? sideNav : railTabs
                        showScrollBar: false      // railScroll is its bar
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        implicitWidth: navContent.implicitWidth
                        contentHeight: railFlick.navContent.implicitHeight + railTail
                        // Scroll padding: just enough space after the last entry that
                        // the end position starts exactly at an entry, so scrolled to the
                        // bottom the top entry is whole instead of cut in half.
                        readonly property real railTail: {
                            const over = railFlick.navContent.implicitHeight - height;
                            if (over <= 0) return 0;
                            let next = railFlick.navContent.implicitHeight;
                            for (const b of (railFlick.navContent.buttons ?? []))
                                if (b.y >= over && b.y < next) next = b.y;
                            return next - over;
                        }
                        contentWidth: width
                        // Only actually scrolls when it has to.
                        interactive: contentHeight > height
                        clip: true

                        // ── Website-style scrolling ─────────────────────────
                        // Scroll snapping (CSS scroll-snap: proximity): once the
                        // scroll settles, glide to the nearest entry so none is
                        // left cut in half at the edge.
                        onContentYChanged: railSnap.restart()
                        onMovementEnded: railSnap.restart()
                        Timer {
                            id: railSnap
                            interval: 160
                            onTriggered: {
                                if (railFlick.moving || railFlick.dragging || !railFlick.interactive) return;
                                const max = railFlick.contentHeight - railFlick.height;
                                const y = railFlick.contentY;
                                if (y <= 0 || y >= max - 1) return;
                                let best = 0;
                                for (const b of (railFlick.navContent.buttons ?? []))
                                    if (Math.abs(b.y - y) < Math.abs(best - y)) best = b.y;
                                best = Math.max(0, Math.min(max, best));
                                if (Math.abs(best - y) >= 1)
                                    railScroll.snapAnimTo(best / railFlick.contentHeight);
                            }
                        }

                        SideNavList {
                            id: sideNav
                            visible: navRail.expanded
                            width: parent.width
                            model: root.pages
                            currentIndex: root.currentPage
                            onSelected: index => root.currentPage = index
                            animate: root.railReady
                        }
                        NavigationRailTabArray {
                            id: railTabs
                            visible: !navRail.expanded
                            width: parent.width
                            currentIndex: root.currentPage
                            animate: root.railReady
                            expanded: navRail.expanded
                            Repeater {
                                model: root.pages
                                NavigationRailButton {
                                    required property var index
                                    required property var modelData
                                    toggled: root.currentPage === index
                                    onPressed: root.currentPage = index;
                                    expanded: navRail.expanded
                                    animateExpand: root.railReady
                                    buttonIcon: modelData.icon
                                    iconColor: root.groupColor(index)
                                    buttonIconRotation: modelData.iconRotation || 0
                                    buttonText: modelData.name
                                    groupLabel: modelData.group ?? ""
                                    showToggledHighlight: false
                                }
                            }
                        }
                        }

                }
            }
            Rectangle { // Content container
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - root.contentPadding

                Rectangle {
                }

                // Find-on-page highlights, over the content like a browser's.
                // Positions are read from the items every frame the page can
                // move, because a Flickable does not tell anyone when it has.
                Repeater {
                    model: root.findMatches
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool isCurrent: index === root.findIndex

                        z: 399
                        radius: Appearance.rounding.verysmall
                        color: isCurrent ? Appearance.colors.colPrimary
                                         : Appearance.m3colors.m3tertiary
                        opacity: visible ? (isCurrent ? 0.42 : 0.2) : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                        Behavior on color { ColorAnimation { duration: 120 } }

                        // Recomputed off contentY so the box follows its item
                        // while the page scrolls.
                        readonly property var box: {
                            void (pageLoader.item?.contentY ?? 0);
                            void root.findIndex;
                            const it = modelData;
                            if (!it || !it.visible || !pageLoader.item) return null;
                            const p = it.mapToItem(pageLoader, 0, 0);
                            return { x: p.x, y: p.y, w: it.width, h: it.height };
                        }
                        visible: !!box && box.y > -40
                            && box.y < pageLoader.height + 40
                        x: (box?.x ?? 0) - 4
                        y: (box?.y ?? 0) - 2
                        width: (box?.w ?? 0) + 8
                        height: (box?.h ?? 0) + 4
                    }
                }

                Loader {
                    id: pageLoader
                    anchors.fill: parent
                    opacity: 1.0


                    active: Config.ready
                    Component.onCompleted: {
                        source = root.pages[0].component
                    }

                    Connections {
                        target: root
                        function onCurrentPageChanged() {
                            switchAnim.complete();
                            switchAnim.start();
                        }
                    }

                    SequentialAnimation {
                        id: switchAnim

                        NumberAnimation {
                            target: pageLoader
                            properties: "opacity"
                            from: 1
                            to: 0
                            duration: 100
                            easing.type: Appearance.animation.elementMoveExit.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedFirstHalf
                        }
                        ParallelAnimation {
                            PropertyAction {
                                target: pageLoader
                                property: "source"
                                value: root.pages[root.currentPage].component
                            }
                            PropertyAction {
                                target: pageLoader
                                property: "anchors.topMargin"
                                value: 20
                            }
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                target: pageLoader
                                properties: "opacity"
                                from: 0
                                to: 1
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                            NumberAnimation {
                                target: pageLoader
                                properties: "anchors.topMargin"
                                to: 0
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                        }
                    }
                }
            }
        }
    }
}
