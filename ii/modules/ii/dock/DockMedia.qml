pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs.modules.common.models
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item {
    id: root

    property real cardWidth:     240
    property real buttonPadding: 5
    property real artMargin:     5
    /// One size for every transport button, here and in the expansion. They
    /// were 26 and 28 in three places and the mismatch showed.
    readonly property real transportSize: 28
    /// Matches DockAppButton.iconSize so the card sits level with the icons.
    property real artSize:       35

    // position only changes when the player emits it; nudge it while playing.
    Timer {
        running: root.player?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: root.player?.positionChanged()
    }

    property var player: MprisController.activePlayer

    // Hover expansion: grows upward in a popup, so the dock never resizes.
    readonly property bool expandEnabled: (Config.options?.dock.mediaExpandOnHover ?? false)
    // Not while editing — it grows into the edit panel's pixels.
    readonly property bool wantExpansion: root.expandEnabled && root.hasTrack
        && !GlobalStates.dockEditMode
        && (cardHover.hovered || (expansionLoader.item?.hovered ?? false))
    property bool showExpansion: false
    /// Animated, so the corners open with the panel instead of snapping.
    property real cardTopRadius: root.showExpansion ? 0 : Appearance.rounding.normal
    Behavior on cardTopRadius {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    /// Keeps the dock revealed while the card is broken out of it.
    readonly property bool requestDockShow: root.showExpansion

    Timer {
        interval: root.wantExpansion ? 130 : 170
        running: root.wantExpansion !== root.showExpansion
        onTriggered: root.showExpansion = root.wantExpansion
    }

    // Loader-gated: a bad popup size is a fatal Wayland error that kills the
    // shell, so with the setting off it is never constructed.
    Loader {
        id: expansionLoader
        active: root.expandEnabled && root.hasTrack
        sourceComponent: DockMediaExpansion {
            media: root
            cardItem: card
        }
    }

    property var    artUrl:      player?.trackArtUrl ?? ""
    property string trackTitle:  player?.trackTitle  ?? ""
    property string trackArtist: player?.trackArtist ?? ""
    property bool   isPlaying:   player?.isPlaying   ?? false
    property bool   hasTrack:    trackTitle.length > 0

    readonly property real trackLength: player?.length ?? 0
    readonly property real trackPos: player?.position ?? 0
    /// A live stream has no fixed end. Browsers report mpris:length as
    /// INT64_MAX (~292000 years) for one; quickshell clamps that to the
    /// position, so both forms are checked — plus no length at all.
    readonly property bool isLive: root.hasTrack && (
        root.trackLength <= 0
        || root.trackLength > 86400                    // the INT64_MAX sentinel
        || (root.trackLength - root.trackPos) < 1.5)   // ...or clamped to position

    property string artDownloadLocation: Directories.coverArt
    property string artFileName:         Qt.md5(artUrl)
    property string artFilePath:         `${artDownloadLocation}/${artFileName}`
    property bool   artDownloaded:       false

    property string displayedArtFilePath: {
        if (!root.artDownloaded) return ""
        if (root.artUrl.startsWith("file://")) return root.artUrl
        return Qt.resolvedUrl(artFilePath)
    }

    property color artDominantColor: ColorUtils.mix(
        colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary,
        Appearance.colors.colPrimaryContainer,
        0.8)

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: root.artDominantColor
    }

    onArtFilePathChanged: {
        if (!root.artUrl || root.artUrl.length === 0) {
            root.artDominantColor = Appearance.m3colors.m3secondaryContainer
            root.artDownloaded = false
            return
        }

        if (root.artUrl.startsWith("file://")) {
            root.artDownloaded = true
            return
        }

        artDownloader.targetFile  = root.artUrl
        artDownloader.artFilePath = root.artFilePath
        root.artDownloaded = false
        artDownloader.running = true
    }

    Process {
        id: artDownloader
        property string targetFile:  root.artUrl
        property string artFilePath: root.artFilePath
        command: ["bash", "-c",
            `[ -f ${artFilePath} ] || curl -sSL '${targetFile}' -o '${artFilePath}'`]
        onExited: { root.artDownloaded = true }
    }

    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0
        rescaleSize: 1
    }

    visible:        root.hasTrack
    implicitWidth:  root.hasTrack ? root.cardWidth : 0
    implicitHeight: parent?.height ?? 46

    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    StyledRectangularShadow {
        target: card
    }

    Rectangle {
        id: card
        anchors.fill:         parent
        anchors.topMargin:    Appearance.sizes.hyprlandGapsOut
        anchors.bottomMargin: Appearance.sizes.hyprlandGapsOut
        anchors.leftMargin:   Appearance.sizes.hyprlandGapsOut
        anchors.rightMargin:  Appearance.sizes.hyprlandGapsOut - 2
        radius: Appearance.rounding.normal
        color:  "transparent"

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width:  card.width
                height: card.height
                // Square on top while the expansion sits there.
                topLeftRadius:     root.cardTopRadius
                topRightRadius:    root.cardTopRadius
                bottomLeftRadius:  card.radius
                bottomRightRadius: card.radius
            }
        }

        HoverHandler { id: cardHover }

        // Shared with the expansion so the two read as one surface.
        MediaCardSurface {
            anchors.fill: parent
            art: root.displayedArtFilePath
            colors: root.blendedColors
            z: 0
        }

        RowLayout {
            width:  card.width
            height: card.height
            clip:   true
            spacing: 8
            z: 3

            // Sized to match an app icon, not the card.
            MediaArtwork {
                Layout.alignment:  Qt.AlignVCenter
                Layout.leftMargin: root.artMargin + 2
                size:    root.artSize
                source:  root.displayedArtFilePath
                seed:    String(root.trackTitle) + String(root.trackArtist)
                accent:  root.blendedColors.colPrimary
                surface: root.blendedColors.colLayer1
            }

            // Artist + Title
            ColumnLayout {
                Layout.fillWidth:  true
                Layout.fillHeight: true
                spacing: -2

                Item { Layout.fillHeight: true }

                StyledText {
                    Layout.fillWidth: true
                    text: root.trackArtist
                    font.pixelSize: Appearance.font.pixelSize.small - 2
                    color: root.blendedColors.colSubtext
                    elide: Text.ElideRight
                }

                readonly property string cleanTitle: StringUtils.cleanMusicTitle(root.trackTitle) ?? ""

                StyledText {
                    visible: parent.cleanTitle.length > 0
                    Layout.fillWidth: true
                    text: parent.cleanTitle
                    font.pixelSize: Appearance.font.pixelSize.normal - 4
                    color: root.blendedColors.colOnLayer0
                    elide: Text.ElideRight
                    opacity: 0.7
                }

                // Some players publish no title; show position instead.
                RowLayout {
                    visible: parent.cleanTitle.length === 0
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 5

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 3
                        radius: Appearance.rounding.full
                        color: ColorUtils.transparentize(root.blendedColors.colOnLayer0, 0.75)

                        Rectangle {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            // Live streams report length 0 — guard the divide.
                            width: (root.player?.length ?? 0) > 0
                                ? parent.width * Math.max(0, Math.min(1, root.player.position / root.player.length))
                                : 0
                            radius: parent.radius
                            color: root.blendedColors.colOnLayer0
                        }
                    }

                    StyledText {
                        text: StringUtils.friendlyTimeForSeconds(root.player?.position ?? 0)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.monospace
                        color: root.blendedColors.colSubtext
                    }
                }

                Item { Layout.fillHeight: true }
            }

            // Buttons
            RowLayout {
                Layout.rightMargin: 4
                Layout.alignment:   Qt.AlignVCenter
                spacing: 3

                // Play / Pause
                RippleButton {
                    implicitWidth:  root.transportSize
                    implicitHeight: root.transportSize
                    buttonRadius: root.isPlaying
                        ? Appearance.rounding.normal
                        : implicitWidth / 2
                    colBackground: root.isPlaying
                        ? root.blendedColors.colPrimary
                        : root.blendedColors.colSecondaryContainer
                    colBackgroundHover: root.isPlaying
                        ? root.blendedColors.colPrimaryHover
                        : root.blendedColors.colSecondaryContainerHover
                    colRipple: root.isPlaying
                        ? root.blendedColors.colPrimaryActive
                        : root.blendedColors.colSecondaryContainerActive
                    downAction: () => root.player?.togglePlaying()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: root.isPlaying ? "pause" : "play_arrow"
                        iconSize: Appearance.font.pixelSize.large
                        fill: 1
                        color: root.isPlaying
                            ? root.blendedColors.colOnPrimary
                            : root.blendedColors.colOnSecondaryContainer
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }

                // Next
                RippleButton {
                    implicitWidth:  root.transportSize
                    implicitHeight: root.transportSize
                    buttonRadius: implicitWidth / 2
                    colBackground:      ColorUtils.transparentize(root.blendedColors.colSecondaryContainer, 1)
                    colBackgroundHover: root.blendedColors.colSecondaryContainerHover
                    colRipple:          root.blendedColors.colSecondaryContainerActive
                    downAction: () => root.player?.next()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "skip_next"
                        iconSize: Appearance.font.pixelSize.large
                        fill: 1
                        color: root.blendedColors.colOnSecondaryContainer
                    }
                }
            }
        }
    }
}
