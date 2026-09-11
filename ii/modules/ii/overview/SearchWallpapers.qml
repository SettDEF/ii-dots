pragma ComponentBehavior: Bound

import QtQuick
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
    }
    Component.onCompleted: completeDebounce.restart()
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
            meta: WallpaperHub.focusedMeta
        }
    }

    // ── Filter / sort chips (the filter_list button in the bar) ───────
    // Same chips skwd draws in its own panel, same state (WallpaperHub) —
    // they just live here while the launcher is open.
    Item {
        id: filterPanel
        visible: WallpaperHub.filterOpen && WallpaperHub.source === "reddit"
        anchors { top: parent.top; left: parent.left; right: parent.right }
        implicitHeight: filterCol.implicitHeight + 12

        ColumnLayout {
            id: filterCol
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 6 }
            spacing: 6

            StyledText {
                text: Translation.tr("Sort")
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
                    model: WallpaperHub.sortChips
                    delegate: Rectangle {
                        id: sortChip
                        required property var modelData
                        readonly property bool on: WallpaperHub.forcedSort === modelData.id
                        implicitWidth: chipLabel.implicitWidth + 22
                        implicitHeight: 30
                        // Button-shaped, not a pill — squarer corners.
                        radius: Appearance.rounding.verysmall
                        color: sortChip.on
                            ? Appearance.m3colors.m3primary
                            : (chipHov.hovered ? Appearance.colors.colLayer2Hover
                                               : Appearance.colors.colLayer2Base)
                        border.width: sortChip.on ? 0 : 1
                        border.color: Appearance.colors.colLayer0Border
                        Behavior on color { ColorAnimation { duration: 140 } }
                        HoverHandler { id: chipHov }
                        TapHandler {
                            onTapped: {
                                // Hub first (so skwd's chips agree even if it
                                // isn't open yet), then ask skwd to re-sync.
                                WallpaperHub.forcedSort = sortChip.modelData.id;
                                WallpaperHub.sortPicked(sortChip.modelData.id);
                            }
                        }
                        StyledText {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: sortChip.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: sortChip.on
                                ? Appearance.m3colors.m3onPrimary
                                : Appearance.colors.colOnLayer1
                        }
                    }
                }
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
