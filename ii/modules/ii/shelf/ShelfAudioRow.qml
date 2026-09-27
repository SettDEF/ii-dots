pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Rectangle {
    id: root
    required property string filePath
    required property string fileName
    property string duration: ""
    readonly property bool isPlaying: ShelfPlayer.isPlaying && ShelfPlayer.currentPath === root.filePath

    implicitHeight: rowContent.implicitHeight + 14
    radius: Appearance.rounding.small
    color: dragHandler.active
        ? Appearance.colors.colPrimaryContainer
        : (playHov.hovered || dragHov.hovered)
            ? Appearance.colors.colLayer2
            : ColorUtils.transparentize(Appearance.colors.colLayer2)
    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

    // ── Drag ─────────────────────────────────────────────────────────────
    Drag.active: dragHandler.active
    Drag.dragType: Drag.Automatic
    Drag.mimeData: ({ "text/uri-list": "file://" + root.filePath })
    Drag.onDragStarted: root.isPlaying = false

    DragHandler {
        id: dragHandler
        onActiveChanged: if (active) root.grabToImage(result => { root.Drag.imageSource = result.url })
    }

    // ── Duration loader ───────────────────────────────────────────────────
    Process {
        id: durationProc
        stdout: StdioCollector {
            onStreamFinished: {
                const secs = parseFloat(text.trim())
                if (!isNaN(secs) && secs > 0) {
                    const m = Math.floor(secs / 60)
                    const s = Math.floor(secs % 60)
                    root.duration = `${m}:${String(s).padStart(2, "0")}`
                }
            }
        }
    }

    function togglePlay() { ShelfPlayer.toggle(root.filePath) }

    Component.onCompleted: {
        durationProc.exec({ command: ["bash", "-c",
            `ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${root.filePath}" 2>/dev/null || echo 0`] })
    }

    // ── Layout ────────────────────────────────────────────────────────────
    RowLayout {
        id: rowContent
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 8; rightMargin: 8 }
        spacing: 8

        // Play button
        Rectangle {
            id: playBtn
            implicitWidth: 28; implicitHeight: 28; radius: 14
            color: root.isPlaying ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            HoverHandler { margin: Appearance.sizes.touchSlop; id: playHov }
            TapHandler { margin: Appearance.sizes.touchSlop; onTapped: root.togglePlay() }
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.isPlaying ? "stop" : "play_arrow"
                iconSize: Appearance.font.pixelSize.small
                color: root.isPlaying ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }
        }

        // File name
        StyledText {
            Layout.fillWidth: true
            text: root.fileName
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer0
            elide: Text.ElideRight
        }

        // Duration
        StyledText {
            text: root.duration
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer0
            opacity: 0.4
            visible: root.duration !== ""
            Layout.preferredWidth: 36
            horizontalAlignment: Text.AlignRight
        }

        // Drag handle
        Item {
            id: dragHandle
            implicitWidth: 28; implicitHeight: 28
            HoverHandler { margin: Appearance.sizes.touchSlop; id: dragHov }

            Column {
                anchors.centerIn: parent
                spacing: 3
                Repeater {
                    model: 3
                    Rectangle {
                        width: 16; height: 2; radius: 1
                        color: dragHov.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                        opacity: dragHov.hovered ? 1 : 0.25
                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }
                }
            }
        }
    }
}
