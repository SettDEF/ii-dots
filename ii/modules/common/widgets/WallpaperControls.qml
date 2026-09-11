pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions

/**
 * Wallpaper-hub controls: source icons, media-type tabs, favourites, filter
 * and refresh. Defined once and used by both the launcher's SearchBar and
 * skwd's fallback toolbar; all state lives in WallpaperHub.
 *
 * Drop it into a RowLayout.
 */
RowLayout {
    id: root
    spacing: 6

    // Which part to draw, so a bar can sit its input between two groups of
    // similar width: "left" = sources, "right" = media tabs + actions,
    // "all" = everything. Split by visual weight, not category.
    property string half: "all"
    readonly property bool showSources: root.half !== "right"
    readonly property bool showActions: root.half !== "left"

    // Slightly smaller geometry for tighter bars.
    property bool compact: false
    readonly property real pillHeight: root.compact ? 34 : 40
    readonly property real cellSize: root.compact ? 30 : 36

    // ── Source icons (local / wallhaven / reddit / videos) ────────────
    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        visible: root.showSources
        implicitWidth: sourceRow.implicitWidth + 8
        implicitHeight: root.pillHeight
        radius: height / 2
        color: ColorUtils.transparentize(Appearance.colors.colSurfaceContainerHigh, 0.5)
        Row {
            id: sourceRow
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                model: WallpaperHub.sources
                delegate: Rectangle {
                    id: srcCell
                    required property var modelData
                    readonly property bool active: WallpaperHub.source === modelData.id
                    width: root.cellSize; height: root.cellSize; radius: width / 2
                    color: srcCell.active ? Appearance.colors.colPrimary
                        : (srcHov.hovered ? Appearance.colors.colSurfaceContainerHighest : "transparent")
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: srcCell.modelData.icon
                        iconSize: root.compact ? 18 : 21
                        color: srcCell.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                    }
                    HoverHandler { id: srcHov }
                    TapHandler { onTapped: WallpaperHub.source = srcCell.modelData.id }
                    StyledToolTip { text: srcCell.modelData.label }
                }
            }
        }
    }

    // ── Media-type tabs (ALL / PIC / VID / WE) ────────────────────────
    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        visible: root.showActions
        implicitWidth: mediaRow.implicitWidth + 8
        implicitHeight: root.pillHeight
        radius: height / 2
        color: ColorUtils.transparentize(Appearance.colors.colSurfaceContainerHigh, 0.5)
        Row {
            id: mediaRow
            anchors.centerIn: parent
            spacing: 1
            Repeater {
                model: WallpaperHub.mediaTypes
                delegate: Rectangle {
                    id: mtCell
                    required property var modelData
                    readonly property bool active: WallpaperHub.mediaType === modelData.id
                    implicitWidth: mtText.implicitWidth + (root.compact ? 16 : 22)
                    height: root.cellSize
                    radius: height / 2
                    color: mtCell.active ? Appearance.colors.colPrimary
                        : (mtHov.hovered ? Appearance.colors.colSurfaceContainerHighest : "transparent")
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                    StyledText {
                        id: mtText
                        anchors.centerIn: parent
                        text: mtCell.modelData.label
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: mtCell.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                    }
                    HoverHandler { id: mtHov }
                    TapHandler { onTapped: WallpaperHub.mediaType = mtCell.modelData.id }
                }
            }
        }
    }

    // ── Favourites only ───────────────────────────────────────────────
    IconToolbarButton {
        Layout.alignment: Qt.AlignVCenter
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        visible: root.showActions
        toggled: WallpaperHub.favoritesOnly
        text: WallpaperHub.favoritesOnly ? "favorite" : "favorite_border"
        onClicked: WallpaperHub.favoritesOnly = !WallpaperHub.favoritesOnly
        colText: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
        StyledToolTip { text: Translation.tr("Favourites only") }
    }

    // ── Details drawer (image info + post) ────────────────────────────
    IconToolbarButton {
        Layout.alignment: Qt.AlignVCenter
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        visible: root.showActions
        toggled: WallpaperHub.detailsOpen
        text: "info"
        onClicked: WallpaperHub.detailsOpen = !WallpaperHub.detailsOpen
        colText: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
        StyledToolTip { text: Translation.tr("Image info & post") }
    }

    // ── Filter (sort chips) + refresh ─────────────────────────────────
    IconToolbarButton {
        Layout.alignment: Qt.AlignVCenter
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        visible: root.showActions
        toggled: WallpaperHub.filterOpen
        text: "filter_list"
        onClicked: WallpaperHub.filterOpen = !WallpaperHub.filterOpen
        colText: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
        StyledToolTip { text: Translation.tr("Filter / sort") }
    }
    IconToolbarButton {
        Layout.alignment: Qt.AlignVCenter
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        visible: root.showActions
        text: "refresh"
        onClicked: WallpaperHub.reload()
        colText: Appearance.colors.colOnSurfaceVariant
        StyledToolTip { text: Translation.tr("Refresh") }
    }
}
