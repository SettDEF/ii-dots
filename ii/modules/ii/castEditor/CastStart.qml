import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.walltune
import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io

/// Shown when no recording is open: record a new one, open a folder, or
/// pick a recent recording.
Rectangle {
    id: start
    required property var doc
    color: Appearance.colors.colLayer0

    /// Recording: `tinct-cast record` (prints the new directory when stopped).
    /// CAST_RECORD_CMD replaces it (tests use a synthetic stand-in; it gets
    /// the planned directory as $1).
    property bool recording: recorder.running
    property real recStarted: 0
    property string recLast: ""
    /// Stop was pressed; the recorder is finishing (stopping capture, analysing).
    property bool stopping: false
    property string recError: ""
    function stopRecording() { stopping = true; recorder.signal(2); }
    function record() {
        const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss");
        const base = doc.config ? doc.config.recordings : (Quickshell.env("HOME") || "") + "/Videos/tinct-cast";
        const dir = base + "/" + stamp;
        const custom = Quickshell.env("CAST_RECORD_CMD") || "";
        recorder.command = custom.length > 0 ? ["sh", "-c", custom, "sh", dir] : doc.cli(["record", "-o", dir]);
        recLast = "";
        recError = "";
        stopping = false;
        recStarted = Date.now();
        recorder.running = true;
    }
    Process {
        id: recorder
        stdout: SplitParser { onRead: (line) => { if (line.trim().length > 0) start.recLast = line.trim(); } }
        onExited: (code) => {
            start.stopping = false;
            if (start.recLast.startsWith("/")) start.doc.open(start.recLast);
            else start.recError = "Recording failed (exit " + code + ")";
        }
    }
    Timer { id: tick; interval: 500; repeat: true; running: start.recording; property int n: 0; onTriggered: n++ }

    Loader {
        id: folderDialog
        active: false
        function open() { active = true; item.open(); }
        sourceComponent: FolderDialog {
            title: "Open a tinct-cast recording"
            onAccepted: start.doc.open(selectedFolder.toString())
            onRejected: folderDialog.active = false
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(560, parent.width - 48)
        spacing: 16

        RowLayout {
            spacing: 12
            MaterialSymbol { text: "movie_edit"; iconSize: 40; color: Appearance.colors.colPrimary }
            ColumnLayout {
                spacing: 0
                StyledText { text: "tinct-cast"; font.pixelSize: Appearance.font.pixelSize.huge; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer0 }
                StyledText { text: "Record your screen, then edit it here."; color: Appearance.colors.colSubtext }
            }
        }

        RowLayout {
            spacing: 10
            RippleButton {
                objectName: "recordNew"
                implicitHeight: 44
                implicitWidth: recRow.implicitWidth + 36
                buttonRadius: Appearance.rounding.full
                colBackground: start.recording ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimary
                colBackgroundHover: start.recording ? Appearance.colors.colErrorContainerHover : Appearance.colors.colPrimaryHover
                enabled: !start.stopping
                onClicked: start.recording ? start.stopRecording() : start.record()
                contentItem: Item {
                    RowLayout {
                        id: recRow
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol {
                            text: start.stopping ? "hourglass_top" : start.recording ? "stop_circle" : "radio_button_checked"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.larger
                            color: start.recording ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            objectName: "recordLabel"
                            text: start.stopping ? "Finishing…" : start.recording ? "Stop · " + start.doc.fmt((Date.now() - start.recStarted) / 1000 + tick.n * 0).replace(/\.\d+$/, "") : "Record new"
                            font.weight: Font.DemiBold
                            color: start.recording ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimary
                        }
                    }
                }
            }
            DialogButton {
                objectName: "openFolder"
                buttonText: "Open recording…"
                onClicked: folderDialog.open()
            }
            DialogButton {
                objectName: "openSettings"
                buttonText: "Settings…"
                onClicked: start.doc.openConfig()
            }
        }
        StyledText {
            objectName: "recError"
            visible: start.recError.length > 0
            text: start.recError
            color: Appearance.colors.colError
        }

        StyledText {
            visible: start.doc.recents.length > 0
            text: "Recent"
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        PaletteCard {
            visible: start.doc.recents.length > 0
            Repeater {
                model: start.doc.recents
                PaletteRow {
                    required property var modelData
                    required property int index
                    objectName: "recent-" + index
                    glyph: "movie"
                    title: modelData.split("/").pop()
                    subtitle: modelData
                    onClicked: start.doc.open(modelData)
                }
            }
        }
    }
}
