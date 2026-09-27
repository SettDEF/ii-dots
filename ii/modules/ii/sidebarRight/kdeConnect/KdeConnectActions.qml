import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Reusable phone-widget content. Shows a media card for the phone's
// own MPRIS proxy (provided by KDE Connect), then a 3-column action
// grid for the connected device.
ColumnLayout {
    id: root
    property var device: KdeConnectService.firstDevice
    spacing: 10
    visible: device !== null && device.reachable

    // Phone media comes from KDE Connect's mprisremote plugin (DBus),
    // NOT from local desktop MPRIS players. See KdeConnectService.
    readonly property bool hasMedia: KdeConnectService.phoneMediaAvailable
                                  && (KdeConnectService.phoneMediaTitle.length > 0
                                      || KdeConnectService.phoneMediaPlayer.length > 0)
    readonly property bool _phonePlaying: KdeConnectService.phoneMediaIsPlaying

    // ── Media card — visible when any player is active ───────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 84
        radius: 20
        visible: root.hasMedia
        color: Appearance.m3colors.m3surfaceContainerHigh
        Behavior on color { ColorAnimation { duration: 160 } }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 12

            // Album art
            Rectangle {
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64
                radius: 14
                color: Appearance.colors.colLayer3
                clip: true
                Image {
                    anchors.fill: parent
                    source: KdeConnectService.phoneMediaArtUrl
                    visible: status === Image.Ready
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 128
                    sourceSize.height: 128
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: KdeConnectService.phoneMediaArtUrl.length === 0
                    text: "music_note"
                    iconSize: 28
                    color: Appearance.m3colors.m3onSurface
                }
            }

            // Title + artist + transport
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: KdeConnectService.phoneMediaTitle
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSurface
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: KdeConnectService.phoneMediaArtist
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    component CtrlBtn: Rectangle {
                        property string sym: ""
                        property var onTap: () => {}
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 28
                        Layout.alignment: Qt.AlignVCenter
                        radius: height / 2
                        color: hov.hovered ? Appearance.colors.colLayer2Hover : ColorUtils.transparentize(Appearance.colors.colLayer2Hover)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        HoverHandler { id: hov }
                        TapHandler { onTapped: parent.onTap() }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: parent.sym
                            iconSize: 18
                            fill: 1
                            color: Appearance.m3colors.m3onSurface
                        }
                    }

                    CtrlBtn {
                        sym: "skip_previous"
                        onTap: () => KdeConnectService.phoneMediaPrevious()
                    }
                    Rectangle {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 28
                        Layout.alignment: Qt.AlignVCenter
                        radius: height / 2
                        color: root._phonePlaying
                            ? Appearance.colors.colPrimary
                            : (playHov.hovered ? Appearance.colors.colLayer2Hover
                                               : Appearance.m3colors.m3surfaceContainerHighest)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        HoverHandler { id: playHov }
                        TapHandler { onTapped: KdeConnectService.phoneMediaPlayPause() }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root._phonePlaying ? "pause" : "play_arrow"
                            iconSize: 20
                            fill: 1
                            color: root._phonePlaying
                                ? Appearance.colors.colOnPrimary
                                : Appearance.m3colors.m3onSurface
                        }
                    }
                    CtrlBtn {
                        sym: "skip_next"
                        onTap: () => KdeConnectService.phoneMediaNext()
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: KdeConnectService.phoneMediaPlayer
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        opacity: 0.8
                    }
                }
            }
        }
    }

    // ── Action grid — matches the surrounding widgets' tile style ─────
    GridLayout {
        Layout.fillWidth: true
        columns: 3
        rowSpacing: 6
        columnSpacing: 6

        component ActionTile: Rectangle {
            id: tile
            required property string icon
            required property string label
            property bool danger: false
            signal pressed()
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            radius: tHov.hovered ? Appearance.rounding.large : height / 2
            Behavior on radius { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }

            color: tHov.hovered
                ? Appearance.colors.colLayer2Hover
                : Appearance.colors.colLayer2
            Behavior on color { ColorAnimation { duration: 140 } }

            HoverHandler { id: tHov }
            TapHandler { onTapped: tile.pressed() }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 2
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: tile.icon
                    iconSize: 20
                    fill: 1
                    color: tile.danger
                        ? Appearance.m3colors.m3error
                        : Appearance.colors.colOnLayer1
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: tile.label
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Medium
                    color: tile.danger
                        ? Appearance.m3colors.m3error
                        : Appearance.colors.colOnLayer1
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
            }
        }

        ActionTile {
            icon: "notifications_active"; label: Translation.tr("Ring")
            onPressed: if (root.device) KdeConnectService.ring(root.device.id)
        }
        ActionTile {
            icon: "wifi_tethering"; label: Translation.tr("Ping")
            onPressed: if (root.device) KdeConnectService.ping(root.device.id, "Hello from " + Qt.application.name)
        }
        ActionTile {
            icon: "content_paste"; label: Translation.tr("Clipboard")
            onPressed: {
                const id = root.device?.id ?? ""
                if (id) Quickshell.execDetached(["bash", "-c",
                    `kdeconnect-cli --device '${id}' --share-text "$(wl-paste)"`])
            }
        }
        ActionTile {
            icon: "upload_file"; label: Translation.tr("Send file")
            onPressed: {
                const id   = root.device?.id   ?? ""
                const name = root.device?.name ?? "phone"
                if (id) Quickshell.execDetached(["bash", "-c",
                    `f=$(zenity --file-selection --title="Send to ${name}" 2>/dev/null) && ` +
                    `[ -n "$f" ] && kdeconnect-cli --device '${id}' --share "$f"`])
            }
        }
        ActionTile {
            icon: "sms"; label: Translation.tr("Send SMS")
            onPressed: {
                const id = root.device?.id ?? ""
                if (id) Quickshell.execDetached(["bash", "-c",
                    `dest=$(zenity --entry --title="Send SMS to" --text="Phone number:" 2>/dev/null) && ` +
                    `[ -n "$dest" ] && msg=$(zenity --entry --title="Message" --text="Message body:" 2>/dev/null) && ` +
                    `[ -n "$msg" ] && kdeconnect-cli --device '${id}' --destination "$dest" --send-sms "$msg"`])
            }
        }
        ActionTile {
            icon: "open_in_new"; label: Translation.tr("Open app")
            onPressed: KdeConnectService.openCli()
        }
    }
    // (Previous inline Process objects were converted to Quickshell.execDetached
    //  to avoid a SIGSEGV in QV4 GC when the panel was closed while a child
    //  Process was still running — the Process.onFinished signal then evaluated
    //  inside a destroyed component scope. execDetached has no QML lifecycle.)
}
