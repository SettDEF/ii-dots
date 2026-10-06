pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Who is in your Discord voice channel and who is talking. Meant to stay
// pinned over a game: click-through by default, so it never takes input.
StyledOverlayWidget {
    id: root
    minimumWidth: 200
    minimumHeight: 70

    contentItem: OverlayBackground {
        radius: root.contentRadius

        ColumnLayout {
            anchors { fill: parent; margins: 10 }
            spacing: 6

            // ── Header ───────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                MaterialSymbol {
                    text: DiscordVoice.inVoice ? "headset_mic" : "headset_off"
                    iconSize: Appearance.font.pixelSize.large
                    color: DiscordVoice.speakingCount > 0 ? Appearance.colors.colPrimary
                                                          : Appearance.colors.colSubtext
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: -2
                    StyledText {
                        Layout.fillWidth: true
                        text: DiscordVoice.inVoice ? DiscordVoice.channel
                                                   : Translation.tr("Not in a voice channel")
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        visible: DiscordVoice.inVoice && DiscordVoice.guild.length > 0
                        Layout.fillWidth: true
                        text: DiscordVoice.guild
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            // ── Members ──────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Column {
                    width: parent.width
                    spacing: 5

                    Repeater {
                        model: DiscordVoice.members
                        delegate: RowLayout {
                            id: member
                            required property var modelData
                            width: parent.width
                            spacing: 8
                            // Quiet people fade back, so the one talking is the
                            // one you see.
                            opacity: member.modelData.speaking ? 1 : 0.72
                            Behavior on opacity { NumberAnimation { duration: 120 } }

                            Item {
                                implicitWidth: 30
                                implicitHeight: 30

                                // The ring: theme primary, so it follows the wallpaper
                                // like everything else.
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: "transparent"
                                    border.width: member.modelData.speaking ? 2 : 0
                                    border.color: Appearance.colors.colPrimary
                                }
                                ClippingRectangle {
                                    anchors { fill: parent; margins: 3 }
                                    radius: width / 2
                                    color: Appearance.colors.colLayer2
                                    Image {
                                        anchors.fill: parent
                                        source: member.modelData.avatar
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: member.modelData.name
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: member.modelData.speaking ? Font.DemiBold : Font.Normal
                                color: Appearance.colors.colOnLayer1
                            }

                            MaterialSymbol {
                                visible: member.modelData.streaming
                                text: "screen_share"; iconSize: 15
                                color: Appearance.colors.colPrimary
                            }
                            MaterialSymbol {
                                visible: member.modelData.video
                                text: "videocam"; iconSize: 15
                                color: Appearance.colors.colSubtext
                            }
                            MaterialSymbol {
                                visible: member.modelData.muted && !member.modelData.deafened
                                text: "mic_off"; iconSize: 15
                                color: Appearance.m3colors.m3error
                            }
                            MaterialSymbol {
                                visible: member.modelData.deafened
                                text: "headset_off"; iconSize: 15
                                color: Appearance.m3colors.m3error
                            }
                        }
                    }
                }
            }
        }
    }
}
