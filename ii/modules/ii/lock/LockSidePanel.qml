import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarRight.quickToggles.androidStyle

/// The lock screen's right panel, in the right sidebar's look: the ROG profile (the sidebar's own
/// switcher) and "Quiet, then sleep when the downloads are done" (SleepAfterDownloads).
Item {
    id: root
    implicitWidth: Appearance.sizes.sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2
    implicitHeight: card.implicitHeight

    readonly property var s: SleepAfterDownloads
    readonly property int shown: 5

    function eta(sec) {
        if (sec < 0) return "";
        if (sec < 60) return Translation.tr("%1 s").arg(Math.round(sec));
        if (sec < 3600) return Translation.tr("%1 min").arg(Math.round(sec / 60));
        return Translation.tr("%1 h %2 min").arg(Math.floor(sec / 3600)).arg(Math.round(sec % 3600 / 60));
    }

    StyledRectangularShadow { target: card }
    Rectangle {
        id: card
        width: parent.width
        implicitHeight: col.implicitHeight + 24
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 10

            // the profile, as in the sidebar's ROG drawer
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 64
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1
                RogProfileSwitcher {
                    anchors { fill: parent; margins: 4 }
                }
            }

            // what is downloading
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: dl.implicitHeight + 24
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: dl
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialSymbol {
                            text: "download"
                            iconSize: 17
                            color: root.s.moving.length > 0 ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Downloads")
                            font.weight: Font.DemiBold
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            text: root.s.items.length === 0 ? Translation.tr("none")
                                : Translation.tr("%1 running").arg(root.s.moving.length)
                                  + (root.s.stalled.length > 0 ? " · " + Translation.tr("%1 stalled").arg(root.s.stalled.length) : "")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }

                    Repeater {
                        model: root.s.items.slice(0, root.shown)
                        delegate: ColumnLayout {
                            id: row
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 3
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                MaterialSymbol {
                                    text: row.modelData.kind === "browser" ? "language" : "swap_vert"
                                    iconSize: 14
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: row.modelData.name
                                    elide: Text.ElideMiddle
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: row.modelData.stalled ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    // speed and time left; stalled ones say so
                                    text: row.modelData.stalled ? Translation.tr("stalled")
                                        : [row.modelData.speed > 0 ? StringUtils.formatBytes(row.modelData.speed) + "/s" : "", root.eta(row.modelData.eta)].filter(x => x).join(" · ")
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            StyledProgressBar {
                                Layout.fillWidth: true
                                visible: row.modelData.progress >= 0
                                value: Math.max(0, row.modelData.progress)
                                highlightColor: row.modelData.stalled ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                            }
                        }
                    }
                    StyledText {
                        visible: root.s.items.length > root.shown
                        text: Translation.tr("and %1 more").arg(root.s.items.length - root.shown)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        visible: root.s.items.length === 0
                        text: Torrents.reachable ? Translation.tr("Nothing is downloading.")
                            : Translation.tr("Nothing is downloading (qBittorrent is not running).")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            // the action: start, or what it is doing and a way back
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 52
                buttonRadius: Appearance.rounding.full
                colBackground: root.s.phase === "idle" ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                colBackgroundHover: root.s.phase === "idle" ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                onClicked: root.s.phase === "idle" ? root.s.start() : root.s.cancel()

                contentItem: RowLayout {
                    anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                    spacing: 10
                    MaterialSymbol {
                        text: root.s.phase === "idle" ? "bedtime" : "close"
                        iconSize: 20
                        fill: 1
                        color: root.s.phase === "idle" ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.s.phase === "idle" ? Translation.tr("Quiet, then sleep when done")
                                : root.s.phase === "sleeping" ? Translation.tr("Going to sleep…")
                                : root.s.secondsLeft >= 0 ? Translation.tr("Sleeping in %1 s").arg(Math.ceil(root.s.secondsLeft))
                                : Translation.tr("Waiting for %1 download(s)").arg(root.s.moving.length)
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: root.s.phase === "idle" ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.s.phase === "idle"
                                ? (root.s.moving.length > 0 ? Translation.tr("Fans down, then sleep after the last one") : Translation.tr("Nothing to wait for: sleeps in a minute"))
                                : Translation.tr("Quiet profile · click to cancel")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: root.s.phase === "idle" ? ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.2) : Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }
}
