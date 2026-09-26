// Image-info and post for the wallpaper skwd currently has focused, drawn in
// the launcher's own dropdown language.
//
// This started life as two bordered panels inside skwd's carousel, which is
// why it first looked out of place here: boxed surfaces with their own
// borders read as skwd furniture, not as a launcher dropdown. The launcher's
// vocabulary is full-width 40px rows — transparent until hovered, 12px side
// margins, a MaterialSymbol lead-in and a DemiBold label — so that is what
// this uses now. Compare the subreddit completion list in SearchWallpapers.
//
// Rows copy their value on click, which is what earns the hover highlight;
// a row that lights up and does nothing is a worse lie than a flat one.
//
// Example
//   WallpaperDetailsPanel {
//       item: WallpaperHub.focusedItem
//       meta: WallpaperHub.focusedMeta
//       onContextMenuRequested: (x, y) => menu.popup(x, y, itemsFor(item))
//   }
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    property var item: null
    property var meta: null
    property var theme: null       // flat tinct {role: hex}
    property real rowHeight: 40

    signal contextMenuRequested(real x, real y)

    implicitHeight: col.implicitHeight

    function formatBytes(n) {
        if (!n || n <= 0) return "—"
        if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB"
        if (n >= 1024)    return (n / 1024).toFixed(0) + " KB"
        return n + " B"
    }

    // Each row carries the icon that makes it scannable without reading the
    // key, the same way the completion list leads with a tag glyph.
    readonly property var rows: {
        const m = root.item
        if (!m) return []
        const mt = root.meta
        const local = (m.path || "").startsWith("/")
        return [
            { icon: "title",       k: qsTr("Title"),      v: m.title || "—" },
            { icon: "public",      k: qsTr("Source"),     v: (m.source || "—")
                + (m.subreddit ? "  ·  r/" + m.subreddit : "") },
            { icon: "category",    k: qsTr("Type"),       v: (m.kind || "pic").toUpperCase() },
            { icon: "aspect_ratio", k: qsTr("Resolution"), v: mt && mt.dims ? mt.dims
                : (local ? "…" : qsTr("(remote)")) },
            { icon: "image",       k: qsTr("Format"),     v: mt && mt.format ? mt.format
                : (local ? "…" : "—") },
            { icon: "database",    k: qsTr("Size"),       v: mt ? root.formatBytes(mt.bytes)
                : (local ? "…" : "—") },
            { icon: "folder",      k: qsTr("Path"),       v: m.path || "—" },
        ]
    }

    readonly property var images: {
        const m = root.item
        if (!m) return []
        if (Array.isArray(m.gallery) && m.gallery.length > 0) return m.gallery
        const one = m.full || m.thumb || ""
        return one.length ? [one] : []
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 2

        // Nothing focused yet — one quiet line rather than an empty box.
        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.topMargin: 6
            Layout.bottomMargin: 6
            visible: root.item === null
            text: qsTr("Focus a wallpaper to see its details")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        // ── Theme this wallpaper would apply ──────────────────────────
        Rectangle {
            id: themeCard
            readonly property var t: root.theme
            visible: root.item !== null
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 4
            Layout.bottomMargin: 6
            Layout.preferredHeight: 52
            radius: Appearance.rounding.small
            color: themeCard.t ? themeCard.t.surfaceContainer : Appearance.colors.colLayer2
            border.width: 1
            border.color: themeCard.t ? themeCard.t.outlineVariant : Appearance.colors.colLayer0Border
            Behavior on color { ColorAnimation { duration: 200 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                spacing: 8
                opacity: themeCard.t ? 1 : 0.5

                MaterialSymbol {
                    text: "palette"
                    iconSize: 18
                    color: themeCard.t ? themeCard.t.primary : Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    text: themeCard.t ? qsTr("Theme preview") : qsTr("Reading colours…")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: themeCard.t ? themeCard.t.onSurface : Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
                Repeater {
                    model: ["secondary", "tertiary", "surfaceBright"]
                    delegate: Rectangle {
                        required property string modelData
                        implicitWidth: 18
                        implicitHeight: 18
                        radius: 9
                        color: themeCard.t ? themeCard.t[modelData] : Appearance.colors.colLayer3
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }
                Rectangle {
                    implicitWidth: sampleText.implicitWidth + 24
                    implicitHeight: 32
                    radius: height / 2
                    color: themeCard.t ? themeCard.t.primary : Appearance.colors.colLayer3
                    TapHandler { onTapped: WallpaperHub.applyFocused() }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    Behavior on color { ColorAnimation { duration: 200 } }
                    StyledText {
                        id: sampleText
                        anchors.centerIn: parent
                        text: qsTr("Apply")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: themeCard.t ? themeCard.t.onPrimary : Appearance.colors.colSubtext
                    }
                }
            }
        }

        Repeater {
            model: root.rows
            delegate: Rectangle {
                id: infoRow
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: root.rowHeight
                radius: Appearance.rounding.small
                color: rowHov.hovered ? Appearance.colors.colLayer2Hover : "transparent"
                Behavior on color { ColorAnimation { duration: 140 } }

                HoverHandler { id: rowHov }
                TapHandler {
                    onTapped: Quickshell.execDetached(["wl-copy", "--", String(infoRow.modelData.v)])
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: (eventPoint) => {
                        if (!root.item) return
                        const g = infoRow.mapToItem(root, eventPoint.position.x, eventPoint.position.y)
                        root.contextMenuRequested(g.x, g.y)
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    MaterialSymbol {
                        text: infoRow.modelData.icon
                        iconSize: 17
                        color: Appearance.colors.colSubtext
                        Layout.alignment: Qt.AlignVCenter
                    }
                    StyledText {
                        text: infoRow.modelData.k
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        Layout.preferredWidth: 78
                        Layout.alignment: Qt.AlignVCenter
                    }
                    StyledText {
                        text: infoRow.modelData.v
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    // Only announced on hover, so the row stays quiet at rest.
                    MaterialSymbol {
                        text: "content_copy"
                        iconSize: 14
                        opacity: rowHov.hovered ? 1 : 0
                        color: Appearance.colors.colSubtext
                        Layout.alignment: Qt.AlignVCenter
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                    }
                }
            }
        }

        // ── Post images ───────────────────────────────────────────────
        // A gallery post gets a strip; a single image needs no strip at all,
        // since the carousel below is already showing it full size.
        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.topMargin: 6
            visible: root.images.length > 1
            text: qsTr("POST · %1 images").arg(root.images.length)
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Bold
            font.letterSpacing: 1.2
            color: Appearance.colors.colPrimary
        }

        ListView {
            id: postStrip
            visible: root.images.length > 1
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 4
            Layout.bottomMargin: 8
            Layout.preferredHeight: 96
            orientation: ListView.Horizontal
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            spacing: 6
            model: root.images

            delegate: Rectangle {
                required property var modelData
                width: 148
                height: postStrip.height
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                clip: true
                Image {
                    anchors.fill: parent
                    source: modelData
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 320
                }
            }
        }
    }
}
