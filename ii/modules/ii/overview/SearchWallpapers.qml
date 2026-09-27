pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// Launcher's skwd mode: a real subreddit autocomplete dropdown that only shows
// while the search input is focused. Picking a subreddit opens/updates the
// real skwd window (which sits BELOW this launcher in the z-order) — the
// wallpapers show there, full-size, not inside the launcher.
Item {
    id: root

    property string sub: "wallpapers"
    property bool inputFocused: false

    readonly property string homePath: FileUtils.trimFileProtocol(Directories.home)
    readonly property string scriptDir: `${homePath}/.config/quickshell/ii/scripts/colors`

    property var completions: []
    // Starts dismissed — see WallpaperHub.dropdownSuppressed.
    property bool dropdownDismissed: true

    // Collapse to nothing when neither the filter nor the subreddit dropdown
    // is showing, so the launcher is just the bar and skwd (below) is fully
    // visible. Otherwise: filter chips on top, subreddit list underneath.
    readonly property real filterHeight: filterPanel.visible ? filterPanel.implicitHeight + 8 : 0
    readonly property real detailsHeight: detailsPanel.visible ? detailsPanel.implicitHeight + 8 : 0
    readonly property real listHeight: ddList.visible
        ? Math.min(ddList.contentHeight + 8, 320 - root.filterHeight) : 0
    implicitHeight: root.filterHeight + root.detailsHeight + root.listHeight

    // No auto-highlight: Enter must open what you TYPED, not the first
    // completion. -1 = nothing highlighted.
    onCompletionsChanged: WallpaperHub.completionIndex = -1
    Connections {
        target: WallpaperHub
        function onSelectNext() {
            if (root.completions.length === 0) return;
            WallpaperHub.completionIndex = Math.min(WallpaperHub.completionIndex + 1, root.completions.length - 1);
        }
        function onSelectPrev() {
            if (root.completions.length === 0) return;
            WallpaperHub.completionIndex = Math.max(WallpaperHub.completionIndex - 1, 0);
        }
        function onSubmit() {
            const i = WallpaperHub.completionIndex;
            const name = (i >= 0 && i < root.completions.length) ? root.completions[i].name : root.sub;
            root.dropdownDismissed = true;
            root.openInSkwd(name);
        }
    }

    // Set when we rewrite the launcher's text ourselves, so the resulting
    // text change doesn't re-open the dropdown we just dismissed.
    property bool selfEdit: false

    function openInSkwd(name) {
        // Picking an entry writes it back into the search field, so the input
        // always shows the subreddit you actually opened.
        root.selfEdit = true;
        WallpaperHub.dropdownSuppressed = true;
        GlobalStates.requestLauncherSearch(`r/${name}`);
        const s = Persistent.states.skwd;
        if (s) {
            s.activeSource = "reddit";
            s.activeMediaType = WallpaperHub.mediaType;
            s.query = name;
            s.activeIndex = 0;
        }
        WallpaperHub.lastSub = name;       // remembered for reopen
        WallpaperHub.navigate(name);       // live-update if skwd already open
        GlobalStates.skwdWallOpen = true;  // launcher stays open (they coexist)
    }
    function formatSubs(n) {
        if (n >= 1000000) return (n / 1000000).toFixed(n >= 10000000 ? 0 : 1) + "M";
        if (n >= 1000)    return (n / 1000).toFixed(n >= 100000 ? 0 : 1) + "k";
        return String(n);
    }

    onSubChanged: {
        if (root.selfEdit) {
            // Our own rewrite after a pick — keep the dropdown closed.
            root.selfEdit = false;
            return;
        }
        root.dropdownDismissed = false;
        completeDebounce.restart();
        searchDebounce.restart();
    }
    Component.onCompleted: completeDebounce.restart()
    Timer {
        id: searchDebounce
        interval: 300
        onTriggered: if (WallpaperHub.source !== "reddit") WallpaperHub.search(root.sub)
    }
    Connections {
        target: WallpaperHub
        function onSourceChanged() { searchDebounce.restart() }
    }
    Timer {
        id: completeDebounce
        interval: 220
        onTriggered: {
            if (WallpaperHub.source !== "reddit" || root.sub.length < 2) { root.completions = []; return }
            if (completeProc.running) return;
            completeProc.command = ["bash", "-c",
                `'${root.scriptDir}/reddit_complete.sh' '${root.sub.replace(/'/g, "")}'`];
            completeProc.running = true;
        }
    }
    Process {
        id: completeProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.completions = text.trim().split("\n").filter(l => l.length > 0).map(l => {
                    const c = l.split("\t");
                    return { name: c[0] || "", nsfw: c[1] === "1", subs: parseInt(c[2] || "0", 10) };
                }).filter(r => r.name.length > 0);
            }
        }
    }

    Binding { target: WallpaperHub; property: "dropdownVisible"; value: ddList.visible }
    Binding { target: WallpaperHub; property: "detailsHeight"; value: detailsPanel.implicitHeight }

    // ── Image info + post (the info button in the bar) ───────────────
    // Same panel skwd draws beside its carousel, same state (WallpaperHub),
    // rendered here while the launcher is open — the arrangement the filter
    // chips below already use.
    Item {
        id: detailsPanel
        // Height-animated rather than a bare visible flip, so the launcher
        // grows into the space instead of the subreddit list jumping down.
        // visible follows the height so it stops consuming layout once shut.
        readonly property bool shown: WallpaperHub.detailsOpen
        visible: implicitHeight > 1
        clip: true
        anchors { top: parent.top; left: parent.left; right: parent.right }
        anchors.topMargin: root.filterHeight
        implicitHeight: detailsPanel.shown ? detailsInner.implicitHeight + 12 : 0
        Behavior on implicitHeight {
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }

        WallpaperDetailsPanel {
            id: detailsInner
            // Full width, like the completion list — the rows ARE the panel,
            // so a centred fixed-width block would look pasted on.
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.topMargin: 6
            opacity: detailsPanel.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            item: WallpaperHub.focusedItem
            theme: WallpaperHub.focusedTheme
            meta: WallpaperHub.focusedMeta
        }
    }

    // ── Filter chips (the filter_list button in the bar) ──────────────
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool on: false
        signal picked()
        implicitWidth: chipLabel.implicitWidth + 22
        implicitHeight: 30
        radius: Appearance.rounding.verysmall
        color: chip.on ? Appearance.m3colors.m3primary
            : (chipHov.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2Base)
        border.width: chip.on ? 0 : 1
        border.color: Appearance.colors.colLayer0Border
        Behavior on color { ColorAnimation { duration: 140 } }
        HoverHandler { id: chipHov }
        TapHandler { onTapped: chip.picked() }
        StyledText {
            id: chipLabel
            anchors.centerIn: parent
            text: chip.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: chip.on ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
        }
    }
    component ChipRow: ColumnLayout {
        id: chipRow
        property string title: ""
        property var options: []          // [{ label, value }]
        property var current
        signal picked(var value)
        Layout.fillWidth: true
        spacing: 4
        StyledText {
            text: chipRow.title
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            Layout.leftMargin: 12
        }
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            spacing: 5
            Repeater {
                model: chipRow.options
                delegate: Chip {
                    required property var modelData
                    label: modelData.label
                    on: chipRow.current === modelData.value
                    onPicked: chipRow.picked(modelData.value)
                }
            }
        }
    }

    Item {
        id: filterPanel
        readonly property bool reddit: WallpaperHub.source === "reddit" || WallpaperHub.source === "videos"
        readonly property bool wallhaven: WallpaperHub.source === "wallhaven"
        visible: WallpaperHub.filterOpen
        anchors { top: parent.top; left: parent.left; right: parent.right }
        implicitHeight: filterCol.implicitHeight + 12

        ColumnLayout {
            id: filterCol
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 6 }
            spacing: 8

            ChipRow {
                visible: filterPanel.reddit
                title: Translation.tr("Sort")
                options: WallpaperHub.sortChips.map(c => ({ label: c.label, value: c.id }))
                current: WallpaperHub.forcedSort
                onPicked: value => {
                    WallpaperHub.forcedSort = value;
                    WallpaperHub.sortPicked(value);
                }
            }
            ChipRow {
                visible: filterPanel.wallhaven
                title: Translation.tr("Content")
                options: [{ label: "SFW", value: true }, { label: Translation.tr("ALL"), value: false }]
                current: WallpaperHub.whSfw
                onPicked: value => WallpaperHub.setWh("whSfw", value)
            }
            ChipRow {
                visible: filterPanel.wallhaven
                title: Translation.tr("Ratio")
                options: [{ label: Translation.tr("ANY"), value: "" }, { label: "16:9", value: "16:9" },
                    { label: "16:10", value: "16:10" }, { label: "21:9", value: "21:9" }, { label: "9:16", value: "9:16" }]
                current: WallpaperHub.whRatio
                onPicked: value => WallpaperHub.setWh("whRatio", value)
            }
            ChipRow {
                visible: filterPanel.wallhaven
                title: Translation.tr("At least")
                options: [{ label: Translation.tr("ANY"), value: 0 }, { label: "FHD", value: 1920 },
                    { label: "QHD", value: 2560 }, { label: "4K", value: 3840 }]
                current: WallpaperHub.whMinWidth
                onPicked: value => WallpaperHub.setWh("whMinWidth", value)
            }
            ChipRow {
                visible: filterPanel.wallhaven
                title: Translation.tr("Sort")
                options: [{ label: Translation.tr("AUTO"), value: "" }, { label: Translation.tr("NEW"), value: "new" },
                    { label: Translation.tr("RANDOM"), value: "random" }, { label: Translation.tr("LARGE"), value: "large" },
                    { label: Translation.tr("WIDE"), value: "wide" }]
                current: WallpaperHub.whSort
                onPicked: value => WallpaperHub.setWh("whSort", value)
            }
            ChipRow {
                title: Translation.tr("Change wallpaper every")
                options: WallpaperRotation.intervals.map(m => ({
                    label: m === 0 ? Translation.tr("OFF") : m < 60 ? m + " MIN" : (m / 60) + " H", value: m }))
                current: WallpaperRotation.minutes
                onPicked: value => WallpaperRotation.setMinutes(value)
            }
            ChipRow {
                visible: WallpaperRotation.enabled
                title: Translation.tr("From")
                options: [{ label: Translation.tr("FAVOURITES"), value: "favorites" },
                    { label: Translation.tr("WALLPAPERS FOLDER"), value: "folder" }]
                current: WallpaperRotation.from
                onPicked: value => WallpaperRotation.setFrom(value)
            }
        }
    }

    // ── Subreddit dropdown (only while the input is focused) ──────────
    ListView {
        id: ddList
        anchors {
            // Stacks below whichever panels are open: chips, then details.
            top: detailsPanel.visible ? detailsPanel.bottom
                : (filterPanel.visible ? filterPanel.bottom : parent.top)
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        visible: root.inputFocused && !root.dropdownDismissed
                 && !WallpaperHub.dropdownSuppressed
                 && WallpaperHub.source === "reddit" && root.completions.length > 0
        clip: true
        model: root.completions
        boundsBehavior: Flickable.StopAtBounds
        spacing: 2
        ScrollBar.vertical: StyledScrollBar {}
        currentIndex: WallpaperHub.completionIndex
        // Keep the keyboard-selected row scrolled into view.
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        delegate: Rectangle {
            id: ddRow
            required property var modelData
            required property int index
            readonly property bool selected: index === WallpaperHub.completionIndex
            width: ddList.width
            height: 40
            radius: Appearance.rounding.small
            color: (selected || ddHov.hovered) ? Appearance.colors.colLayer2Hover : "transparent"
            // Hover highlights only — moving the keyboard selection here would
            // make Enter open whatever the pointer rests on.
            HoverHandler { id: ddHov }
            TapHandler { onTapped: { root.dropdownDismissed = true; root.openInSkwd(ddRow.modelData.name) } }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12; anchors.rightMargin: 12
                spacing: 10
                MaterialSymbol { text: "tag"; iconSize: 17; color: Appearance.colors.colSubtext; Layout.alignment: Qt.AlignVCenter }
                StyledText {
                    text: ddRow.modelData.name
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                }
                Rectangle {
                    visible: ddRow.modelData.nsfw
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: 18; implicitWidth: ddNsfw.implicitWidth + 12; radius: 5
                    color: Qt.alpha(Appearance.m3colors.m3error, 0.18)
                    StyledText { id: ddNsfw; anchors.centerIn: parent; text: "18+"; font.pixelSize: 10; font.weight: Font.Bold; color: Appearance.m3colors.m3error }
                }
                StyledText { text: root.formatSubs(ddRow.modelData.subs); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext; Layout.alignment: Qt.AlignVCenter }
                MaterialSymbol { text: "open_in_full"; iconSize: 15; color: Appearance.colors.colSubtext; Layout.alignment: Qt.AlignVCenter }
            }
        }
    }
}
