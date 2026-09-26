// The part of the now-playing card that grows out of the dock.
//
// Its own PopupWindow, because the dock's layer surface is exactly as tall as
// the dock — anything above it is clipped, and a taller window would drag
// exclusiveZone and the reveal mask along.
//
// The window is a fixed size and only the panel inside grows: a window resize
// cannot be animated. The panel is bottom-anchored, clipped, and carries no
// artwork or title — repeating what is already on the card made it read as
// two cards.
pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import Qt5Compat.GraphicalEffects
import QtQuick.Layouts
import Quickshell

PopupWindow {
    id: root

    /// The DockMedia this grows out of.
    required property var media
    /// The card Item inside it, which this aligns to exactly.
    required property Item cardItem

    readonly property var player: root.media?.player ?? null

    // Named roles, resolved once. These used to be inlined with "white"/"grey"
    // fallbacks — literal colours that ignore the theme and never retint.
    readonly property color colText: root.colors?.colOnLayer0 ?? Appearance.colors.colOnLayer0
    readonly property color colSub: root.colors?.colSubtext ?? Appearance.colors.colSubtext
    readonly property color colAccent: root.colors?.colPrimary ?? Appearance.colors.colPrimary
    readonly property color colChip: root.colors?.colSecondaryContainer ?? Appearance.colors.colSecondaryContainer
    readonly property color colChipHover: root.colors?.colSecondaryContainerHover ?? Appearance.colors.colSecondaryContainerHover
    readonly property color colChipActive: root.colors?.colSecondaryContainerActive ?? Appearance.colors.colSecondaryContainerActive
    readonly property color colOnChip: root.colors?.colOnSecondaryContainer ?? Appearance.colors.colOnSecondaryContainer
    readonly property QtObject colors: root.media?.blendedColors ?? null
    readonly property real grownHeight: Math.max(1, Config.options?.dock.mediaExpandedHeight ?? 44)
    property alias hovered: hoverArea.containsMouse

    color: "transparent"

    /// Zero while the dock builds. A zero-sized popup is a fatal Wayland
    /// error that kills the shell, so never map until it is real.
    readonly property real hostWidth: root.cardItem?.QsWindow?.window?.width ?? 0

    // Present whenever there is a card to grow from; the panel's height is
    // what actually opens and closes.
    visible: (root.media?.hasTrack ?? false) && root.cardItem !== null
             && (Config.options?.dock.mediaExpandOnHover ?? false)
             && root.hostWidth > 0 && root.grownHeight > 0

    // Only the drawn part takes input.
    mask: Region { item: panel }

    // Full dock width, panel placed inside at the card's x.
    anchor {
        window: root.cardItem ? root.cardItem.QsWindow.window : null
        gravity: Edges.Top | Edges.Right
        edges: Edges.Top | Edges.Left
        adjustment: PopupAdjustment.None
        // Measured: rect.y places the popup's BOTTOM, so the card's top edge
        // is the value that makes the two meet.
        rect: Qt.rect(0, root.cardTop, 1, 1)
    }

    implicitWidth: Math.max(1, root.hostWidth)
    implicitHeight: Math.max(1, root.grownHeight)

    // mapFromItem() is a call, not a dependency, so this latches. The tick
    // re-syncs it while the dock slides in.
    property int _tick: 0
    Timer {
        // Only while actually open. Bound to `visible` this ran 10x/second for
        // as long as anything was playing, since the window stays mapped.
        running: root.media?.showExpansion ?? false
        interval: 100
        repeat: true
        onTriggered: root._tick++
    }
    readonly property point cardOrigin: {
        root._tick;
        root.media?.showExpansion;
        root.hostWidth;
        if (!root.cardItem || !root.cardItem.QsWindow?.window) return Qt.point(0, 0);
        return root.cardItem.QsWindow.mapFromItem(root.cardItem, 0, 0);
    }
    readonly property real cardX: root.cardOrigin.x
    /// How far the card's top sits below the dock window's own top edge.
    readonly property real cardTop: root.cardOrigin.y

    Rectangle {
        id: panel
        x: root.cardX
        width: root.cardItem?.width ?? 0
        anchors.bottom: parent.bottom
        // The one animated dimension. Bottom-anchored, so it grows upward.
        // Never zero — a bad size under the mask is fatal to the shell.
        implicitHeight: (root.media?.showExpansion ?? false) ? root.grownHeight : 1
        opacity: (root.media?.showExpansion ?? false) ? 1 : 0
        // Without this the panel blinks out and the height animation is
        // never seen on leave.
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        visible: opacity > 0
        height: implicitHeight
        clip: true
        radius: Appearance.rounding.normal
        color: "transparent"

        Behavior on implicitHeight {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        // Square at the bottom so it meets the card with no seam.
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: panel.width
                height: Math.max(1, panel.height)
                topLeftRadius: panel.radius
                topRightRadius: panel.radius
                bottomLeftRadius: 0
                bottomRightRadius: 0
            }
        }

        // Same surface as the card.
        MediaCardSurface {
            anchors.fill: parent
            art: root.media?.displayedArtFilePath ?? ""
            colors: root.colors
        }

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        // Bottom-anchored, so it slides out instead of being squashed.
        RowLayout {
            anchors {
                left: parent.left; right: parent.right; bottom: parent.bottom
                leftMargin: 6; rightMargin: 6; bottomMargin: 0
            }
            height: root.grownHeight
            spacing: 4

            RippleButton {
                implicitWidth: root.media?.transportSize ?? 28
                implicitHeight: root.media?.transportSize ?? 28
                buttonRadius: Appearance.rounding.full
                colBackground: ColorUtils.transparentize(root.colChip, 1)
                colBackgroundHover: root.colChipHover
                colRipple: root.colChipActive
                downAction: () => root.player?.previous()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "skip_previous"
                    iconSize: Appearance.font.pixelSize.large
                    fill: 1
                    color: root.colOnChip
                }
            }

            // Hidden when live: a stream has no position and no length, so both
            // labels read 0:00 and frame the LIVE badge with noise.
            StyledText {
                visible: !(root.media?.isLive ?? false)
                text: StringUtils.friendlyTimeForSeconds(root.player?.position ?? 0)
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.monospace
                color: root.colSub
            }

            Item {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 16

                // Live: there is nothing to seek through, and a full bar read
                // as a finished track.
                Loader {
                    anchors.centerIn: parent
                    active: root.media?.isLive ?? false
                    sourceComponent: RowLayout {
                        spacing: 5
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 7
                            implicitHeight: 7
                            radius: Appearance.rounding.full
                            color: Appearance.m3colors.m3error
                            SequentialAnimation on opacity {
                                // Only while the panel is open. Ungated, this
                                // repainted the popup every frame for the whole
                                // length of a live stream.
                                running: root.media?.showExpansion ?? false
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutQuad }
                                NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
                            }
                        }
                        StyledText {
                            text: Translation.tr("LIVE")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: root.colText
                        }
                    }
                }

                // Draggable if the player allows it, else a plain bar.
                Loader {
                    anchors.fill: parent
                    active: !(root.media?.isLive ?? false) && (root.player?.canSeek ?? false)
                    sourceComponent: StyledSlider {
                        highlightColor: root.colAccent
                        trackColor: root.colChip
                        handleColor: root.colAccent
                        value: (root.player?.length ?? 0) > 0
                            ? Math.max(0, Math.min(1, root.player.position / root.player.length)) : 0
                        onMoved: if ((root.player?.length ?? 0) > 0)
                            root.player.position = value * root.player.length
                    }
                }
                Loader {
                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; right: parent.right }
                    active: !(root.media?.isLive ?? false) && !(root.player?.canSeek ?? false)
                    sourceComponent: Rectangle {
                        implicitHeight: 3
                        radius: Appearance.rounding.full
                        color: ColorUtils.transparentize(root.colText, 0.75)
                        Rectangle {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: (root.player?.length ?? 0) > 0
                                ? parent.width * Math.max(0, Math.min(1, root.player.position / root.player.length))
                                : 0
                            radius: parent.radius
                            color: root.colText
                        }
                    }
                }
            }
            StyledText {
                visible: !(root.media?.isLive ?? false)
                text: StringUtils.friendlyTimeForSeconds(root.player?.length ?? 0)
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.monospace
                color: root.colSub
            }

        }
    }
}
