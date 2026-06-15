// Last.fm / MPRIS music tile. At base size: icon + title + artist.
// At expanded size (cellSize > 1): album art on the left, track + artist
// stacked, prev / play-pause / next controls along the bottom.
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Widgets

AndroidQuickToggleButton {
    id: root

    toggleModel: LastFmToggle {}

    // Custom layout used when this tile is sized > 1 in the grid.
    expandedDelegate: Component {
        RowLayout {
            id: bigRow
            spacing: 10

            readonly property bool playing: MprisController.isPlaying
            readonly property bool hasPlayer: MprisController.activePlayer !== null

            // ── Album art (or material icon fallback) ───────────────
            // ClippingRectangle from Quickshell.Widgets actually rounds
            // the mask of its children — a plain Rectangle with radius
            // + clip:true only clips to the rectangular bbox, so the
            // image was overflowing the rounded corners.
            ClippingRectangle {
                Layout.preferredWidth: parent.height - 8
                Layout.preferredHeight: parent.height - 8
                Layout.alignment: Qt.AlignVCenter
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer3

                Image {
                    anchors.fill: parent
                    source: root.toggleModel.iconImage
                    visible: status === Image.Ready && root.toggleModel.iconImage.length > 0
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 96
                    sourceSize.height: 96
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !root.toggleModel.iconImage || root.toggleModel.iconImage.length === 0
                    text: root.toggleModel.icon
                    iconSize: 28
                    color: Appearance.m3colors.m3onSurface
                }
            }

            // ── Title / artist + control row ────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: root.toggleModel.name
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSurface
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.toggleModel.statusText
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }

                Item { Layout.fillHeight: true }

                // Transport controls — only when an MPRIS player exists.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    spacing: 4
                    visible: bigRow.hasPlayer

                    component CtrlBtn: Rectangle {
                        property string sym: ""
                        property var onTap: () => {}
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignVCenter
                        radius: Appearance.rounding.full
                        color: hov.hovered ? Appearance.colors.colLayer2Hover : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        HoverHandler { id: hov }
                        TapHandler { onTapped: parent.onTap() }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: parent.sym
                            iconSize: 18
                            color: Appearance.m3colors.m3onSurface
                        }
                    }

                    CtrlBtn { sym: "skip_previous"; onTap: () => MprisController.activePlayer?.previous() }
                    Rectangle {
                        Layout.preferredWidth: 36; Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignVCenter
                        radius: Appearance.rounding.full
                        color: bigRow.playing
                            ? Appearance.colors.colPrimary
                            : (playHov.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        HoverHandler { id: playHov }
                        TapHandler {
                            onTapped: if (MprisController.canTogglePlaying) MprisController.togglePlaying()
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: bigRow.playing ? "pause" : "play_arrow"
                            iconSize: 20
                            fill: 1
                            color: bigRow.playing
                                ? Appearance.colors.colOnPrimary
                                : Appearance.m3colors.m3onSurface
                        }
                    }
                    CtrlBtn { sym: "skip_next"; onTap: () => MprisController.activePlayer?.next() }
                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}
