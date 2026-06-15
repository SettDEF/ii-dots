pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Rectangle {
    id: root
    required property string filePath
    required property string fileName
    required property string fileSize
    required property string timeAgo
    required property string extractTo

    property bool extracting: false
    property bool extracted: false
    property var  audioFiles: []
    property string extractError: ""

    implicitWidth: 180
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    border.width: 1
    border.color: extracted ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer0Border
    Behavior on border.color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
    clip: true

    // _gone guard: cards are removed from the shelf list while a Process
    // is still finishing — the JS handler then dereferences a dead `root`
    // and V4 GC crashes during stack scan.
    property bool _gone: false
    Component.onDestruction: _gone = true

    // ── Extract ───────────────────────────────────────────────────────────
    Process {
        id: extractProc
        stdout: StdioCollector { onStreamFinished: {
            if (root._gone) return
            root._onExtractDone(text.trim())
        }}
        onRunningChanged: {
            if (running) return
            if (root._gone) return
            root.extracting = false
        }
    }

    Process {
        id: listProc
        stdout: StdioCollector { onStreamFinished: {
            if (root._gone) return
            const lines = text.trim().split("\n").filter(l => l.trim())
            root.audioFiles = lines.map(l => ({
                path: l.trim(),
                name: l.trim().split("/").pop()
            }))
        }}
    }

    Process {
        id: checkProc
        stdout: StdioCollector { onStreamFinished: {
            if (root._gone) return
            if (text.trim() !== "") {
                root.extracted = true
                root._onExtractDone("ok:" + text.trim())
            }
        }}
    }

    function extract() {
        if (extracting || extracted) return
        extracting = true
        extractError = ""
        const packName = fileName.replace(/\.zip$/i, "")
        const dest = extractTo + "/" + packName
        extractProc.exec({ command: ["bash", "-c",
            `mkdir -p "${dest}" && unzip -o "${filePath}" -d "${dest}" > /dev/null 2>&1 && echo "ok:${dest}" || echo "err"`
        ]})
    }

    function _onExtractDone(result) {
        if (result.startsWith("ok:")) {
            extracted = true
            const dest = result.slice(3)
            listProc.exec({ command: ["bash", "-c",
                `find "${dest}" -type f \\( -iname "*.wav" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.aiff" \\) | sort`
            ]})
        } else {
            extractError = "Failed"
        }
    }

    Component.onCompleted: {
        if (extractTo !== "") {
            const packName = fileName.replace(/\.zip$/i, "")
            const dest = extractTo + "/" + packName
            checkProc.exec({ command: ["bash", "-c", `test -d "${dest}" && echo "${dest}" || true`] })
        }
    }

    // ── Layout ────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors { fill: parent; margins: 10 }
        spacing: 6

        // Icon area
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 48
            radius: Appearance.rounding.small
            color: root.extracted
                ? Appearance.colors.colPrimaryContainer
                : Appearance.colors.colLayer2
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.extracted ? "folder_zip" : "archive"
                iconSize: 24
                color: root.extracted ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                opacity: root.extracted ? 1 : 0.3
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

                RotationAnimation on rotation {
                    running: root.extracting
                    loops: Animation.Infinite; from: 0; to: 360; duration: 1200
                }
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

        // Size + time
        StyledText {
            text: root.fileSize + " · " + root.timeAgo
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer0
            opacity: 0.4
        }

        Item { Layout.fillHeight: true }

        // Status / extract row
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            // Track count badge
            Rectangle {
                visible: root.audioFiles.length > 0
                implicitWidth: trackLbl.implicitWidth + 10; implicitHeight: 20; radius: 10
                color: Appearance.colors.colTertiaryContainer
                StyledText {
                    id: trackLbl
                    anchors.centerIn: parent
                    text: root.audioFiles.length + " tracks"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onTertiaryContainer
                }
            }

            Item { Layout.fillWidth: true }

            // Extract button
            Rectangle {
                visible: root.extractTo !== "" && !root.extracted
                implicitWidth: 26; implicitHeight: 26; radius: 13
                color: root.extracting
                    ? Appearance.colors.colLayer2
                    : (extHov.hovered ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2)
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                HoverHandler { id: extHov }
                TapHandler { onTapped: root.extract() }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.extracting ? "hourglass_empty" : "unarchive"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.7
                    RotationAnimation on rotation {
                        running: root.extracting
                        loops: Animation.Infinite; from: 0; to: 360; duration: 1200
                    }
                }
            }

            // Error
            StyledText {
                visible: root.extractError !== ""
                text: root.extractError
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3error
            }
        }
    }
}
