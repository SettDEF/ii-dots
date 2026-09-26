pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * qBittorrent.
 *
 * Ordered by what is actually moving, not by name or date added: with 48
 * torrents the question is almost always "what is running right now", and an
 * alphabetical list buries that under things that have been idle for months.
 *
 * Torrents whose data has gone missing get their own line at the top. They look
 * perfectly healthy in a normal list while seeding nothing, and on this machine
 * they accumulate whenever an external disk is not mounted.
 */
Scope {
    id: root

    // The upload watcher has to run whether or not the panel is open.
    Component.onCompleted: Torrents.ready

    IpcHandler {
        target: "torrents"
        function toggle(): void { GlobalStates.torrentsOpen = !GlobalStates.torrentsOpen }
        function open(): void   { GlobalStates.torrentsOpen = true }
        function close(): void  { GlobalStates.torrentsOpen = false }
        function pauseAll(): void  { Torrents.pauseAll() }
        function resumeAll(): void { Torrents.resumeAll() }
        function status(): string {
            return JSON.stringify({
                reachable: Torrents.reachable, count: Torrents.count,
                uploading: Torrents.activeUploads, missing: Torrents.missingFiles,
                up: Torrents.upRate, dl: Torrents.dlRate,
            })
        }
    }

    GlobalShortcut {
        name: "torrentsToggle"
        description: "Toggle the qBittorrent panel"
        onPressed: GlobalStates.torrentsOpen = !GlobalStates.torrentsOpen
    }

    StackedPanelLoader {
        isOpen: GlobalStates.torrentsOpen

        sourceComponent: StackedSettingsPanel {
            id: win
            panelId: "torrents"
            title: Translation.tr("Torrents")
            icon: "download"
            onRequestClose: GlobalStates.torrentsOpen = false

            // ── totals ───────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: sumCol.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: sumCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        ColumnLayout {
                            spacing: 0
                            RowLayout {
                                spacing: 5
                                MaterialSymbol {
                                    text: "upload"; iconSize: 16
                                    color: Torrents.upRate > 0 ? Appearance.colors.colPrimary
                                                               : Appearance.colors.colSubtext
                                }
                                StyledText {
                                    text: Torrents.fmtRate(Torrents.upRate)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.family: Appearance.font.family.monospace
                                    color: Torrents.upRate > 0 ? Appearance.colors.colPrimary
                                                               : Appearance.colors.colOnLayer1
                                }
                            }
                            StyledText {
                                text: Translation.tr("%1 this session").arg(Torrents.fmtBytes(Torrents.upTotal))
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                        }
                        ColumnLayout {
                            spacing: 0
                            RowLayout {
                                spacing: 5
                                MaterialSymbol { text: "download"; iconSize: 16; color: Appearance.colors.colSubtext }
                                StyledText {
                                    text: Torrents.fmtRate(Torrents.dlRate)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.family: Appearance.font.family.monospace
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                            StyledText {
                                text: Translation.tr("%1 this session").arg(Torrents.fmtBytes(Torrents.dlTotal))
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                        }
                        Item { Layout.fillWidth: true }
                        DialogButton {
                            buttonText: Translation.tr("Pause all")
                            onClicked: Torrents.pauseAll()
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: !Torrents.reachable
                            ? Translation.tr("qBittorrent is not answering on 127.0.0.1:8080")
                            : Translation.tr("%1 torrents · %2 uploading now")
                                .arg(Torrents.count).arg(Torrents.activeUploads)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Torrents.reachable ? Appearance.colors.colSubtext
                                                  : Appearance.m3colors.m3error
                    }
                }
            }

            // ── missing data warning ─────────────────────────────────────
            Rectangle {
                visible: Torrents.missingFiles > 0
                Layout.fillWidth: true
                implicitHeight: missRow.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.m3colors.m3error

                RowLayout {
                    id: missRow
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 9
                    MaterialSymbol { text: "folder_off"; iconSize: 16; color: Appearance.m3colors.m3error }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("%1 torrents cannot find their files").arg(Torrents.missingFiles)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: Translation.tr("They look like they are seeding and are uploading nothing. Usually a disk that is not mounted.")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            // ── the list ─────────────────────────────────────────────────
            Repeater {
                // Only what is worth looking at: anything moving, plus a few
                // idle ones for context. All 48 would be a wall.
                model: Torrents.torrents.slice(0, 12)
                delegate: Rectangle {
                    id: tor
                    required property var modelData
                    readonly property bool up: (modelData.upspeed ?? 0) > 0
                    readonly property bool missing: String(modelData.state ?? "") === "missingFiles"
                    Layout.fillWidth: true
                    implicitHeight: torCol.implicitHeight + 18
                    radius: Appearance.rounding.small
                    color: torHov.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                    HoverHandler { id: torHov }

                    ColumnLayout {
                        id: torCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 9 }
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            MaterialSymbol {
                                text: tor.missing ? "folder_off" : tor.up ? "upload" : "pause"
                                iconSize: 15
                                color: tor.missing ? Appearance.m3colors.m3error
                                     : tor.up ? Appearance.colors.colPrimary
                                              : Appearance.colors.colSubtext
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: tor.modelData.name ?? ""
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                visible: tor.up
                                text: Torrents.fmtRate(tor.modelData.upspeed)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.family: Appearance.font.family.monospace
                                color: Appearance.colors.colPrimary
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 23
                            elide: Text.ElideRight
                            text: Translation.tr("%1 up · ratio %2 · %3 peer(s)")
                                    .arg(Torrents.fmtBytes(tor.modelData.uploaded))
                                    .arg(Number(tor.modelData.ratio ?? 0).toFixed(2))
                                    .arg(tor.modelData.num_leechs ?? 0)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }
}
