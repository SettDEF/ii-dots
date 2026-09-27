// Sort & filter settings for launcher results.
//
// Lives INSIDE the search panel as a dropdown, above the result list — the same
// pattern SearchThemes and SearchWallpapers use, so it shares the launcher's
// surface, rounding and open/close animation instead of floating on top of it.
//
// Unlike those two it does NOT replace the results: the list stays visible
// below, so flipping a sort mode visibly re-orders real entries instead of
// making you close the panel to find out what it did.
//
// (It was first built as its own PopupWindow. That worked, but it read as a
// detached context menu rather than part of the launcher, which is not what
// this UI wants.)
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    signal requestClose()

    readonly property var opts: Config.options.launcher

    // Capped low on purpose: the result list stays visible BELOW this panel so
    // you can watch the ordering change as you flip a setting. Leaving room for
    // that matters more than showing every control at once — the rest scrolls.
    implicitHeight: Math.min(contentCol.implicitHeight + 20, 300)

    StyledFlickable {
        id: flick
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 6
        anchors.bottomMargin: 10
        contentHeight: contentCol.implicitHeight
        clip: true
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: contentCol
            width: flick.width
            spacing: 4

            // ── Sort ─────────────────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Sort results by") }

            ConfigSelectionArray {
                Layout.fillWidth: true
                currentValue: root.opts.sortMode
                onSelected: newValue => root.opts.sortMode = newValue
                options: LauncherRanking.sortModes.map(m => ({
                    displayName: m.label, icon: m.icon, value: m.id
                }))
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                Layout.bottomMargin: 2
                text: (LauncherRanking.sortModes.find(m => m.id === root.opts.sortMode)?.hint) ?? ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }

            ConfigSwitch {
                buttonIcon: "swap_vert"
                text: Translation.tr("Reverse order")
                checked: root.opts.reverseSort
                onCheckedChanged: root.opts.reverseSort = checked
            }

            ConfigSwitch {
                buttonIcon: "low_priority"
                text: Translation.tr("Prioritised entries float to top")
                checked: root.opts.usePriorityBoost
                onCheckedChanged: root.opts.usePriorityBoost = checked
            }

            // Only meaningful for the decayed mode.
            ConfigSpinBox {
                visible: root.opts.sortMode === "frecency"
                icon: "hourglass_bottom"
                text: Translation.tr("Halve a launch's weight after (days)")
                value: root.opts.frecencyHalfLife
                from: 1
                to: 365
                stepSize: 1
                onValueChanged: root.opts.frecencyHalfLife = value
            }

            // ── Entries ──────────────────────────────────────────────────
            ContentSubsectionLabel {
                Layout.topMargin: 8
                text: Translation.tr("Which entries appear")
            }

            ConfigSwitch {
                buttonIcon: "visibility_off"
                text: Translation.tr("Show hidden entries")
                checked: root.opts.showHidden
                onCheckedChanged: root.opts.showHidden = checked
            }

            ConfigSwitch {
                buttonIcon: "terminal"
                text: Translation.tr("Show terminal apps")
                checked: root.opts.showTerminalApps
                onCheckedChanged: root.opts.showTerminalApps = checked
            }

            ConfigSwitch {
                buttonIcon: "list_alt"
                text: Translation.tr("Show app shortcut actions")
                checked: root.opts.showDesktopActions
                onCheckedChanged: root.opts.showDesktopActions = checked
            }

            ConfigSpinBox {
                icon: "format_list_numbered"
                text: Translation.tr("Maximum results")
                value: root.opts.maxResults
                from: 3
                to: 60
                stepSize: 1
                onValueChanged: root.opts.maxResults = value
            }

            // ── Row appearance ───────────────────────────────────────────
            ContentSubsectionLabel {
                Layout.topMargin: 8
                text: Translation.tr("Row appearance")
            }

            ConfigSwitch {
                buttonIcon: "tag"
                text: Translation.tr("Show launch counts")
                checked: root.opts.showLaunchCounts
                onCheckedChanged: root.opts.showLaunchCounts = checked
            }

            ConfigSwitch {
                buttonIcon: "notes"
                text: Translation.tr("Show descriptions")
                checked: root.opts.showDescriptions
                onCheckedChanged: root.opts.showDescriptions = checked
            }

            ConfigSwitch {
                buttonIcon: "density_small"
                text: Translation.tr("Compact rows")
                checked: root.opts.compactRows
                onCheckedChanged: root.opts.compactRows = checked
            }

            // ── Searching ────────────────────────────────────────────────
            // Everything above decides how results are *ordered*; this decides
            // what gets searched in the first place. The prefixes are shown
            // rather than made editable — they are single characters wired into
            // Config, and a settings panel is the wrong place to discover you
            // have bound "/" to two things.
            ContentSubsectionLabel {
                Layout.topMargin: 8
                text: Translation.tr("Searching")
            }

            ConfigSwitch {
                buttonIcon: "bolt"
                text: Translation.tr("Show actions without typing a prefix")
                checked: Config.options.search.prefix.showDefaultActionsWithoutPrefix
                onCheckedChanged: Config.options.search.prefix.showDefaultActionsWithoutPrefix = checked
            }

            ConfigSwitch {
                buttonIcon: "spellcheck"
                // "Sloppy" in Config; the name says how it behaves rather than
                // what the flag is called.
                text: Translation.tr("Match loosely (typo-tolerant)")
                checked: Config.options.search.sloppy
                onCheckedChanged: Config.options.search.sloppy = checked
            }

            ConfigSpinBox {
                icon: "timer"
                text: Translation.tr("Wait before searching the slow sources (ms)")
                // Web, files and math each cost a round trip or a process; this
                // is what stops every keystroke starting one.
                value: Config.options.search.nonAppResultDelay
                from: 0
                to: 500
                stepSize: 10
                onValueChanged: Config.options.search.nonAppResultDelay = value
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                Layout.topMargin: 2
                text: Translation.tr("Prefixes — apps %1 · run %2 · web %3 · maths %4 · clipboard %5 · emoji %6 · actions %7 · themes %8")
                    .arg(Config.options.search.prefix.app)
                    .arg(Config.options.search.prefix.shellCommand)
                    .arg(Config.options.search.prefix.webSearch)
                    .arg(Config.options.search.prefix.math)
                    .arg(Config.options.search.prefix.clipboard)
                    .arg(Config.options.search.prefix.emojis)
                    .arg(Config.options.search.prefix.action)
                    .arg(Config.options.search.prefix.theme)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }

            // ── Web search ───────────────────────────────────────────────
            ContentSubsectionLabel {
                Layout.topMargin: 8
                text: Translation.tr("Web search")
            }

            ConfigSelectionArray {
                Layout.fillWidth: true
                currentValue: Config.options.search.engineBaseUrl
                onSelected: newValue => Config.options.search.engineBaseUrl = newValue
                options: [
                    { displayName: Translation.tr("Google"), value: "https://www.google.com/search?q=" },
                    { displayName: Translation.tr("DuckDuckGo"), value: "https://duckduckgo.com/?q=" },
                    { displayName: Translation.tr("Brave"), value: "https://search.brave.com/search?q=" },
                    { displayName: Translation.tr("Kagi"), value: "https://kagi.com/search?q=" },
                    { displayName: Translation.tr("Wikipedia"), value: "https://en.wikipedia.org/w/index.php?search=" },
                ]
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                visible: (Config.options.search.excludedSites?.length ?? 0) > 0
                text: Translation.tr("Excluding %1").arg((Config.options.search.excludedSites ?? []).join(", "))
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }

            // ── Usage data ───────────────────────────────────────────────
            ContentSubsectionLabel {
                Layout.topMargin: 8
                text: Translation.tr("Usage data")
            }

            ConfigSwitch {
                buttonIcon: "insights"
                text: Translation.tr("Count launches")
                checked: root.opts.trackUsage
                onCheckedChanged: root.opts.trackUsage = checked
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                text: {
                    LauncherRanking.revision   // re-read after a mutation
                    return Translation.tr("%1 tracked · %2 prioritised · %3 hidden")
                        .arg(Object.keys(LauncherRanking.launches).length)
                        .arg(root.opts.priorityApps.length)
                        .arg(root.opts.hiddenApps.length)
                }
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 6

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    materialIcon: "low_priority"
                    mainText: Translation.tr("Clear priorities")
                    enabled: root.opts.priorityApps.length > 0
                    onClicked: LauncherRanking.clearPriorities()
                }
                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    materialIcon: "visibility"
                    mainText: Translation.tr("Unhide all")
                    enabled: root.opts.hiddenApps.length > 0
                    onClicked: LauncherRanking.clearHidden()
                }
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                Layout.bottomMargin: 4
                materialIcon: "delete_history"
                mainText: Translation.tr("Reset all launch counts")
                colBackground: ColorUtils.transparentize(Appearance.m3colors.m3error, 0.84)
                onClicked: LauncherRanking.resetAll()
            }
        }
    }
}
