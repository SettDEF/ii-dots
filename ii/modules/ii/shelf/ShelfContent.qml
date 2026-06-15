pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.mediaControls
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

Item {
    id: root

    // ── Battle tab state ──────────────────────────────────────────────────
    // Mirrors GlobalStates.shelfBattleIndex so the bar can render the
    // sub-tab pills externally (frees vertical space here).
    property int battlePathIndex: GlobalStates.shelfBattleIndex
    onBattlePathIndexChanged: GlobalStates.shelfBattleIndex = battlePathIndex
    readonly property var pathTabs: ShelfPaths.paths

    // ── Level 1: main tab routing ─────────────────────────────────────────
    readonly property var tabOrder: ["files", "battle", "media"]
    readonly property int tabIndex: Math.max(0, tabOrder.indexOf(GlobalStates.shelfTab))

    // ── Level 2: sub-tab state per main tab ───────────────────────────────
    // Mirror to GlobalStates so the selected Files sub-tab survives shelf
    // open/close (ShelfContent may be re-instantiated per monitor on
    // visibility transitions).
    property string filesSubTab: GlobalStates.shelfFilesSubTab
    onFilesSubTabChanged: GlobalStates.shelfFilesSubTab = filesSubTab

    // ── Level 2 tab definitions ───────────────────────────────────────────
    readonly property var filesSubTabs: [
        { id: "explorer", label: qsTr("Explorer"), icon: "folder_open"   },
        { id: "recent",   label: qsTr("Recent"),   icon: "history"        },
        { id: "torrents", label: qsTr("Torrents"), icon: "downloading"    },
    ]

    // Battle sub-tabs are dynamic (from ShelfPaths) + settings
    readonly property var battleSubTabs: {
        const tabs = pathTabs.map((p, i) => ({
            id: "path_" + i,
            label: p.label ?? "Folder",
            icon: p.icon ?? "folder",
            index: i
        }))
        tabs.push({ id: "settings", label: qsTr("Manage"), icon: "settings", index: -1 })
        return tabs
    }
    readonly property string battleSubTab: {
        if (battlePathIndex === -1) return "settings"
        const id = "path_" + battlePathIndex
        return battleSubTabs.some(t => t.id === id) ? id : "path_0"
    }

    // ── Sliding strip (Level 1) ───────────────────────────────────────────
    Item {
        id: viewport
        anchors.fill: parent
        clip: true

        Item {
            id: strip
            width: viewport.width * 3
            height: parent.height
            x: -root.tabIndex * viewport.width
            Behavior on x {
                NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
            }

            // ── Tab 0: Files ──────────────────────────────────────────────
            Item {
                x: 0
                width: viewport.width
                height: strip.height

                TabsView {
                    anchors.fill: parent
                    tabs: root.filesSubTabs
                    currentId: root.filesSubTab
                    tabBarPosition: Qt.AlignLeft
                    onTabSelected: id => { root.filesSubTab = id; GlobalStates.shelfFilesSubTab = id }
                    componentFor: id => id === "torrents" ? torrentsComp
                                       : id === "recent"  ? recentComp
                                       : explorerComp
                }
                Component { id: explorerComp; ShelfExplorer  {} }
                Component { id: recentComp;   ShelfRecent    {} }
                Component { id: torrentsComp; ShelfTorrents  {} }
            }

            // ── Tab 1: Battle ─────────────────────────────────────────────
            Item {
                x: viewport.width
                width: viewport.width
                height: strip.height

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Sub-tabs lifted to BarContent.qml (visible on the bar's
                    // right side when shelf is open and Battle is active).
                    // Frees the full vertical space inside the shelf body.

                    // Level 2 content
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ShelfManagePaths {
                            anchors.fill: parent
                            visible: root.battlePathIndex === -1
                            opacity: root.battlePathIndex === -1 ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }

                        // Only build the FolderTab for the path the user is
                        // currently viewing. Each FolderTab spawns its own
                        // inotifywait at construction, so the previous
                        // pattern (Repeater → one per path × per monitor)
                        // leaked file watchers proportional to (#paths ×
                        // #monitors). Loader reuses the same instance and
                        // rebinds its properties when the active path
                        // changes — single inotifywait per shelf.
                        Loader {
                            anchors.fill: parent
                            visible: root.battlePathIndex >= 0
                            opacity: root.battlePathIndex >= 0 ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                            readonly property var activePath:
                                (root.battlePathIndex >= 0 && root.battlePathIndex < root.pathTabs.length)
                                    ? root.pathTabs[root.battlePathIndex]
                                    : null

                            active: activePath !== null
                            sourceComponent: ShelfFolderTab {
                                anchors.fill: parent
                                path:      parent.activePath?.path      ?? ""
                                filter:    parent.activePath?.filter    ?? "*"
                                mode:      parent.activePath?.mode      ?? "audio"
                                extractTo: parent.activePath?.extractTo ?? ""
                                label:     parent.activePath?.label     ?? ""
                            }
                        }
                    }
                }
            }

            // ── Tab 2: Media ──────────────────────────────────────────────
            Item {
                x: viewport.width * 2
                width: viewport.width
                height: strip.height

                Loader {
                    anchors.fill: parent
                    anchors.margins: 8
                    active: root.tabIndex >= 2 || GlobalStates.shelfTab === "media"

                    sourceComponent: Item {
                        Item {
                            anchors.fill: parent
                            visible: PlayerService.players.length === 0
                            ColumnLayout {
                                anchors.centerIn: parent; spacing: 8
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "music_off"; iconSize: 32
                                    color: Appearance.colors.colOnLayer0; opacity: 0.2
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Translation.tr("No active player")
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 6
                            visible: PlayerService.players.length > 0

                            PlayerControl {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                player: PlayerService.activePlayer
                                visualizerPoints: CavaService.visualizerPoints
                                radius: Appearance.rounding.normal
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 4; Layout.rightMargin: 4
                                visible: PlayerService.players.length > 1
                                implicitHeight: visible ? 20 : 0

                                StyledText {
                                    text: PlayerService.activePlayer?.identity ?? ""
                                    color: PlayerService.accentForPlayer(PlayerService.activePlayer)
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Medium
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                                Item { Layout.fillWidth: true }
                                Row {
                                    spacing: 6
                                    Repeater {
                                        model: PlayerService.players
                                        delegate: Rectangle {
                                            required property int index
                                            required property MprisPlayer modelData
                                            width: PlayerService.activeIndex === index ? 18 : 7
                                            height: 7; radius: 3.5
                                            color: PlayerService.activeIndex === index
                                                ? PlayerService.accentForPlayer(modelData)
                                                : Qt.alpha(Appearance.colors.colOnLayer0, 0.3)
                                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                            TapHandler { onTapped: PlayerService.activeIndex = index }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
