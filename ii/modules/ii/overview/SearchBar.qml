pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
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
        shape: switch(root.searchPrefixType) {
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
        text: switch (root.searchPrefixType) {
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
    ToolbarTextField { // Search box
        id: searchInput
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        implicitHeight: 40
        focus: GlobalStates.overviewOpen
        font.pixelSize: Appearance.font.pixelSize.small
        placeholderText: Translation.tr("Search, calculate or run")
        implicitWidth: root.searchingText == "" ? Appearance.sizes.searchWidthCollapsed : Appearance.sizes.searchWidth

        Behavior on implicitWidth {
            id: searchWidthBehavior
            enabled: root.animateWidth
            NumberAnimation {
                duration: 300
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }

        onTextChanged: {
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
            if (appResults.count > 0) {
                // Get the first visible delegate and trigger its click
                let firstItem = appResults.itemAtIndex(0);
                if (firstItem && firstItem.clicked) {
                    firstItem.clicked();
                }
            }
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Tab) {
                if (LauncherSearch.results.length === 0) return;
                const tabbedText = LauncherSearch.results[0].name;
                LauncherSearch.query = tabbedText;
                searchInput.text = tabbedText;
                event.accepted = true;
            }
        }
    }

    IconToolbarButton {
        Layout.topMargin: 4
        Layout.bottomMargin: 4
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

    IconToolbarButton {
        id: songRecButton
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        Layout.rightMargin: 4
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
