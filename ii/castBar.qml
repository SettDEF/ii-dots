//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_IM_MODULE=compose

// tinct-cast recording bar. `tinct-cast record --bar` starts it with
// CAST_REC_STATUS=<recording dir>/.rec-status.json and CAST_REC_MONITOR=<name>.
// It sits on a monitor that is NOT being recorded when there is one, shows
// the timer, mic/camera, a thumbnail and (on demand) the styled live
// preview, and signals the recorder: SIGUSR1 pause, SIGUSR2 live, SIGINT stop.
// Tests: CAST_SHOT=<png> grabs the bar and quits; CAST_TEST=<js> drives it.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.castEditor

PanelWindow {
    id: root
    readonly property string statusPath: Quickshell.env("CAST_REC_STATUS") || ""
    readonly property string recMonitor: Quickshell.env("CAST_REC_MONITOR") || ""
    readonly property string shot: Quickshell.env("CAST_SHOT") || ""
    /// Another monitor than the recorded one, or (single monitor) the recorded one.
    readonly property var otherScreen: Quickshell.screens.find(s => s.name !== root.recMonitor) ?? null
    readonly property bool inRecording: otherScreen === null

    property var st: ({})
    readonly property bool ready: st.pid !== undefined
    readonly property bool paused: !!st.paused
    readonly property bool live: !!st.live

    screen: otherScreen ?? Quickshell.screens.find(s => s.name === root.recMonitor) ?? Quickshell.screens[0]
    anchors.top: true
    margins.top: 14
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "tinct-cast-bar"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    implicitWidth: card.implicitWidth + 24
    implicitHeight: card.implicitHeight + 24

    Component.onCompleted: MaterialThemeLoader.reapplyTheme()

    // ---- status from the recorder ----
    FileView {
        id: statusFile
        path: root.statusPath
        blockLoading: true
        onLoaded: {
            try { root.st = JSON.parse(text()); } catch (e) { return; }
            if (root.st.stopped && root.shot.length === 0) Qt.quit();
        }
    }
    Timer {
        running: root.statusPath.length > 0
        repeat: true
        interval: 200
        onTriggered: statusFile.reload()
    }

    function sendSignal(name) {
        if (!root.ready) return;
        Quickshell.execDetached(["kill", "-" + name, String(root.st.pid)]);
    }
    function togglePause() { if (root.st.can_pause) root.sendSignal("USR1"); }
    function toggleLive() { root.sendSignal("USR2"); }
    function stop() { root.sendSignal("INT"); }

    function clock(s) {
        s = Math.max(0, s || 0);
        const m = Math.floor(s / 60), r = Math.floor(s % 60);
        const h = Math.floor(m / 60);
        const two = n => (n < 10 ? "0" : "") + n;
        return (h > 0 ? h + ":" + two(m % 60) : two(m)) + ":" + two(r);
    }

    component BarButton: RippleButton {
        property string glyph: ""
        property string tip: ""
        property bool lit: false
        property color fg: lit ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
        implicitWidth: 36; implicitHeight: 36
        buttonRadius: Appearance.rounding.full
        colBackground: lit ? Appearance.colors.colSecondaryContainer : "transparent"
        colBackgroundHover: lit ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            text: parent.glyph
            iconSize: Appearance.font.pixelSize.larger
            color: parent.enabled ? parent.fg : Appearance.colors.colSubtext
        }
        StyledToolTip { text: parent.tip }
    }

    /// Shows a JPEG the recorder rewrites; two images alternate so the old
    /// frame stays up while the next one decodes.
    component LiveImage: Item {
        id: li
        property string file: ""
        property int rev: 0
        property bool flip: false
        clip: true
        onRevChanged: {
            if (!file.length || rev <= 0) return;
            const next = flip ? a : b;
            next.source = "file://" + file + "?" + rev;
        }
        Image {
            id: a
            anchors.fill: parent
            asynchronous: true; cache: false; fillMode: Image.PreserveAspectFit
            visible: !li.flip
            onStatusChanged: if (status === Image.Ready && li.flip) li.flip = false
        }
        Image {
            id: b
            anchors.fill: parent
            asynchronous: true; cache: false; fillMode: Image.PreserveAspectFit
            visible: li.flip
            onStatusChanged: if (status === Image.Ready && !li.flip) li.flip = true
        }
    }

    Item {
        id: stage
        anchors.fill: parent

        StyledRectangularShadow { target: card }
        Rectangle {
            id: card
            objectName: "barCard"
            anchors.centerIn: parent
            implicitWidth: col.implicitWidth + 20
            implicitHeight: col.implicitHeight + 16
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            ColumnLayout {
                id: col
                anchors.centerIn: parent
                spacing: 10

                RowLayout {
                    spacing: 6

                    // Recording dot + timer
                    Rectangle {
                        Layout.preferredWidth: 12; Layout.preferredHeight: 12
                        Layout.leftMargin: 6
                        radius: 6
                        color: root.paused ? Appearance.colors.colSubtext : Appearance.colors.colError
                        SequentialAnimation on opacity {
                            running: root.ready && !root.paused
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 700 }
                            NumberAnimation { to: 1; duration: 700 }
                        }
                    }
                    StyledText {
                        objectName: "timer"
                        Layout.preferredWidth: 64
                        text: root.ready ? root.clock(root.st.elapsed) : "--:--"
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        objectName: "state"
                        text: !root.ready ? "Starting…" : root.paused ? "Paused" : "Recording"
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 24; Layout.leftMargin: 4; Layout.rightMargin: 4; color: Appearance.colors.colOutlineVariant }

                    // Target, mic, camera
                    MaterialSymbol { text: "desktop_windows"; iconSize: Appearance.font.pixelSize.large; color: Appearance.colors.colSubtext }
                    StyledText {
                        objectName: "target"
                        text: root.ready ? root.st.target + "  " + root.st.monitor[0] + "×" + root.st.monitor[1] : ""
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    MaterialSymbol {
                        objectName: "micIcon"
                        Layout.leftMargin: 6
                        text: root.st.mic ? "mic" : "mic_off"
                        iconSize: Appearance.font.pixelSize.large
                        color: root.st.mic ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        StyledToolTip { text: root.st.mic ? "Audio is recorded" : "No audio" }
                        HoverHandler {}
                    }
                    MaterialSymbol {
                        objectName: "camIcon"
                        text: root.st.camera ? "videocam" : "videocam_off"
                        iconSize: Appearance.font.pixelSize.large
                        color: root.st.camera ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        StyledToolTip { text: root.st.camera ? "Camera: " + root.st.camera : "No camera" }
                        HoverHandler {}
                    }
                    MaterialSymbol {
                        objectName: "inRecordingIcon"
                        visible: root.inRecording
                        text: "visibility"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colError
                        StyledToolTip { text: "Only one monitor: this bar is in the recording" }
                        HoverHandler {}
                    }

                    // Thumbnail of what is being captured (1 per second)
                    Rectangle {
                        Layout.preferredWidth: 96; Layout.preferredHeight: 60
                        Layout.leftMargin: 6
                        radius: Appearance.rounding.verysmall
                        color: Appearance.colors.colLayer0
                        clip: true
                        visible: !root.live
                        LiveImage {
                            objectName: "thumb"
                            anchors.fill: parent
                            file: root.ready ? root.st.runtime + "/thumb.jpg" : ""
                            rev: root.st.thumb_rev ?? 0
                        }
                    }

                    BarButton {
                        objectName: "liveToggle"
                        Layout.leftMargin: 4
                        glyph: "preview"
                        lit: root.live
                        tip: root.live ? "Hide the live preview" : "Show the styled live preview"
                        onClicked: root.toggleLive()
                    }
                    BarButton {
                        objectName: "pauseButton"
                        glyph: root.paused ? "play_arrow" : "pause"
                        lit: root.paused
                        enabled: !!root.st.can_pause
                        tip: !root.st.can_pause ? "The camera cannot pause; stop instead" : root.paused ? "Resume" : "Pause"
                        onClicked: root.togglePause()
                    }
                    RippleButton {
                        objectName: "stopButton"
                        implicitWidth: 84; implicitHeight: 36
                        Layout.rightMargin: 2
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colError
                        colBackgroundHover: Qt.lighter(Appearance.colors.colError, 1.1)
                        onClicked: root.stop()
                        contentItem: Item {
                            Row {
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "stop"; fill: 1; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnError }
                                StyledText { anchors.verticalCenter: parent.verticalCenter; text: "Stop"; color: Appearance.colors.colOnError }
                            }
                        }
                        StyledToolTip { text: "Stop and open the editor (Ctrl+C in the terminal works too)" }
                    }
                }

                // Styled live preview (on demand)
                ColumnLayout {
                    visible: root.live
                    spacing: 4
                    Rectangle {
                        Layout.preferredWidth: 480; Layout.preferredHeight: 270
                        Layout.alignment: Qt.AlignHCenter
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer0
                        clip: true
                        LiveImage {
                            objectName: "livePreview"
                            anchors.fill: parent
                            file: root.ready && root.live ? root.st.runtime + "/live.jpg" : ""
                            rev: root.st.live_rev ?? 0
                        }
                    }
                    StyledText {
                        objectName: "liveStats"
                        Layout.alignment: Qt.AlignHCenter
                        text: "Live preview  " + (root.st.fps ?? 0).toFixed(0) + " fps  ·  " + (root.st.latency_ms ?? 0).toFixed(1) + " ms per frame  ·  zooms follow clicks as they happen; the export is exact"
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }
        }
    }

    // ---- test hooks ----
    Loader {
        id: tester
        active: (Quickshell.env("CAST_TEST") || "").length > 0
        sourceComponent: CastTester {}
    }
    function find(name, item) {
        item = item || stage;
        if (item.objectName === name) return item;
        for (const c of item.children) {
            const r = root.find(name, c);
            if (r) return r;
        }
        if (item.contentItem && item.contentItem !== item) return root.find(name, item.contentItem);
        return null;
    }
    function click(name) {
        const it = root.find(name);
        if (!it) { console.warn("castBar test: no item " + name); return; }
        const p = it.mapToItem(stage, it.width / 2, it.height / 2);
        tester.item.click(stage, p.x, p.y);
    }
    property bool testRan: false
    property bool holdShot: false
    Timer {
        running: tester.status === Loader.Ready && root.ready && !root.testRan
        interval: 500
        onTriggered: {
            root.testRan = true;
            try { eval(Quickshell.env("CAST_TEST")); } catch (e) { console.warn("castBar test failed: " + e); }
        }
    }
    Timer {
        running: root.shot.length > 0 && root.ready && (tester.status !== Loader.Ready || root.testRan) && !root.holdShot
        interval: 1500
        onTriggered: stage.grabToImage(r => { r.saveToFile(root.shot); Qt.quit(); })
    }
    Timer {
        running: root.shot.length > 0
        interval: 90000
        onTriggered: { console.warn("castBar: screenshot timed out"); Qt.quit(); }
    }
}
