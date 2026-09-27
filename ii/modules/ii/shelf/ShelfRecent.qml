pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import QtQuick.Controls

Item {
    id: root

    property var entries: []
    property bool loading: false

    Component.onCompleted: scan()

    Process {
        id: scanProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false
                const lines = text.trim().split("\n").filter(l => l.trim())
                root.entries = lines.map(l => {
                    const p = l.split("\t")
                    return {
                        path:  p[0] ?? "",
                        name:  (p[0] ?? "").split("/").pop(),
                        mtime: parseInt(p[1]) || 0,
                        size:  _fmtSize(parseInt(p[2]) || 0),
                    }
                }).filter(e => e.name !== "")
            }
        }
    }

    function scan() {
        loading = true
        entries = []
        // Recent files: find across home, sorted by modification time, skip hidden
        scanProc.exec({ command: ["bash", "-c",
            `find "$HOME" -maxdepth 4 -type f ! -path "*/.*" ! -path "*/node_modules/*" ! -path "*/__pycache__/*" -printf "%p\\t%T@\\t%s\\n" 2>/dev/null | sort -t$'\\t' -k2 -rn | head -60`
        ]})
    }

    function _fmtSize(bytes) {
        if (bytes < 1024)    return bytes + " B"
        if (bytes < 1048576) return Math.round(bytes / 1024) + " KB"
        return (bytes / 1048576).toFixed(1) + " MB"
    }

    function _timeAgo(epoch) {
        const diff = Math.floor(Date.now() / 1000) - epoch
        if (diff < 60)    return qsTr("now")
        if (diff < 3600)  return Math.floor(diff / 60) + "m"
        if (diff < 86400) return Math.floor(diff / 3600) + "h"
        return Math.floor(diff / 86400) + "d"
    }

    function _fileIcon(name) {
        const ext = (name.split(".").pop() ?? "").toLowerCase()
        if (["mp3","wav","flac","aiff","aif","ogg","m4a"].includes(ext)) return "audio_file"
        if (["zip","rar","7z","tar","gz"].includes(ext))                 return "folder_zip"
        if (["jpg","jpeg","png","gif","webp","svg","xcf"].includes(ext)) return "image"
        if (["pdf"].includes(ext))                                        return "picture_as_pdf"
        if (["mp4","mkv","mov","avi","webm"].includes(ext))              return "movie"
        if (["txt","md","conf","json","toml","yaml"].includes(ext))      return "text_snippet"
        return "draft"
    }

    function _isAudio(name) {
        const ext = (name.split(".").pop() ?? "").toLowerCase()
        return ["mp3","wav","flac","aiff","aif","ogg","m4a"].includes(ext)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Toolbar
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8; Layout.rightMargin: 8
            Layout.topMargin: 6; Layout.bottomMargin: 4

            StyledText {
                text: qsTr("Recently modified")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer0
                opacity: 0.4
                Layout.fillWidth: true
            }

            Rectangle {
                implicitWidth: 26; implicitHeight: 26; radius: 13
                color: refreshHov.hovered ? Appearance.colors.colLayer2 : ColorUtils.transparentize(Appearance.colors.colLayer2)
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                HoverHandler { margin: Appearance.sizes.touchSlop; id: refreshHov }
                TapHandler { margin: Appearance.sizes.touchSlop; onTapped: root.scan() }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0
                    opacity: refreshHov.hovered ? 0.8 : 0.35
                    RotationAnimation on rotation {
                        running: root.loading
                        loops: Animation.Infinite; from: 0; to: 360; duration: 900
                    }
                }
            }
        }

        ListView {
            id: recentList
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 4
            Layout.rightMargin: 6
            Layout.bottomMargin: 6
            clip: true
            spacing: 1
            model: root.entries

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Item {
                required property var modelData
                width: recentList.width
                implicitHeight: 34

                readonly property bool isAudio: root._isAudio(modelData.name)
                readonly property bool isPlaying: isAudio && ShelfPlayer.isPlaying
                    && ShelfPlayer.currentPath === modelData.path

                Drag.active: dragH.active
                Drag.dragType: Drag.Automatic
                Drag.mimeData: ({ "text/uri-list": "file://" + modelData.path })
                Drag.onDragStarted: { if (isAudio) ShelfPlayer.stop() }
                DragHandler {
                    id: dragH
                    onActiveChanged: if (active) parent.grabToImage(r => { parent.Drag.imageSource = r.url })
                }

                Rectangle {
                    anchors { fill: parent; rightMargin: 2 }
                    radius: Appearance.rounding.small
                    color: isPlaying
                        ? Qt.alpha(Appearance.colors.colPrimary, 0.12)
                        : (rHov.hovered ? Appearance.colors.colLayer2 : ColorUtils.transparentize(Appearance.colors.colLayer2))
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                    HoverHandler { id: rHov }
                    TapHandler {
                        onTapped: { if (isAudio) ShelfPlayer.toggle(modelData.path) }
                    }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        spacing: 8

                        MaterialSymbol {
                            text: isPlaying ? "graphic_eq" : root._fileIcon(modelData.name)
                            iconSize: Appearance.font.pixelSize.normal
                            color: isPlaying ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                            opacity: isPlaying ? 1 : 0.4
                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.name
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: isPlaying ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                                elide: Text.ElideRight
                                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    const parts = modelData.path.split("/")
                                    return parts.slice(-3, -1).join("/")
                                }
                                font.pixelSize: Appearance.font.pixelSize.smaller - 1
                                color: Appearance.colors.colOnLayer0
                                opacity: 0.28
                                elide: Text.ElideLeft
                            }
                        }

                        StyledText {
                            text: root._timeAgo(modelData.mtime)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer0
                            opacity: 0.28
                        }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: !root.loading && root.entries.length === 0
                ColumnLayout {
                    anchors.centerIn: parent; spacing: 6
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "history"; iconSize: 28
                        color: Appearance.colors.colOnLayer0; opacity: 0.12
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("No recent files")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer0; opacity: 0.25
                    }
                }
            }
        }
    }
}
