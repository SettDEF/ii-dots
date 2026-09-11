pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Rectangle {
    id: root
    required property string filePath
    required property string fileName
    property string audioDuration: ""

    readonly property bool isPlaying: ShelfPlayer.isPlaying && ShelfPlayer.currentPath === root.filePath

    implicitWidth: 150
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    border.width: 1
    border.color: root.isPlaying
        ? Appearance.colors.colPrimary
        : (cardHov.hovered ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer0Border)
    Behavior on border.color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
    clip: true

    HoverHandler { id: cardHov }

    // ── Drag ─────────────────────────────────────────────────────────────
    Drag.active: dragHandler.active
    Drag.dragType: Drag.Automatic
    Drag.mimeData: ({ "text/uri-list": "file://" + root.filePath })
    Drag.onDragStarted: ShelfPlayer.stop()

    DragHandler {
        id: dragHandler
        onActiveChanged: if (active) root.grabToImage(result => { root.Drag.imageSource = result.url })
    }

    // ── Duration ──────────────────────────────────────────────────────────
    Process {
        id: durationProc
        stdout: StdioCollector {
            onStreamFinished: {
                const secs = parseFloat(text.trim())
                if (!isNaN(secs) && secs > 0) {
                    const m = Math.floor(secs / 60)
                    const s = Math.floor(secs % 60)
                    root.audioDuration = m + ":" + String(s).padStart(2, "0")
                }
            }
        }
    }

    Component.onCompleted: {
        durationProc.exec({ command: ["bash", "-c",
            `ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${root.filePath}" 2>/dev/null || echo 0`] })
    }

    // ── Layout ────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors { fill: parent; margins: 10 }
        spacing: 6

        // Icon / waveform area
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 48
            radius: Appearance.rounding.small
            color: root.isPlaying ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.isPlaying ? "graphic_eq" : "audio_file"
                iconSize: 24
                color: root.isPlaying ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                opacity: root.isPlaying ? 1 : 0.3
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }
        }

        // Filename
        StyledText {
            Layout.fillWidth: true
            text: root.fileName
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
            color: Appearance.colors.colOnLayer0
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }

        Item { Layout.fillHeight: true }

        // Bottom row
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            StyledText {
                text: root.audioDuration
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer0
                opacity: 0.4
                visible: root.audioDuration !== ""
                Layout.fillWidth: true
            }

            Rectangle {
                implicitWidth: 26; implicitHeight: 26; radius: 13
                color: root.isPlaying ? Appearance.colors.colPrimary : (playHov.hovered ? Appearance.colors.colLayer2 : "transparent")
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                HoverHandler { margin: Appearance.sizes.touchSlop; id: playHov }
                TapHandler { margin: Appearance.sizes.touchSlop; onTapped: ShelfPlayer.toggle(root.filePath) }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.isPlaying ? "stop" : "play_arrow"
                    iconSize: Appearance.font.pixelSize.small
                    color: root.isPlaying ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                }
            }

            Item {
                implicitWidth: 20; implicitHeight: 26
                HoverHandler { margin: Appearance.sizes.touchSlop; id: dragHov }
                Column {
                    anchors.centerIn: parent; spacing: 3
                    Repeater {
                        model: 3
                        Rectangle {
                            width: 14; height: 2; radius: 1
                            color: dragHov.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                            opacity: dragHov.hovered ? 0.9 : 0.2
                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }
                    }
                }
            }
        }
    }
}
