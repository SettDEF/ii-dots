pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

// Per-app audio sources: live meter + volume + "audio follows focus" mode.
ColumnLayout {
    id: root
    // Every open app, not just the ones currently streaming — a silent
    // Telegram still gets a row and a volume.
    readonly property list<var> appNodes: AppVolumes.rows
    readonly property int rowHeight: 54
    spacing: 2

    // Height the popup can use to size itself: rows (capped) + padding.
    // No header — the "Sources" tab in CornerPopup already names this view.
    // The empty state needs room for PagePlaceholder's 56px icon plus its
    // title, otherwise the popup crops it into a blob.
    readonly property int contentHeight: root.appNodes.length === 0
        ? 116
        : 10 + Math.min(root.appNodes.length, 5) * (rowHeight + 2)

    StyledListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: 6
        Layout.rightMargin: 6
        Layout.bottomMargin: 6
        clip: true
        spacing: 2
        model: ScriptModel { values: root.appNodes }
        delegate: AudioRow {
            anchors.left: parent?.left
            anchors.right: parent?.right
            required property var modelData
            row: modelData
        }

        PagePlaceholder {
            anchors.centerIn: parent
            icon: "music_off"
            title: Translation.tr("Nothing playing")
            shown: root.appNodes.length === 0
        }
    }

    // ── One application row ─────────────────────────────────────────────
    component AudioRow: Rectangle {
        id: rowRoot
        required property var row
        readonly property var node: rowRoot.row?.node ?? null
        readonly property bool live: rowRoot.row?.live ?? false
        implicitHeight: root.rowHeight
        radius: Appearance.rounding.small
        color: rowHov.hovered ? Qt.alpha(Appearance.colors.colOnLayer0, 0.06) : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
        // Apps with no stream are still listed, just visibly quieter.
        opacity: rowRoot.live ? 1 : 0.55

        // Needed so node.audio / properties are populated.
        PwObjectTracker { objects: rowRoot.node ? [rowRoot.node] : [] }

        // Live peak (0..1) for this stream.
        PwNodePeakMonitor {
            id: peakMon
            node: rowRoot.node
            enabled: rowRoot.visible && rowRoot.live
        }

        readonly property int mode: rowRoot.live ? AppAudioFocus.getMode(rowRoot.node) : 0

        HoverHandler { id: rowHov }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 6
            spacing: 8

            // App icon
            Image {
                Layout.alignment: Qt.AlignVCenter
                sourceSize.width: 26
                sourceSize.height: 26
                visible: source != ""
                source: {
                    let icon = AppSearch.guessIcon(rowRoot.node?.properties?.["application.icon-name"] ?? "");
                    if (AppSearch.iconExists(icon))
                        return Quickshell.iconPath(icon, "image-missing");
                    icon = AppSearch.guessIcon(rowRoot.node?.properties?.["node.name"]
                        ?? (rowRoot.row?.name ?? ""));
                    return Quickshell.iconPath(icon, "image-missing");
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: rowRoot.row?.name ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: rowRoot.node?.audio?.muted
                            ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer0
                    }
                    // Mode chip — click cycles Always → On workspace → When focused.
                    // Only meaningful for a real stream.
                    Rectangle {
                        id: modeChip
                        visible: rowRoot.live
                        Layout.alignment: Qt.AlignVCenter
                        implicitHeight: 20
                        implicitWidth: chipRow.implicitWidth + 12
                        radius: height / 2
                        color: rowRoot.mode === 0
                            ? (chipHov.hovered ? Qt.alpha(Appearance.colors.colOnLayer0, 0.10) : "transparent")
                            : Appearance.colors.colSecondaryContainer
                        border.width: rowRoot.mode === 0 ? 1 : 0
                        border.color: Qt.alpha(Appearance.colors.colOnLayer0, 0.20)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        HoverHandler { id: chipHov }
                        TapHandler { onTapped: AppAudioFocus.cycleMode(rowRoot.node) }
                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 3
                            MaterialSymbol {
                                text: AppAudioFocus.modeIcon(rowRoot.mode)
                                iconSize: 13
                                color: rowRoot.mode === 0
                                    ? Appearance.colors.colSubtext
                                    : Appearance.colors.colOnSecondaryContainer
                            }
                            StyledText {
                                text: AppAudioFocus.modeName(rowRoot.mode)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: rowRoot.mode === 0
                                    ? Appearance.colors.colSubtext
                                    : Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }

                // Volume slider with an overlaid live meter behind the fill.
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 18

                    // Live meter: a soft bar that tracks peak, sitting under the slider.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 4
                        radius: 2
                        color: Qt.alpha(Appearance.colors.colOnLayer0, 0.08)
                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            height: parent.height
                            radius: parent.radius
                            // Peak scaled by current volume so a quiet stream reads quiet.
                            width: parent.width * Math.min(1, peakMon.peak * (rowRoot.node?.audio?.volume ?? 1))
                            color: Qt.alpha(Appearance.colors.colPrimary, 0.45)
                            Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                        }
                    }

                    StyledSlider {
                        id: slider
                        anchors.fill: parent
                        from: 0
                        to: 1
                        // Live streams read straight from the node; a silent
                        // app reads the level remembered for it.
                        value: AppVolumes.volumeFor(rowRoot.row)
                        onMoved: AppVolumes.setVolume(rowRoot.row, value)
                    }
                }
            }

            // Quick mute toggle — needs a real stream to act on.
            Rectangle {
                visible: rowRoot.live
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 28
                implicitHeight: 28
                radius: height / 2
                color: muteHov.hovered ? Qt.alpha(Appearance.colors.colOnLayer0, 0.08) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
                HoverHandler { id: muteHov }
                TapHandler {
                    onTapped: if (rowRoot.node?.audio) rowRoot.node.audio.muted = !rowRoot.node.audio.muted
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: rowRoot.node?.audio?.muted ? "volume_off" : "volume_up"
                    iconSize: 17
                    color: rowRoot.node?.audio?.muted ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer0
                }
            }
        }
    }
}
