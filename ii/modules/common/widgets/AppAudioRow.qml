pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

/**
 * One application in a volume list: icon, name, focus-mode chip, a volume
 * slider carrying the live level in its track, and mute.
 *
 * Shared by the corner popup's Sources view and the audio panel's Apps list.
 * Both take their rows from AppVolumes.rows, which lists every OPEN app - a
 * silent one gets a row and a remembered volume - and which is only replaced
 * when the set of apps changes, so neither list rebuilds its delegates on every
 * PipeWire node update.
 *
 *     AppAudioRow {
 *         row: modelData                     // an AppVolumes.rows entry
 *         showRouting: true                  // destination + route button
 *         onRouteRequested: openPicker(row.node)
 *     }
 */
Rectangle {
    id: rowRoot

    required property var row
    /// Show where the app plays and a button to change it.
    property bool showRouting: false
    signal routeRequested()

    readonly property var node: rowRoot.row?.node ?? null
    readonly property bool live: rowRoot.row?.live ?? false
    readonly property bool isChain:
        AudioPlugins.profiles.some(p => p.name === (rowRoot.row?.name ?? ""))

    implicitHeight: 54
    radius: Appearance.rounding.small
    color: rowHov.hovered ? Qt.alpha(Appearance.colors.colOnLayer0, 0.06) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }
    // Apps with no stream are listed, just visibly quieter.
    opacity: rowRoot.live ? 1 : 0.55

    // Needed so node.audio / properties are populated.
    PwObjectTracker { objects: rowRoot.node ? [rowRoot.node] : [] }

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

        // A chain's output is a stream but not an app; a guessed desktop icon
        // made it look like something installed.
        MaterialSymbol {
            visible: rowRoot.isChain
            Layout.preferredWidth: 26
            horizontalAlignment: Text.AlignHCenter
            text: "graphic_eq"
            iconSize: 22
            color: Appearance.colors.colPrimary
        }
        Image {
            visible: !rowRoot.isChain && source != ""
            Layout.alignment: Qt.AlignVCenter
            // sourceSize only sets the decode size; without a layout size the
            // Image still claims the icon file's natural size and some themes
            // ship those at 48px+.
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26
            fillMode: Image.PreserveAspectFit
            sourceSize.width: 52
            sourceSize.height: 52
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
                spacing: 6

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: rowRoot.row?.name ?? ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: rowRoot.node?.audio?.muted
                        ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer0
                }

                // Where it plays. Only a live stream has a destination.
                StyledText {
                    visible: rowRoot.showRouting
                    Layout.maximumWidth: 130
                    elide: Text.ElideRight
                    text: {
                        if (!rowRoot.live) return Translation.tr("Silent");
                        if (AudioPlugins.isRoutePending(rowRoot.node)) return Translation.tr("Routing…");
                        const dest = Audio.sinkForStream(rowRoot.node?.id);
                        return dest.length > 0 ? dest : Translation.tr("Automatic");
                    }
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }

                // Mode chip - click cycles Always -> On workspace -> When focused.
                Rectangle {
                    visible: rowRoot.live && !rowRoot.showRouting
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

            // Live level runs inside the slider's own track. Peak is scaled by
            // the volume so a quiet stream reads quiet.
            StyledSlider {
                Layout.fillWidth: true
                from: 0
                to: 1
                value: AppVolumes.volumeFor(rowRoot.row)
                onMoved: AppVolumes.setVolume(rowRoot.row, value)
                level: rowRoot.live
                    ? Math.min(1, peakMon.peak * (rowRoot.node?.audio?.volume ?? 1)) : -1
            }
        }

        // Change where it plays. Needs a real stream to move.
        RippleButton {
            visible: rowRoot.showRouting && rowRoot.live
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 28
            implicitHeight: 28
            buttonRadius: Appearance.rounding.full
            onClicked: rowRoot.routeRequested()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "call_split"
                iconSize: 16
                color: Appearance.colors.colOnLayer0
            }
            StyledToolTip { text: Translation.tr("Send this app somewhere else") }
        }

        // Quick mute - needs a real stream to act on.
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
