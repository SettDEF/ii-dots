import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.walltune
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/// Export sheet over the editor: format, size, rate, quality, encoder, then
/// a progress bar fed by the CLI's "progress" lines; when done, copy the
/// file to the clipboard or show it in the file manager.
Item {
    id: dlg
    required property var doc
    property bool open: false
    /// idle | running | cancelling | done | failed
    property string phase: "idle"
    property real progress: 0
    property string outPath: ""
    property string log: ""
    visible: open

    /// GIFs are capped at 720p (the CLI clamps too); 4K GIFs are unusable.
    readonly property int effectiveRes: doc.exportFormat === "gif" ? Math.min(doc.exportRes, 720) : doc.exportRes
    readonly property int effectiveFps: doc.exportFormat === "gif" ? Math.min(doc.exportFps, 30) : doc.exportFps
    /// Timestamped, so exporting twice never overwrites the last one.
    function outFile() {
        const base = doc.dir.replace(/\/$/, "");
        return base + "/export-" + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss") + "-" + effectiveRes + "p" + effectiveFps + "." + doc.exportFormat;
    }
    function cancel() {
        if (dlg.phase !== "running") return;
        if (!job.running) { dlg.phase = "idle"; return; }
        dlg.phase = "cancelling";
        job.signal(15);
    }
    /// The export path comes from the config (exports dir + name template).
    function start() {
        dlg.outPath = "";
        dlg.phase = "running";
        dlg.progress = 0;
        dlg.log = "";
        namer.command = doc.cli(["config", "--export-path", "--dir", doc.dir, "--res", String(effectiveRes), "--fps", String(effectiveFps), "--ext", doc.exportFormat]);
        namer.running = true;
    }
    Process {
        id: namer
        property string got: ""
        stdout: StdioCollector { onStreamFinished: namer.got = text.trim() }
        onExited: (code) => dlg.launch(code === 0 && namer.got.startsWith("/") ? namer.got : dlg.outFile())
    }
    function launch(path) {
        if (dlg.phase !== "running") return;
        dlg.outPath = path;
        dlg.progress = 0;
        dlg.log = "";
        dlg.phase = "running";
        job.command = doc.cli(["render", doc.dir, "-o", dlg.outPath, "--resolution", String(effectiveRes),
                       "--fps", String(effectiveFps),
                       "--quality", doc.exportQuality, "--encoder", doc.exportEncoder, "--progress"]);
        job.running = true;
    }

    Process {
        id: job
        stdout: SplitParser {
            onRead: (line) => {
                const m = line.match(/^progress (\d+) (\d+)/);
                if (m && Number(m[2]) > 0) dlg.progress = Number(m[1]) / Number(m[2]);
            }
        }
        stderr: SplitParser { onRead: (line) => dlg.log = line }
        onExited: (code) => {
            if (dlg.phase === "cancelling") {
                // The CLI removes partial files itself; reset to idle.
                dlg.phase = "idle";
                dlg.progress = 0;
                return;
            }
            dlg.phase = code === 0 ? "done" : "failed";
            if (code === 0) { dlg.progress = 1; dlg.doc.lastExport = dlg.outPath; }
        }
    }

    // Scrim.
    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colScrim
        opacity: 0.55
        MouseArea { anchors.fill: parent; onClicked: if (dlg.phase !== "running") dlg.open = false }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 520
        implicitHeight: body.implicitHeight + 40
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 14

            RowLayout {
                spacing: 10
                MaterialSymbol { text: "ios_share"; iconSize: Appearance.font.pixelSize.huge; color: Appearance.colors.colPrimary }
                StyledText { Layout.fillWidth: true; text: "Export"; font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer0 }
                RippleButton {
                    implicitWidth: 34; implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    enabled: dlg.phase !== "running" && dlg.phase !== "cancelling"
                    onClicked: dlg.open = false
                    contentItem: MaterialSymbol { horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; text: "close"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer0 }
                }
            }

            component Choice: ColumnLayout {
                property string title: ""
                property var model: []
                property var current
                signal chosen(var id)
                Layout.fillWidth: true
                spacing: 6
                StyledText { text: parent.title; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                SegmentedButtons {
                    Layout.fillWidth: true
                    segmentHeight: 34
                    model: parent.model
                    currentId: parent.current
                    onSelected: id => parent.chosen(id)
                }
            }

            Choice {
                title: "Format"
                model: [{ id: "mp4", label: "MP4", icon: "movie" }, { id: "gif", label: "GIF", icon: "gif_box" }]
                current: dlg.doc.exportFormat
                onChosen: id => dlg.doc.exportFormat = id
            }
            Choice {
                title: "Resolution"
                model: [{ id: 720, label: "720p" }, { id: 1080, label: "1080p" }, { id: 1440, label: "1440p" }, { id: 2160, label: "4K" }]
                current: dlg.doc.exportRes
                onChosen: id => dlg.doc.exportRes = id
            }
            StyledText {
                visible: dlg.doc.exportFormat === "gif" && (dlg.doc.exportRes > 720 || dlg.doc.exportFps > 30)
                Layout.fillWidth: true
                text: "GIFs are made at up to 720p and 30 fps."
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
            Choice {
                title: "Frame rate"
                model: [{ id: 30, label: "30 fps" }, { id: 60, label: "60 fps" }]
                current: dlg.doc.exportFps
                onChosen: id => dlg.doc.exportFps = id
            }
            Choice {
                title: "Quality"
                model: [{ id: "low", label: "Small" }, { id: "medium", label: "Balanced" }, { id: "high", label: "High" }]
                current: dlg.doc.exportQuality
                onChosen: id => dlg.doc.exportQuality = id
            }
            Choice {
                title: "Encoder"
                model: [{ id: "auto", label: "Auto" }, { id: "vaapi", label: "GPU", icon: "memory" }, { id: "cpu", label: "CPU", icon: "developer_board" }]
                current: dlg.doc.exportEncoder
                onChosen: id => dlg.doc.exportEncoder = id
            }

            // Progress / result.
            Rectangle {
                Layout.fillWidth: true
                visible: dlg.phase !== "idle"
                implicitHeight: res.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                ColumnLayout {
                    id: res
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 8
                    RowLayout {
                        MaterialSymbol {
                            text: dlg.phase === "done" ? "check_circle" : (dlg.phase === "failed" ? "error" : "hourglass_top")
                            iconSize: Appearance.font.pixelSize.larger
                            color: dlg.phase === "failed" ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: dlg.phase === "done" ? dlg.outPath.split("/").pop()
                                  : dlg.phase === "failed" ? "Export failed" : "Rendering…"
                            elide: Text.ElideMiddle
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            text: Math.round(dlg.progress * 100) + "%"
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colSubtext
                        }
                    }
                    StyledProgressBar {
                        Layout.fillWidth: true
                        value: dlg.progress
                    }
                    StyledText {
                        visible: dlg.phase === "failed" && dlg.log.length > 0
                        Layout.fillWidth: true
                        text: dlg.log
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.m3colors.m3error
                    }
                    RowLayout {
                        visible: dlg.phase === "done"
                        spacing: 8
                        DialogButton {
                            buttonText: "Copy to clipboard"
                            onClicked: dlg.doc.copyFile(dlg.outPath)
                        }
                        CastReveal { objectName: "dialogReveal"; doc: dlg.doc; path: dlg.outPath }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DialogButton {
                    objectName: "exportCancel"
                    visible: dlg.phase === "running" || dlg.phase === "cancelling"
                    enabled: dlg.phase === "running"
                    buttonText: dlg.phase === "cancelling" ? "Cancelling…" : "Cancel"
                    onClicked: dlg.cancel()
                }
                PrimaryActionButton {
                    objectName: "exportStart"
                    buttonText: dlg.phase === "running" ? "Exporting…" : (dlg.phase === "done" ? "Export again" : "Export")
                    enabled: dlg.phase !== "running" && dlg.phase !== "cancelling"
                    onClicked: dlg.start()
                }
            }
        }
    }
}
