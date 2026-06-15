pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import QtQuick.Controls

Item {
    id: root

    readonly property string home: "/home/caesar"

    property string currentPath: home + "/Downloads"
    property var navHistory: []
    property var entries: []
    property bool loading: false

    // Level 3: quick-access locations
    readonly property var quickAccess: [
        { id: "downloads", label: qsTr("Downloads"), path: home + "/Downloads",  icon: "download"    },
        { id: "music",     label: qsTr("Music"),     path: home + "/Music",      icon: "music_note"  },
        { id: "pictures",  label: qsTr("Pictures"),  path: home + "/Pictures",   icon: "image"       },
        { id: "documents", label: qsTr("Documents"), path: home + "/Documents",  icon: "description" },
    ]

    // Which quick-access tab is active (based on currentPath)
    readonly property string activeQuickId: {
        for (const qa of quickAccess) {
            if (currentPath === qa.path || currentPath.startsWith(qa.path + "/"))
                return qa.id
        }
        return ""
    }

    function navigate(path) {
        if (path === currentPath) return
        const h = root.navHistory.slice()
        h.push(currentPath)
        root.navHistory = h
        root.currentPath = path
    }

    function goBack() {
        if (root.navHistory.length === 0) return
        const h = root.navHistory.slice()
        const prev = h.pop()
        root.navHistory = h
        root.currentPath = prev
    }

    onCurrentPathChanged: scan()
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
                        kind:  p[0] ?? "f",
                        name:  p[1] ?? "",
                        path:  root.currentPath.replace(/\/+$/, "") + "/" + (p[1] ?? ""),
                        size:  root._fmtSize(parseInt(p[2]) || 0),
                        mtime: parseInt(p[3]) || 0,
                    }
                }).filter(e => e.name !== "" && !e.name.startsWith("."))
            }
        }
    }

    function scan() {
        root.loading = true
        root.entries = []
        scanProc.exec({ command: ["bash", "-c",
            `find "${root.currentPath}" -maxdepth 1 \\( -type f -o -type d \\) ! -name "." -printf "%y\\t%f\\t%s\\t%T@\\n" 2>/dev/null | sort -t$'\\t' -k1,1r -k2,2`
        ]})
    }

    function _fmtSize(bytes) {
        if (bytes < 1024)    return bytes + " B"
        if (bytes < 1048576) return Math.round(bytes / 1024) + " KB"
        return (bytes / 1048576).toFixed(1) + " MB"
    }

    function _fileIcon(name) {
        const ext = (name.split(".").pop() ?? "").toLowerCase()
        if (["mp3","wav","flac","aiff","aif","ogg","m4a","opus"].includes(ext)) return "audio_file"
        if (["zip","rar","7z","tar","gz","bz2","xz"].includes(ext))             return "folder_zip"
        if (["jpg","jpeg","png","gif","webp","svg","xcf","bmp"].includes(ext))  return "image"
        if (["pdf"].includes(ext))                                               return "picture_as_pdf"
        if (["mp4","mkv","mov","avi","webm"].includes(ext))                     return "movie"
        if (["txt","md","conf","json","ini","toml","yaml"].includes(ext))       return "text_snippet"
        return "draft"
    }

    function _isAudio(name) {
        const ext = (name.split(".").pop() ?? "").toLowerCase()
        return ["mp3","wav","flac","aiff","aif","ogg","m4a","opus"].includes(ext)
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Main content column (header + file list) ─────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

        // ── Header: back + breadcrumb ─────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 8
            Layout.topMargin: 4
            Layout.bottomMargin: 2
            spacing: 2

            Rectangle {
                implicitWidth: 26; implicitHeight: 26; radius: 13
                color: backHov.hovered ? Appearance.colors.colLayer2 : "transparent"
                opacity: root.navHistory.length > 0 ? 1 : 0.22
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                Behavior on opacity { NumberAnimation { duration: 150 } }
                HoverHandler { id: backHov }
                TapHandler {
                    enabled: root.navHistory.length > 0
                    onTapped: root.goBack()
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: {
                    const parts = root.currentPath.split("/").filter(p => p)
                    if (parts.length === 0) return "/"
                    if (parts.length <= 2)  return "/" + parts.join("/")
                    return "…/" + parts.slice(-2).join("/")
                }
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer0
                opacity: 0.4
                elide: Text.ElideLeft
            }

            MaterialSymbol {
                text: "refresh"
                iconSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer0
                opacity: root.loading ? 0.4 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                RotationAnimation on rotation {
                    running: root.loading
                    loops: Animation.Infinite; from: 0; to: 360; duration: 900
                }
            }
        }

        // ── File list ─────────────────────────────────────────────────────
        ListView {
            id: fileList
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 4
            Layout.rightMargin: 6
            Layout.bottomMargin: 6
            clip: true
            spacing: 1
            model: root.entries
            cacheBuffer: 250  // was 600

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Item {
                required property var modelData
                width: fileList.width
                implicitHeight: 34

                readonly property bool isDir:   modelData.kind === "d"
                readonly property bool isAudio: root._isAudio(modelData.name)
                readonly property bool isPlaying: isAudio && ShelfPlayer.isPlaying
                    && ShelfPlayer.currentPath === modelData.path

                Drag.active: fileDrag.active
                Drag.dragType: Drag.Automatic
                Drag.mimeData: isDir ? ({}) : ({ "text/uri-list": "file://" + modelData.path })
                Drag.onDragStarted: { if (isAudio) ShelfPlayer.stop() }

                DragHandler {
                    id: fileDrag
                    enabled: !isDir
                    onActiveChanged: if (active) parent.grabToImage(r => { parent.Drag.imageSource = r.url })
                }

                Rectangle {
                    anchors { fill: parent; rightMargin: 2 }
                    radius: Appearance.rounding.small
                    color: isPlaying
                        ? Qt.alpha(Appearance.colors.colPrimary, 0.12)
                        : (rowHov.hovered ? Appearance.colors.colLayer2 : "transparent")
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

                    HoverHandler { id: rowHov }
                    TapHandler {
                        onTapped: {
                            if (isDir) root.navigate(modelData.path)
                            else if (isAudio) ShelfPlayer.toggle(modelData.path)
                        }
                    }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        spacing: 8

                        MaterialSymbol {
                            text: isDir ? "folder"
                                : (isPlaying ? "graphic_eq" : root._fileIcon(modelData.name))
                            iconSize: Appearance.font.pixelSize.normal
                            color: isDir ? Appearance.colors.colPrimary
                                : (isPlaying ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0)
                            opacity: isDir ? 0.75 : (isPlaying ? 1 : 0.4)
                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.name
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: isDir ? Font.Medium : Font.Normal
                            color: isPlaying ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                            elide: Text.ElideRight
                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                        }

                        StyledText {
                            visible: !isDir
                            text: modelData.size
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer0
                            opacity: 0.25
                        }

                        MaterialSymbol {
                            visible: isDir
                            text: "chevron_right"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer0
                            opacity: 0.2
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
                        text: "folder_open"; iconSize: 28
                        color: Appearance.colors.colOnLayer0; opacity: 0.12
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Empty")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer0; opacity: 0.25
                    }
                }
            }
        }
        } // end of main content column

        // ── Hairline vertical separator ──────────────────────────────────
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            color: Qt.alpha(Appearance.colors.colOnLayer0, 0.07)
        }

        // ── Level 3: Quick-access tabs on the RIGHT ──────────────────────
        ShelfSubTabBar {
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 4
            orientation: Qt.Vertical
            tabs: root.quickAccess
            current: root.activeQuickId
            onTabSelected: tabId => {
                const qa = root.quickAccess.find(q => q.id === tabId)
                if (qa) root.navigate(qa.path)
            }
        }
    }
}
