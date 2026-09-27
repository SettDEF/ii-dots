pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

// Theme / wallpaper picker — shown in the overview search when the query
// starts with the theme prefix (Config.options.search.prefix.theme).
// Ported from the former Nexus "themes" section.
Item {
    id: root

    // Query forwarded from the overview search input (prefix already stripped).
    property string query: ""

    // Recents/history come from the shared WallpaperRecents singleton.
    // Slice walltune history to the last 24 here for the compact strip.
    readonly property var wallpaperRecents: WallpaperRecents.recents
    readonly property var walltuneHistory: WallpaperRecents.walltuneHistory.slice(0, 24)

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen) WallpaperRecents.refresh()
        }
    }

    function pickWallpaper(path) {
        Wallpapers.select(path, Appearance.m3colors.darkmode)
    }
    function applyWalltuneEntry(entry) {
        if (!entry?.state) return
        const sJson = JSON.stringify(entry.state).replace(/'/g, "'\\''")
        applyHistProc.command = ["bash", "-c",
            `f="$HOME/.local/state/quickshell/walltune-state.json"; ` +
            `mkdir -p "$(dirname "$f")"; ` +
            `printf '%s' '${sJson}' > "$f"`]
        applyHistProc.running = true
        GlobalStates.wallTuneOpen = true
        GlobalStates.overviewOpen = false
    }
    Process { id: applyHistProc }

    // Filename-substring filter. Empty query → unfiltered list.
    readonly property var filteredRecents: {
        const q = root.query.trim().toLowerCase()
        if (q === "") return root.wallpaperRecents
        return root.wallpaperRecents.filter(p =>
            p.toLowerCase().split("/").pop().includes(q))
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        // ── Compact header: current preview + actions side-by-side ──────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Current wallpaper preview (compact)
            Rectangle {
                Layout.preferredWidth: 200
                Layout.preferredHeight: 112
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                clip: true

                Image {
                    anchors.fill: parent
                    source: Config.options.background.wallpaperPath !== ""
                        ? "file://" + Config.options.background.wallpaperPath : ""
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    asynchronous: true
                    cache: true
                    sourceSize.width: 400
                    sourceSize.height: 224
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                }

                BottomFadeOverlay {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    text: FileUtils.fileNameForPath(Config.options.background.wallpaperPath)
                }

                Row {
                    anchors { top: parent.top; right: parent.right; margins: 6 }
                    spacing: 3
                    Repeater {
                        model: [
                            Appearance.m3colors.m3primary,
                            Appearance.m3colors.m3secondary,
                            Appearance.m3colors.m3tertiary,
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: 10; height: 10; radius: 5
                            color: modelData
                            border.width: 1
                            border.color: Qt.alpha("white", 0.25)
                        }
                    }
                }
            }

            // Action column
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    text: qsTr("Theme")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Browse all wallpapers, or pick a recent one below.")
                    font.pixelSize: Appearance.font.pixelSize.smaller - 1
                    color: Appearance.colors.colOnLayer0; opacity: 0.55
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    spacing: 8

                    Rectangle {
                        implicitWidth: 132; implicitHeight: 34
                        radius: Appearance.rounding.full
                        color: wsHov.hovered ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
                        Behavior on color { ColorAnimation { duration: 130 } }
                        HoverHandler { id: wsHov }
                        TapHandler {
                            onTapped: {
                                GlobalStates.wallpaperSelectorOpen = true
                                GlobalStates.overviewOpen = false
                            }
                        }
                        RowLayout {
                            anchors.centerIn: parent; spacing: 6
                            MaterialSymbol {
                                text: "wallpaper"
                                iconSize: Appearance.font.pixelSize.normal
                                color: wsHov.hovered
                                    ? Appearance.m3colors.m3onSecondaryContainer
                                    : Appearance.colors.colOnLayer0
                                Behavior on color { ColorAnimation { duration: 130 } }
                            }
                            StyledText {
                                text: qsTr("Pick Wallpaper")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                color: wsHov.hovered
                                    ? Appearance.m3colors.m3onSecondaryContainer
                                    : Appearance.colors.colOnLayer0
                                Behavior on color { ColorAnimation { duration: 130 } }
                            }
                        }
                    }

                    Rectangle {
                        implicitWidth: 116; implicitHeight: 34
                        radius: Appearance.rounding.full
                        color: tuneHov.hovered ? Appearance.colors.colPrimary : Qt.alpha(Appearance.colors.colPrimary, 0.15)
                        Behavior on color { ColorAnimation { duration: 130 } }
                        HoverHandler { id: tuneHov }
                        TapHandler {
                            onTapped: {
                                GlobalStates.wallTuneOpen = true
                                GlobalStates.overviewOpen = false
                            }
                        }
                        RowLayout {
                            anchors.centerIn: parent; spacing: 6
                            MaterialSymbol {
                                text: "tune"
                                iconSize: Appearance.font.pixelSize.normal
                                color: tuneHov.hovered ? "white" : Appearance.colors.colPrimary
                                Behavior on color { ColorAnimation { duration: 130 } }
                            }
                            StyledText {
                                text: qsTr("Tune Colors")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                color: tuneHov.hovered ? "white" : Appearance.colors.colPrimary
                                Behavior on color { ColorAnimation { duration: 130 } }
                            }
                        }
                    }
                }
            }
        }

        // ── Recent wallpapers — proper grid (virtualised) ───────────────
        RowLayout {
            Layout.fillWidth: true
            visible: root.wallpaperRecents.length > 0
            spacing: 6
            MaterialSymbol {
                text: "history"
                iconSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer0; opacity: 0.6
            }
            StyledText {
                Layout.fillWidth: true
                text: root.query.length > 0
                    ? qsTr("Recent — %1 match").arg(root.filteredRecents.length)
                    : qsTr("Recent wallpapers")
                font.pixelSize: Appearance.font.pixelSize.smaller - 1
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer0; opacity: 0.55
            }
        }

        GridView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.wallpaperRecents.length > 0
            clip: true
            cellWidth: width / 4
            cellHeight: 86
            model: root.filteredRecents
            cacheBuffer: cellHeight * 2
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            ScrollBar.vertical: StyledScrollBar {}

            delegate: Item {
                required property string modelData
                width: GridView.view.cellWidth
                height: GridView.view.cellHeight
                readonly property bool isCurrent: modelData === Config.options.background.wallpaperPath

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: 8
                    color: Appearance.colors.colLayer1
                    clip: true
                    border.width: parent.isCurrent ? 2 : (rwHov.hovered ? 1 : 0)
                    border.color: parent.isCurrent
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colOutlineVariant
                    Behavior on border.width { NumberAnimation { duration: 120 } }

                    Image {
                        id: rwImg
                        anchors.fill: parent
                        anchors.margins: parent.border.width
                        source: "file://" + parent.parent.modelData
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                        cache: true
                        // Cap decode size — thumbs render ~110x80, decoding
                        // 4K wallpapers each would shred memory.
                        sourceSize.width: 280
                        sourceSize.height: 200
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 160 } }
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: rwImg.width; height: rwImg.height
                                radius: 6
                            }
                        }
                    }

                    // Filename overlay on hover
                    BottomFadeOverlay {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        visible: rwHov.hovered || Appearance.touchUi
                        barHeight: 18
                        elide: Text.ElideMiddle
                        text: FileUtils.fileNameForPath(parent.parent.modelData)
                    }

                    HoverHandler { id: rwHov }
                    TapHandler { onTapped: root.pickWallpaper(parent.parent.modelData) }
                }
            }
        }

        // ── Recent WallTune outputs strip (compact) ─────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.walltuneHistory.length > 0 && root.query.length === 0
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                MaterialSymbol {
                    text: "palette"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0; opacity: 0.6
                }
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Recent themes")
                    font.pixelSize: Appearance.font.pixelSize.smaller - 1
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0; opacity: 0.55
                }
            }
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                orientation: ListView.Horizontal
                spacing: 4
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.walltuneHistory

                delegate: Rectangle {
                    required property var modelData
                    width: 52; height: 32
                    radius: 6
                    color: thHov.hovered
                        ? Appearance.colors.colLayer2
                        : Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    Row {
                        anchors {
                            left: parent.left; right: parent.right
                            top: parent.top; bottom: parent.bottom
                            margins: 4
                        }
                        spacing: 2
                        Rectangle { width: (parent.width - 4) / 3; height: parent.height; radius: 3; color: parent.parent.modelData.primary || "#444" }
                        Rectangle { width: (parent.width - 4) / 3; height: parent.height; radius: 3; color: parent.parent.modelData.secondary || "#444" }
                        Rectangle { width: (parent.width - 4) / 3; height: parent.height; radius: 3; color: parent.parent.modelData.tertiary || "#444" }
                    }
                    HoverHandler { id: thHov }
                    TapHandler { onTapped: root.applyWalltuneEntry(parent.modelData) }
                }
            }
        }
    }
}
