pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io

Item {
    id: root
    required property string path
    required property string filter
    required property string mode
    required property string extractTo
    property string label: ""

    property var  files: []
    property bool loading: true
    property bool watching: false

    // ── File scanning ─────────────────────────────────────────────────────
    Process {
        id: scanProc
        stdout: StdioCollector { onStreamFinished: {
            root.loading = false
            const lines = text.trim().split("\n").filter(l => l.trim())
            root.files = lines.map(l => {
                const parts = l.split("|")
                return {
                    path:    parts[0] ?? "",
                    name:    (parts[0] ?? "").split("/").pop(),
                    size:    root._fmtSize(parseInt(parts[1]) || 0),
                    mtime:   parseInt(parts[2]) || 0,
                    timeAgo: root._timeAgo(parseInt(parts[2]) || 0)
                }
            }).filter(f => f.path !== "")
        }}
    }

    Process {
        id: watchProc
        stdout: SplitParser {
            onRead: line => {
                const parts = line.trim().split(" ")
                if (parts[0] && parts[1]) root._onFsEvent(parts[0], parts[1])
            }
        }
    }

    function startWatch() {
        if (watching) return
        watching = true
        watchProc.exec({ command: ["bash", "-c",
            `inotifywait -m --format "%e %f" -e create,delete,moved_to,moved_from,close_write "${root.path}" 2>/dev/null`
        ]})
    }

    function scan() {
        loading = true
        const exts = filter.split(",").map(e => e.trim()).filter(e => e)
        const findParts = exts.map(e => `-iname "*.${e}"`).join(" -o ")
        const findExpr = exts.length > 1 ? `\\( ${findParts} \\)` : findParts
        scanProc.exec({ command: ["bash", "-c",
            `find "${root.path}" -maxdepth 1 -type f ${findExpr} -printf "%p|%s|%T@\\n" 2>/dev/null | sort -t"|" -k3 -rn | head -100`
        ]})
    }

    function _onFsEvent(event, fname) { rescanTimer.restart() }

    Timer { id: rescanTimer; interval: 600; repeat: false; onTriggered: root.scan() }

    function _fmtSize(bytes) {
        if (bytes < 1024) return bytes + " B"
        if (bytes < 1048576) return Math.round(bytes / 1024) + " KB"
        return (bytes / 1048576).toFixed(1) + " MB"
    }

    function _timeAgo(epoch) {
        const diff = Math.floor(Date.now() / 1000) - epoch
        if (diff < 60)    return "now"
        if (diff < 3600)  return Math.floor(diff / 60) + "m"
        if (diff < 86400) return Math.floor(diff / 3600) + "h"
        return Math.floor(diff / 86400) + "d"
    }

    Component.onCompleted: { scan(); startWatch() }
    Component.onDestruction: { watchProc.exec({ command: ["bash", "-c", "true"] }) }

    // ── UI ────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Toolbar strip
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 12; Layout.rightMargin: 8
            Layout.topMargin: 6; Layout.bottomMargin: 4
            spacing: 6

            StyledText {
                text: root.label !== "" ? root.label : root.path
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer0
                opacity: 0.4
                elide: Text.ElideLeft
                Layout.fillWidth: true
            }

            StyledText {
                text: root.files.length + " files"
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer0
                opacity: 0.3
                visible: !root.loading && root.files.length > 0
            }

            Rectangle {
                implicitWidth: 24; implicitHeight: 24; radius: 12; color: "transparent"
                HoverHandler { id: refreshHov }
                TapHandler { onTapped: root.scan() }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0
                    opacity: refreshHov.hovered ? 0.8 : 0.35
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    RotationAnimation on rotation {
                        running: root.loading
                        loops: Animation.Infinite; from: 0; to: 360; duration: 900
                    }
                }
            }
        }

        // Horizontal file list
        ListView {
            id: listView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.bottomMargin: 8
            orientation: ListView.Horizontal
            clip: true
            spacing: 6
            model: root.files
            cacheBuffer: 300  // was 800
            reuseItems: false

            ScrollBar.horizontal: ScrollBar {
                policy: ScrollBar.AsNeeded
                height: 4
            }

            delegate: root.mode === "zip" ? zipDelegate : audioDelegate

            Component {
                id: zipDelegate
                ShelfZipCard {
                    required property var modelData
                    height: listView.height - 4
                    filePath:  modelData.path
                    fileName:  modelData.name
                    fileSize:  modelData.size
                    timeAgo:   modelData.timeAgo
                    extractTo: root.extractTo
                }
            }

            Component {
                id: audioDelegate
                ShelfAudioCard {
                    required property var modelData
                    height: listView.height - 4
                    filePath: modelData.path
                    fileName: modelData.name
                }
            }

            // Empty state
            Item {
                anchors.fill: parent
                visible: !root.loading && root.files.length === 0
                ColumnLayout {
                    anchors.centerIn: parent; spacing: 6
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "folder_open"; iconSize: 28
                        color: Appearance.colors.colOnLayer0; opacity: 0.12
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("No files")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer0; opacity: 0.25
                    }
                }
            }
        }
    }
}
