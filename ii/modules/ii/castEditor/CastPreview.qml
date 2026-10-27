import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import QtMultimedia

/// The canvas: the proxy video while playing, an exact rendered frame
/// while paused or scrubbing. Transport underneath.
Rectangle {
    id: pv
    required property var doc
    color: Appearance.colors.colLayer0

    /// Output aspect (w / h) from the timeline.
    readonly property real aspect: {
        const t = pv.doc.tl;
        if (!t) return 16 / 10;
        const a = t.style.aspect || "auto";
        const m = a.match(/^(\d+(?:\.\d+)?):(\d+(?:\.\d+)?)$/);
        const rec = m ? Number(m[1]) / Number(m[2]) : t.source.width / t.source.height;
        // media can put the recording on a larger canvas (side by side, stacked)
        const c = t.media && t.media.canvas ? t.media.canvas.main : null;
        return c && c[2] > 0 && c[3] > 0 ? rec * c[3] / c[2] : rec;
    }

    readonly property var media: doc.tl && doc.tl.media ? doc.tl.media : null
    /// The recording's box on the canvas (fractions); the whole canvas without media.
    readonly property var mainR: media && media.canvas && media.canvas.main ? media.canvas.main : [0, 0, 1, 1]
    readonly property var layers: media ? (media.layers || []) : []
    /// Output time at the playhead (layers are timed in output seconds).
    readonly property real outNow: doc.srcToOut(doc.playhead)

    ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 12

        Item {
            id: viewport
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                id: canvas
                readonly property real fitW: Math.min(viewport.width, viewport.height * pv.aspect)
                width: fitW
                height: fitW / pv.aspect
                anchors.centerIn: parent
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                clip: true
                Timer {
                    id: sizeTimer
                    interval: 200
                    onTriggered: {
                        // the exact frame is the recording alone: render it at the
                        // size of its box on the canvas (layers are drawn on top)
                        pv.doc.frameSize = Qt.size(Math.round(mainArea.width / 4) * 4, Math.round(mainArea.height / 2) * 2);
                        pv.doc.requestFrame();
                    }
                }

                Loader {
                    anchors.fill: parent
                    active: pv.doc.proxyPath.length > 0
                    sourceComponent: Item {
                        MediaPlayer {
                            id: player
                            // Seek requested before the media was ready (new proxy, first play).
                            property real pendingSeek: -1
                            function seekAndPlay() {
                                const ms = Math.round(pv.doc.srcToOut(pv.doc.playhead) * 1000);
                                if (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia || mediaStatus === MediaPlayer.BufferingMedia || mediaStatus === MediaPlayer.EndOfMedia) {
                                    position = ms;
                                    play();
                                } else {
                                    pendingSeek = ms;
                                }
                            }
                            onMediaStatusChanged: {
                                if (mediaStatus === MediaPlayer.EndOfMedia && pv.doc.playing) { reachedEnd(); if (pv.doc.loop) play(); return; }
                                if (pendingSeek >= 0 && (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia)) {
                                    position = pendingSeek;
                                    pendingSeek = -1;
                                    if (pv.doc.playing) play();
                                }
                            }
                            onSourceChanged: if (pv.doc.playing) seekAndPlay()
                            source: pv.doc.proxyPath.length > 0 ? "file://" + pv.doc.proxyPath : ""
                            videoOutput: video
                            // Qt 6 plays no sound without one; the proxy carries the export's mix
                            audioOutput: AudioOutput {}
                            playbackRate: pv.doc.playbackRate
                            onPositionChanged: (pos) => {
                                if (!pv.doc.playing) return;
                                const src = pv.doc.outToSrc(pos / 1000);
                                if (src >= pv.doc.playRange[1] - 0.01) reachedEnd();
                                else pv.doc.playhead = src;
                            }
                            /// End of the range: loop back, or stop and rewind to its start.
                            function reachedEnd() {
                                const r = pv.doc.playRange;
                                if (pv.doc.loop) {
                                    pv.doc.playhead = r[0];
                                    position = Math.round(pv.doc.srcToOut(r[0]) * 1000);
                                } else {
                                    pv.doc.playing = false;
                                    pv.doc.playhead = r[0];
                                }
                            }
                        }
                        VideoOutput { id: video; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectFit }
                        Connections {
                            target: pv.doc
                            function onPlayingChanged() {
                                if (pv.doc.playing) {
                                    player.seekAndPlay();
                                } else {
                                    player.pause();
                                }
                            }
                        }
                    }
                }

                // The recording's box (the whole canvas unless media puts it on a
                // larger one): the exact frame and the zoom aim live in here.
                Item {
                    id: mainArea
                    objectName: "mainArea"
                    x: pv.mainR[0] * canvas.width
                    y: pv.mainR[1] * canvas.height
                    width: pv.mainR[2] * canvas.width
                    height: pv.mainR[3] * canvas.height
                    onWidthChanged: sizeTimer.restart()
                    onHeightChanged: sizeTimer.restart()
                    Image {
                        anchors.fill: parent
                        visible: !pv.doc.playing && status === Image.Ready
                        source: pv.doc.framePath.length > 0 ? "file://" + pv.doc.framePath + "?" + pv.doc.frameRev : ""
                        cache: false
                        asynchronous: false
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    // Zoom target: with a zoom block selected, click to aim it; the
                    // crosshair shows where it points (mapped through the frame's view).
                    Item {
                        id: aim
                        objectName: "aimLayer"
                        anchors.fill: parent
                        readonly property var seg: {
                            const s = pv.doc.selection, t = pv.doc.tl;
                            return s && t && s.track === "zoom" ? t.segments[s.index] : null;
                        }
                        readonly property var info: pv.doc.frameInfo
                        // Frame px -> canvas px.
                        readonly property real k: info ? width / info.size[0] : 1
                        visible: seg !== null && !pv.doc.playing
                        function toSource(px, py) {
                            const r = info.rect, v = info.view;
                            const fx = px / k, fy = py / k;
                            if (fx < r[0] || fy < r[1] || fx > r[0] + r[2] || fy > r[1] + r[3]) return null;
                            return [v[0] + (fx - r[0]) / r[2] * v[2], v[1] + (fy - r[1]) / r[3] * v[3]];
                        }
                        readonly property var mark: {
                            if (!seg || !seg.focus || !info) return null;
                            const r = info.rect, v = info.view;
                            const fx = r[0] + (seg.focus[0] - v[0]) / v[2] * r[2], fy = r[1] + (seg.focus[1] - v[1]) / v[3] * r[3];
                            if (fx < r[0] || fy < r[1] || fx > r[0] + r[2] || fy > r[1] + r[3]) return null;
                            return [fx * k, fy * k];
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.CrossCursor
                            onClicked: (m) => {
                                if (!aim.info) return;
                                const p = aim.toSource(m.x, m.y);
                                if (!p) return;
                                const i = pv.doc.selection.index;
                                pv.doc.edit(t => { t.segments[i].focus = [Math.round(p[0]), Math.round(p[1])]; t.segments[i].kind = "manual"; });
                            }
                        }
                        Item {
                            visible: aim.mark !== null
                            x: aim.mark ? aim.mark[0] : 0
                            y: aim.mark ? aim.mark[1] : 0
                            // Halo first so the mark reads on any content.
                            Rectangle { x: -23; y: -2; width: 46; height: 4; radius: 2; color: Appearance.colors.colLayer0; opacity: 0.7 }
                            Rectangle { x: -2; y: -23; width: 4; height: 46; radius: 2; color: Appearance.colors.colLayer0; opacity: 0.7 }
                            Rectangle { x: -22; y: -1; width: 44; height: 2; color: Appearance.colors.colPrimary }
                            Rectangle { x: -1; y: -22; width: 2; height: 44; color: Appearance.colors.colPrimary }
                            Rectangle {
                                x: -14; y: -14; width: 28; height: 28; radius: 14
                                color: "transparent"
                                border.width: 3
                                border.color: Appearance.colors.colPrimary
                            }
                        }
                        Rectangle {
                            anchors { left: parent.left; bottom: parent.bottom; margins: 10 }
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colLayer2
                            implicitHeight: 28
                            implicitWidth: hintRow.implicitWidth + 20
                            RowLayout {
                                id: hintRow
                                anchors.centerIn: parent
                                spacing: 6
                                MaterialSymbol { text: "point_scan"; iconSize: Appearance.font.pixelSize.small; color: Appearance.colors.colPrimary }
                                StyledText {
                                    text: aim.seg && aim.seg.focus ? "Zoom target set: click to move it" : "Click to aim this zoom (now following the cursor)"
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnLayer2
                                }
                            }
                        }
                    }
                }

                CastLayers {
                    anchors.fill: parent
                    doc: pv.doc
                    layers: pv.layers
                    outNow: pv.outNow
                    visible: !pv.doc.playing && pv.layers.length > 0
                    // aiming a zoom takes the clicks
                    interactive: !aim.visible
                }

                // Right-click: transport, aim, and getting the frame out.
                MouseArea {
                    id: previewMenuArea
                    objectName: "previewMenuArea"
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onClicked: (m) => {
                        const d = pv.doc;
                        const items = [{ icon: d.playing ? "pause" : "play_arrow", label: d.playing ? "Pause" : "Play", shortcut: "Space", onTriggered: () => d.togglePlay() }];
                        if (aim.seg && aim.info) {
                            const p = aim.toSource(m.x, m.y);
                            if (p) items.push({ icon: "point_scan", label: "Aim the zoom here", onTriggered: () => {
                                const i = d.selection.index;
                                d.edit(t => { t.segments[i].focus = [Math.round(p[0]), Math.round(p[1])]; t.segments[i].kind = "manual"; });
                            } });
                        }
                        items.push({ separator: true },
                            { icon: "content_copy", label: "Copy frame", onTriggered: () => d.copyFrame() },
                            { icon: "image", label: "Save frame as PNG", onTriggered: () => d.saveFrame() });
                        d.menu(previewMenuArea, m.x, m.y, items);
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: pv.doc.framePath.length === 0
                    text: pv.doc.dir.length === 0 ? "No recording: start with CAST_DIR=<dir>" : (pv.doc.ready ? "Rendering…" : "Loading…")
                    color: Appearance.colors.colSubtext
                }
            }

            // Proxy status chip.
            Rectangle {
                anchors { right: canvas.right; top: canvas.top; margins: 10 }
                visible: pv.doc.proxyBusy
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2
                implicitHeight: 26
                implicitWidth: chipRow.implicitWidth + 20
                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol { text: "autorenew"; iconSize: Appearance.font.pixelSize.small; color: Appearance.colors.colPrimary }
                    StyledText {
                        text: "Preview " + Math.round(pv.doc.proxyProgress * 100) + "%"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: Math.max(canvas.width, 420)
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            component TButton: RippleButton {
                property string glyph: ""
                property string tip: ""
                property bool lit: false
                implicitWidth: 36; implicitHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: lit ? Appearance.colors.colSecondaryContainer : "transparent"
                colBackgroundHover: lit ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    text: parent.glyph
                    iconSize: Appearance.font.pixelSize.larger
                    color: parent.lit ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
                }
                StyledToolTip { text: parent.tip }
            }
            TButton { objectName: "toStart"; glyph: "first_page"; tip: "Go to start (Home)"; onClicked: { pv.doc.playing = false; pv.doc.playhead = pv.doc.trimStart; } }
            TButton { objectName: "prevEdit"; glyph: "skip_previous"; tip: "Previous edit point (Shift+←)"; onClicked: { pv.doc.playing = false; pv.doc.playhead = pv.doc.prevEditPoint(pv.doc.playhead); } }
            RippleButton {
                objectName: "playPause"
                implicitWidth: 44; implicitHeight: 44
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                onClicked: pv.doc.togglePlay()
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    text: pv.doc.playing ? "pause" : (pv.doc.playWhenReady ? "hourglass_top" : "play_arrow")
                    fill: 1
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnPrimaryContainer
                }
                StyledToolTip { text: pv.doc.playing ? "Pause (Space)" : "Play (Space)" }
            }
            TButton { objectName: "nextEdit"; glyph: "skip_next"; tip: "Next edit point (Shift+→)"; onClicked: { pv.doc.playing = false; pv.doc.playhead = pv.doc.nextEditPoint(pv.doc.playhead); } }
            TButton { objectName: "toEnd"; glyph: "last_page"; tip: "Go to end (End)"; onClicked: { pv.doc.playing = false; pv.doc.playhead = pv.doc.trimEnd; } }
            TButton {
                objectName: "loopToggle"
                glyph: "repeat"
                lit: pv.doc.loop
                tip: pv.doc.selection ? "Loop the selected block (L)" : "Loop (L)"
                onClicked: pv.doc.loop = !pv.doc.loop
            }
            RippleButton {
                id: rateChip
                objectName: "rateChip"
                implicitHeight: 30
                implicitWidth: 52
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: pv.doc.menu(rateChip, 0, rateChip.height, [0.5, 1, 1.5, 2].map(v => ({
                    icon: pv.doc.tick(pv.doc.playbackRate === v, "speed"), label: v + "×", onTriggered: () => pv.doc.playbackRate = v })))
                contentItem: StyledText {
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    text: pv.doc.playbackRate + "×"
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer2
                }
                StyledToolTip { text: "Playback speed (preview only)" }
            }
            StyledText {
                text: pv.doc.fmt(pv.doc.srcToOut(pv.doc.playhead)) + " / " + pv.doc.fmt(pv.doc.outDuration)
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer0
            }
            StyledSlider {
                Layout.fillWidth: true
                configuration: StyledSlider.Configuration.S
                from: 0
                to: Math.max(0.01, pv.doc.outDuration)
                value: pv.doc.srcToOut(pv.doc.playhead)
                onMoved: { pv.doc.playing = false; pv.doc.playhead = pv.doc.outToSrc(value); }
            }
        }
    }
}
