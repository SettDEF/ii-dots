pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Who is in your Discord voice channel and who is talking. Meant to stay
// pinned over a game: click-through by default, so it never takes input.
StyledOverlayWidget {
    id: root
    minimumWidth: 200
    minimumHeight: 70
    canHideBackground: true
    canRestrictVisibility: true

    // Over a game there is no surface to read against, so with no background the
    // text goes white and gets a shadow instead.
    readonly property color textColor: root.showBackground ? root.textColor : "white"
    readonly property color subColor: root.showBackground ? root.subColor : "#d0ffffff"

    contentItem: OverlayBackground {
        radius: root.contentRadius
        shown: root.showBackground
        // Pinned over a game and not in a call: nothing to show, so show nothing
        // rather than "Not in a voice channel" in the corner of the screen.
        opacity: (DiscordVoice.inVoice || GlobalStates.overlayOpen) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        ColumnLayout {
            anchors { fill: parent; margins: 10 }
            spacing: 6
            layer.enabled: !root.showBackground
            layer.effect: DropShadow {
                radius: 6
                samples: 13
                spread: 0.25
                color: "#d0000000"
            }

            // ── Header ───────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                MaterialSymbol {
                    text: DiscordVoice.inVoice ? "headset_mic" : "headset_off"
                    iconSize: Appearance.font.pixelSize.large
                    color: DiscordVoice.speakingCount > 0 ? Appearance.colors.colPrimary
                                                          : root.subColor
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
                        color: root.textColor
                    }
                    StyledText {
                        visible: DiscordVoice.inVoice && DiscordVoice.guild.length > 0
                        Layout.fillWidth: true
                        text: DiscordVoice.guild
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: root.subColor
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
                                color: root.textColor
                            }

                            MaterialSymbol {
                                visible: member.modelData.streaming
                                text: "screen_share"; iconSize: 15
                                color: Appearance.colors.colPrimary
                            }
                            MaterialSymbol {
                                visible: member.modelData.video
                                text: "videocam"; iconSize: 15
                                color: root.subColor
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
