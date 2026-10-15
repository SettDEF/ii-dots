import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// Tracks laid out on the recording (so cut and sped-up parts stay
/// editable), labelled in OUTPUT time: the ruler counts the video you will
/// export, and hovering it shows the matching recording time. Zoom with
/// Ctrl+wheel, middle-drag (up/down zooms, sideways pans) or the slider, scroll with the wheel or the overview bar.
Rectangle {
    id: tlv
    required property var doc
    color: Appearance.colors.colLayer0
    readonly property var t: doc.tl
    readonly property real dur: Math.max(0.01, doc.duration)
    /// 1 = whole recording fits; up to ~400 px per second.
    property real zoom: 1
    readonly property real fitPps: Math.max(1, scroller.width / dur)
    readonly property real maxZoom: Math.max(1, 400 / fitPps)
    readonly property real pps: fitPps * zoom
    readonly property int trackH: 40
    readonly property int cursorH: 28
    readonly property bool hasWave: !!(doc.assets && doc.assets.wave)

    /// Room a block has on its own track: from the previous block's end to
    /// the next one's start (lists are kept sorted by start).
    function lo(list, i) { return i > 0 ? list[i - 1].end : 0; }
    function hi(list, i) { return i + 1 < list.length ? list[i + 1].start : tlv.dur; }
    function sel(track, i) { return tlv.doc.selection && tlv.doc.selection.track === track && tlv.doc.selection.index === i; }
    function addAtPlayhead(kind) { return tlv.doc.addAt(kind); }
    /// Zoom keeping the recording time under `px` (scroller coords) in place.
    function setZoom(z, px) {
        const anchorT = (scroller.contentX + px) / tlv.pps;
        tlv.zoom = Math.max(1, Math.min(tlv.maxZoom, z));
        scroller.contentX = Math.max(0, Math.min(scroller.contentWidth - scroller.width, anchorT * tlv.pps - px));
    }
    function fit() { tlv.zoom = 1; scroller.contentX = 0; }
    function seekPx(px) { tlv.doc.playing = false; tlv.doc.playhead = Math.max(0, Math.min(tlv.dur, px / tlv.pps)); }

    // ── Context menus ──
    function blockMenu(item, x, y, track, i) {
        const d = tlv.doc;
        const b = d.listOf(d.tl, track)[i];
        if (!b) return;
        const setv = (fn) => () => d.edit(t => fn(d.listOf(t, track)[i]));
        const common = [
            { separator: true },
            { icon: "content_copy", label: "Duplicate", shortcut: "Ctrl+D", onTriggered: () => d.duplicate(track, i) },
            { icon: "vertical_split", label: "Split at playhead", shortcut: "S", onTriggered: () => d.splitAt(track, i, d.playhead) },
            { separator: true },
            { icon: "delete", label: "Delete", shortcut: "Del", danger: true, onTriggered: () => { d.selection = { track: track, index: i }; d.deleteSelection(); } }
        ];
        let items = [];
        if (track === "zoom") {
            items = [
                { icon: "zoom_in", label: "Level", submenu: [1.5, 2, 2.5, 3].map(v => ({ icon: d.tick(Math.abs(b.zoom - v) < 1e-6, "zoom_in"), label: v + "×",
                    onTriggered: setv(s => { s.zoom = v; s.kind = "manual"; }) })) },
                { icon: "point_scan", label: "Aim at the cursor", onTriggered: () => {
                    const c = d.frameInfo && d.frameInfo.cursor;
                    if (c) d.edit(t => { t.segments[i].focus = [Math.round(c[0]), Math.round(c[1])]; t.segments[i].kind = "manual"; });
                } },
                { icon: d.tick(!b.focus, "my_location"), label: "Follow the cursor", onTriggered: setv(s => s.focus = null) }
            ];
        } else if (track === "window") {
            const modes = [["screen", "Screen", "desktop_windows"], ["follow", "Follow focus", "ads_click"], ["pin", "Pin window", "push_pin"]];
            const wins = d.windowsInfo ? d.windowsInfo.windows : [];
            items = [
                { icon: "select_window", label: "Mode", submenu: modes.map(m => ({ icon: d.tick(b.mode === m[0], m[2]), label: m[1], onTriggered: setv(s => s.mode = m[0]) })) }
            ];
            if (b.mode === "pin" && wins.length) items.push({ icon: "push_pin", label: "Window", submenu: wins.map(w => ({ icon: d.tick(b.pin === w.address, "web_asset"), label: w.class, onTriggered: setv(s => s.pin = w.address) })) });
            items.push({ icon: "web", label: "Decorations", submenu: [[null, "Default"], ["with", "With"], ["without", "Without"], ["clean", "Clean"]].map(m => ({ icon: d.tick((b.decorations ?? null) === m[0], "web"), label: m[1], onTriggered: setv(s => s.decorations = m[0]) })) },
                { icon: "transition_slide", label: "Transition in", submenu: [[null, "Default"]].concat(tlv.transitionNames).map(m => ({ icon: d.tick((b.transition ?? null) === m[0], "animation"), label: m[1], onTriggered: setv(s => s.transition = m[0]) })) });
        } else if (track === "cursor") {
            items = [
                { icon: b.visible ? "visibility_off" : "visibility", label: b.visible ? "Hide cursor here" : "Show cursor here", onTriggered: setv(s => s.visible = !s.visible) }
            ];
        } else if (track === "camera") {
            const w = d.tl.webcam;
            items = [
                { icon: "videocam", label: "Mode", submenu: [["hidden", "Hidden", "videocam_off"], ["bubble", "Bubble", "account_circle"], ["fullscreen", "Full screen", "fullscreen"]].map(m => ({
                    icon: d.tick(b.mode === m[0], m[2]), label: m[1], onTriggered: setv(s => s.mode = m[0]) })) },
                { icon: "picture_in_picture", label: "Corner", submenu: [[null, "Default"], ["top-left", "Top left"], ["top-right", "Top right"], ["bottom-left", "Bottom left"], ["bottom-right", "Bottom right"]].map(m => ({
                    icon: d.tick((b.corner ?? null) === m[0], "crop_square"), label: m[1], onTriggered: setv(s => s.corner = m[0]) })) },
                { icon: "photo_size_select_large", label: "Size", submenu: [[null, "Default"], [0.2, "Small"], [0.28, "Medium"], [0.38, "Large"]].map(m => ({
                    icon: d.tick((b.size ?? null) === m[0], "circle"), label: m[1], onTriggered: setv(s => s.size = m[0]) })) }
            ];
        } else {
            const speeds = [0.5, 1.5, 2, 4];
            items = [
                { icon: "speed", label: "Speed", submenu: speeds.map(v => ({ icon: d.tick(track === "speed" && b.speed === v, "speed"), label: v + "×", onTriggered: () => {
                    if (track === "speed") d.edit(t => t.clip.speed[i].speed = v);
                    else if (d.convertClip("cut", i)) { const j = d.selection.index; d.edit(t => t.clip.speed[j].speed = v); }
                } })) },
                { icon: track === "cut" ? "speed" : "content_cut", label: track === "cut" ? "Turn into a speed-up" : "Turn into a cut", onTriggered: () => d.convertClip(track, i) }
            ];
        }
        d.menu(item, x, y, items.concat(common));
    }
    readonly property var transitionNames: [["smooth", "Smooth"], ["fade", "Fade"], ["slide", "Slide"], ["zoom", "Zoom through"], ["cut", "Cut"]]
    /// A window switch marker: its own transition.
    function switchMenu(item, x, y, sw) {
        const d = tlv.doc;
        const cur = d.switchTransition(sw.t);
        d.menu(item, x, y, [
            { icon: "transition_slide", label: "Transition", submenu: [[null, "Default (" + (sw.workspace ? d.tl.window.workspace_transition : d.tl.window.transition) + ")"]].concat(tlv.transitionNames).map(m => ({ icon: d.tick(cur === m[0], "animation"), label: m[1], onTriggered: () => d.setSwitchTransition(sw.t, m[0]) })) },
            { icon: "location_on", label: "Move playhead here", onTriggered: () => { d.playing = false; d.playhead = sw.t; } }
        ]);
    }
    /// Empty space on a track at recording time `t`.
    function laneMenu(item, x, y, t) {
        const d = tlv.doc;
        const at = (fn) => () => { d.playing = false; d.playhead = t; fn(); };
        const splitHere = () => { for (const k of ["zoom", "speed", "cut", "camera", "cursor", "window"]) { const i = d.blockAt(k, t); if (i >= 0 && d.splitAt(k, i, t)) return; } };
        const items = [
            { icon: "content_cut", label: "Add cut here", shortcut: "C", onTriggered: at(() => d.addAt("cut")) },
            { icon: "speed", label: "Add speed-up here", onTriggered: at(() => d.addAt("speed")) },
            { icon: "zoom_in", label: "Add zoom here", shortcut: "Z", onTriggered: at(() => d.addAt("zoom")) }
        ];
        if (d.hasWebcam) items.push({ icon: "videocam", label: "Add camera change here", onTriggered: at(() => d.addAt("camera")) });
        if (d.hasWindows) items.push({ icon: "select_window", label: "Window mode span here", onTriggered: at(() => d.addAt("window")) });
        const shownNow = !d.tl.cursor || d.tl.cursor.visible !== false;
        items.push({ icon: shownNow ? "visibility_off" : "visibility", label: shownNow ? "Hide cursor here" : "Show cursor here", onTriggered: at(() => d.addAt("cursor")) });
        items.push({ separator: true },
            { icon: "vertical_split", label: "Split here", shortcut: "S", onTriggered: at(splitHere) },
            { icon: "first_page", label: "Set trim start here", shortcut: "[", onTriggered: () => d.setTrim("start", t) },
            { icon: "last_page", label: "Set trim end here", shortcut: "]", onTriggered: () => d.setTrim("end", t) },
            { icon: "bookmark_add", label: "Add marker here", onTriggered: () => d.addMarker(t) });
        d.menu(item, x, y, items);
    }
    function rulerMenu(item, x, y, t) {
        const d = tlv.doc;
        d.menu(item, x, y, [
            { icon: "location_on", label: "Move playhead here", onTriggered: () => { d.playing = false; d.playhead = t; } },
            { icon: "fit_screen", label: "Fit timeline", onTriggered: () => tlv.fit() },
            { icon: "bookmark_add", label: "Add marker here", onTriggered: () => d.addMarker(t) }
        ]);
    }

    // Keep the playhead in view while playing.
    Connections {
        target: tlv.doc
        function onPlayheadChanged() {
            if (!tlv.doc.playing) return;
            const x = tlv.doc.playhead * tlv.pps;
            if (x < scroller.contentX || x > scroller.contentX + scroller.width - 40)
                scroller.contentX = Math.max(0, Math.min(scroller.contentWidth - scroller.width, x - scroller.width * 0.2));
        }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 1
        color: Appearance.colors.colLayer0Border
    }

    ColumnLayout {
        anchors { fill: parent; margins: 12; topMargin: 8 }
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            StyledText {
                text: "Timeline"
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            Item { implicitWidth: 10 }
            Repeater {
                model: [
                    { id: "cut", icon: "content_cut", label: "Cut" },
                    { id: "speed", icon: "speed", label: "Speed" },
                    { id: "zoom", icon: "zoom_in", label: "Zoom" },
                    { id: "camera", icon: "videocam", label: "Camera" },
                    { id: "cursor", icon: "visibility_off", label: "Cursor" },
                    { id: "window", icon: "select_window", label: "Window" }
                ]
                RippleButton {
                    required property var modelData
                    visible: (modelData.id !== "camera" || tlv.doc.hasWebcam) && (modelData.id !== "window" || tlv.doc.hasWindows)
                    implicitHeight: 30
                    implicitWidth: addRow.implicitWidth + 24
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: tlv.addAtPlayhead(modelData.id)
                    contentItem: Item {
                // A Control sizes its contentItem, so centre the row inside one.
                RowLayout {
                        id: addRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol { text: "add"; iconSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                        MaterialSymbol { text: modelData.icon; iconSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer2 }
                        StyledText { text: modelData.label; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer2 }
                    }
            }
                    StyledToolTip { text: "Add at the playhead" }
                }
            }
            Item { Layout.fillWidth: true }
            MaterialSymbol { text: "zoom_out"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colSubtext }
            StyledSlider {
                objectName: "timelineZoom"
                Layout.fillWidth: false
                Layout.preferredWidth: 160
                Layout.maximumWidth: 160
                configuration: StyledSlider.Configuration.XS
                from: 0; to: 1
                // Logarithmic: equal steps feel equal at any length.
                value: Math.log(tlv.zoom) / Math.log(Math.max(1.0001, tlv.maxZoom))
                onMoved: tlv.setZoom(Math.exp(value * Math.log(Math.max(1.0001, tlv.maxZoom))), tlv.doc.playhead * tlv.pps - scroller.contentX)
            }
            MaterialSymbol { text: "zoom_in"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colSubtext }
            RippleButton {
                implicitHeight: 30
                implicitWidth: fitRow.implicitWidth + 20
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: tlv.fit()
                contentItem: Item {
                // A Control sizes its contentItem, so centre the row inside one.
                RowLayout {
                    id: fitRow
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol { text: "fit_screen"; iconSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer2 }
                    StyledText { text: "Fit"; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer2 }
                }
            }
                StyledToolTip { text: "Show the whole recording (Ctrl+wheel zooms)" }
            }
            Item { implicitWidth: 6 }
            ColumnLayout {
                spacing: -2
                StyledText {
                    Layout.alignment: Qt.AlignRight
                    text: tlv.doc.fmt(tlv.doc.srcToOut(tlv.doc.playhead))
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.alignment: Qt.AlignRight
                    text: "rec " + tlv.doc.fmt(tlv.doc.playhead)
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            // Track labels.
            ColumnLayout {
                Layout.preferredWidth: 92
                Layout.alignment: Qt.AlignTop
                spacing: 8
                Item { implicitHeight: 20 }
                Repeater {
                    model: [
                        { icon: "movie", label: "Clip", show: true, h: 48 },
                        { icon: "graphic_eq", label: "Audio", show: tlv.hasWave, h: 26 },
                        { icon: "zoom_in", label: "Zoom", show: true, h: tlv.trackH },
                        { icon: "videocam", label: "Camera", show: tlv.doc.hasWebcam, h: tlv.trackH },
                        { icon: "arrow_selector_tool", label: "Cursor", show: true, h: tlv.cursorH },
                        { icon: "select_window", label: "Window", show: tlv.doc.hasWindows, h: tlv.cursorH },
                        { icon: "video_library", label: "Media", show: tlv.doc.mediaRows > 0, h: Math.max(1, tlv.doc.mediaRows * (tlv.cursorH + 8) - 8) }
                    ]
                    RowLayout {
                        required property var modelData
                        visible: modelData.show
                        Layout.preferredHeight: modelData.h
                        spacing: 6
                        MaterialSymbol { text: modelData.icon; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colSubtext }
                        StyledText { text: modelData.label; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer0 }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6

                Flickable {
                    id: scroller
                    objectName: "timelineScroller"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    interactive: false
                    contentWidth: Math.max(width, tlv.dur * tlv.pps)
                    contentHeight: height
                    boundsBehavior: Flickable.StopAtBounds

                    // Wheel: scroll; Ctrl+wheel: zoom around the pointer.
                    WheelHandler {
                        acceptedModifiers: Qt.ControlModifier
                        onWheel: (e) => tlv.setZoom(tlv.zoom * Math.pow(1.0015, e.angleDelta.y), e.x - scroller.contentX)
                    }
                    WheelHandler {
                        acceptedModifiers: Qt.NoModifier
                        onWheel: (e) => {
                            const d = e.angleDelta.x !== 0 ? e.angleDelta.x : e.angleDelta.y;
                            scroller.contentX = Math.max(0, Math.min(scroller.contentWidth - scroller.width, scroller.contentX - d));
                        }
                    }
                    // Middle-drag: up zooms in, down out, sideways pans; the time
                    // under the pointer at the press stays under the pointer.
                    PointHandler {
                        id: midZoom
                        objectName: "middleZoom"
                        acceptedButtons: Qt.MiddleButton
                        cursorShape: Qt.SizeVerCursor
                        property real anchorT: 0
                        property real z0: 1
                        property real y0: 0
                        readonly property real k: 0.01
                        function local(sp) { return scroller.mapFromItem(null, sp.x, sp.y); }
                        onActiveChanged: {
                            if (!active) return;
                            const p = local(point.scenePressPosition);
                            anchorT = (scroller.contentX + p.x) / tlv.pps;
                            z0 = tlv.zoom;
                            y0 = p.y;
                        }
                        onPointChanged: {
                            if (!active) return;
                            const p = local(point.scenePosition);
                            tlv.zoom = Math.max(1, Math.min(tlv.maxZoom, z0 * Math.exp(-(p.y - y0) * k)));
                            scroller.contentX = Math.max(0, Math.min(scroller.contentWidth - scroller.width, anchorT * tlv.pps - p.x));
                        }
                    }

                    Item {
                        id: lanes
                        width: scroller.contentWidth
                        height: scroller.height
                        // Visible recording window (s), for windowed repeaters.
                        readonly property real visA: scroller.contentX / tlv.pps
                        readonly property real visB: (scroller.contentX + scroller.width) / tlv.pps

                        // ── Ruler in output time ──
                        Item {
                            id: ruler
                            width: parent.width
                            height: 20
                            readonly property real step: {
                                const steps = [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300];
                                for (const s of steps) if (s * tlv.pps >= 70) return s;
                                return 600;
                            }
                            readonly property var ticks: {
                                tlv.doc.tl;
                                const out = [];
                                const a = tlv.doc.srcToOut(lanes.visA), b = tlv.doc.srcToOut(lanes.visB);
                                const k0 = Math.max(0, Math.floor(a / ruler.step)), k1 = Math.ceil(b / ruler.step);
                                for (let k = k0; k <= k1 && out.length < 400; ++k) {
                                    const to = k * ruler.step;
                                    if (to > tlv.doc.outDuration + 1e-6) break;
                                    out.push({ t: to, x: tlv.doc.outToSrc(to) * tlv.pps });
                                }
                                return out;
                            }
                            Repeater {
                                model: ruler.ticks
                                Item {
                                    required property var modelData
                                    x: modelData.x
                                    Rectangle { y: 14; width: 1; height: 6; color: Appearance.colors.colSubtext; opacity: 0.6 }
                                    StyledText {
                                        x: 3
                                        text: modelData.t >= 60 ? tlv.doc.fmt(modelData.t).replace(/\.\d+$/, "") : (Math.round(modelData.t * 100) / 100) + "s"
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.family: Appearance.font.family.monospace
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }
                            MouseArea {
                                id: rulerArea
                                anchors.fill: parent
                                hoverEnabled: true
                                objectName: "rulerArea"
                                cursorShape: Qt.SizeHorCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onPressed: (m) => {
                                    if (m.button === Qt.RightButton) tlv.rulerMenu(rulerArea, m.x, m.y, Math.max(0, Math.min(tlv.dur, m.x / tlv.pps)));
                                    else tlv.seekPx(m.x);
                                }
                                onPositionChanged: (m) => { if (pressed && (m.buttons & Qt.LeftButton)) tlv.seekPx(m.x); }
                            }
                            // Markers: click to go there, right-click to remove.
                            Repeater {
                                model: tlv.t ? (tlv.t.markers || []) : []
                                MaterialSymbol {
                                    required property var modelData
                                    required property int index
                                    objectName: "marker-" + index
                                    x: modelData.t * tlv.pps - width / 2
                                    y: 2
                                    text: "bookmark"
                                    fill: 1
                                    iconSize: 14
                                    color: Appearance.colors.colTertiary
                                    MouseArea {
                                        id: markerArea
                                        anchors { fill: parent; margins: -3 }
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: (m) => {
                                            const i = parent.index, mt = parent.modelData.t;
                                            if (m.button === Qt.RightButton) tlv.doc.menu(markerArea, m.x, m.y, [
                                                { icon: "location_on", label: "Go to marker", onTriggered: () => { tlv.doc.playing = false; tlv.doc.playhead = mt; } },
                                                { icon: "bookmark_remove", label: "Remove marker", danger: true, onTriggered: () => tlv.doc.removeMarker(i) }
                                            ]);
                                            else { tlv.doc.playing = false; tlv.doc.playhead = mt; }
                                        }
                                    }
                                }
                            }
                            StyledToolTip {
                                extraVisibleCondition: false
                                alternativeVisibleCondition: rulerArea.containsMouse
                                text: {
                                    const s = Math.max(0, rulerArea.mouseX / tlv.pps);
                                    return "Video " + tlv.doc.fmt(tlv.doc.srcToOut(s)) + "  ·  recording " + tlv.doc.fmt(s);
                                }
                            }
                        }

                        // Empty track space: move the playhead, drop the selection.
                        MouseArea {
                            id: laneArea
                            objectName: "laneArea"
                            anchors { left: parent.left; right: parent.right; top: ruler.bottom; bottom: parent.bottom }
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (m) => {
                                if (m.button === Qt.RightButton) tlv.laneMenu(laneArea, m.x, m.y, Math.max(0, Math.min(tlv.dur, m.x / tlv.pps)));
                                else { tlv.doc.selection = null; tlv.seekPx(m.x); }
                            }
                        }

                        // ── Clip track: filmstrip, trims, cuts, speed ──
                        Item {
                            id: clipTrack
                            y: ruler.height + 8
                            width: parent.width
                            height: 48
                            readonly property real trimS: tlv.t ? (tlv.t.clip.trim_start || 0) : 0
                            readonly property real trimE: tlv.t && tlv.t.clip.trim_end !== null && tlv.t.clip.trim_end !== undefined ? tlv.t.clip.trim_end : tlv.dur
                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.verysmall
                                color: Appearance.colors.colSecondaryContainer
                                clip: true
                                // Filmstrip: one thumb per slot, from the cached keyframes.
                                Repeater {
                                    model: {
                                        const a = tlv.doc.assets;
                                        if (!a || !a.thumbs) return [];
                                        const w = clipTrack.height * 16 / 10;
                                        const out = [];
                                        let last = -1e9;
                                        for (const th of a.thumbs) {
                                            const x = th.t * tlv.pps;
                                            if (x + 3 * w < scroller.contentX || x > scroller.contentX + scroller.width + w) continue;
                                            if (x - last < w) continue;
                                            last = x;
                                            out.push({ x: x, w: w, file: tlv.doc.assetsDir + "/" + th.file });
                                        }
                                        // Each thumb reaches the next one (cropped), so the strip has no gaps.
                                        for (let i = 0; i + 1 < out.length; ++i) out[i].w = Math.min(3 * w, out[i + 1].x - out[i].x);
                                        return out;
                                    }
                                    Image {
                                        required property var modelData
                                        x: modelData.x
                                        height: clipTrack.height
                                        width: modelData.w
                                        fillMode: Image.PreserveAspectCrop
                                        source: "file://" + modelData.file
                                        asynchronous: true
                                        sourceSize.height: 90
                                        opacity: 0.85
                                    }
                                }
                            }
                            // Trimmed-away ends.
                            Rectangle {
                                width: clipTrack.trimS * tlv.pps; height: parent.height
                                radius: Appearance.rounding.verysmall
                                color: Appearance.colors.colLayer0; opacity: 0.8
                            }
                            Rectangle {
                                x: clipTrack.trimE * tlv.pps; width: Math.max(0, parent.width - x); height: parent.height
                                radius: Appearance.rounding.verysmall
                                color: Appearance.colors.colLayer0; opacity: 0.8
                            }
                            Repeater {
                                model: tlv.t ? tlv.t.clip.speed : []
                                CastBlock {
                                    required property var modelData
                                    required property int index
                                    objectName: "block-speed-" + index
                                    id: speedBlk
                                    onMenuRequested: (x, y) => tlv.blockMenu(speedBlk, x, y, "speed", index)
                                    y: parent.height - height
                                    height: 22
                                    start: modelData.start; end: modelData.end
                                    minStart: tlv.lo(tlv.t.clip.speed, index); maxEnd: tlv.hi(tlv.t.clip.speed, index)
                                    pxPerSec: tlv.pps; duration: tlv.dur
                                    icon: "speed"; label: modelData.speed + "×"
                                    fill: Appearance.colors.colTertiaryContainer; onFill: Appearance.colors.colOnTertiaryContainer
                                    selected: tlv.sel("speed", index)
                                    onPicked: tlv.doc.selection = { track: "speed", index: index }
                                    onCommitted: (s, e) => tlv.doc.edit(t => { t.clip.speed[index].start = s; t.clip.speed[index].end = e; })
                                }
                            }
                            Repeater {
                                model: tlv.t ? tlv.t.clip.cuts : []
                                CastBlock {
                                    required property var modelData
                                    required property int index
                                    objectName: "block-cut-" + index
                                    id: cutBlk
                                    onMenuRequested: (x, y) => tlv.blockMenu(cutBlk, x, y, "cut", index)
                                    height: clipTrack.height
                                    start: modelData.start; end: modelData.end
                                    minStart: tlv.lo(tlv.t.clip.cuts, index); maxEnd: tlv.hi(tlv.t.clip.cuts, index)
                                    pxPerSec: tlv.pps; duration: tlv.dur
                                    icon: "content_cut"; label: "cut"
                                    fill: Appearance.colors.colErrorContainer; onFill: Appearance.colors.colOnErrorContainer
                                    selected: tlv.sel("cut", index)
                                    onPicked: tlv.doc.selection = { track: "cut", index: index }
                                    onCommitted: (s, e) => tlv.doc.edit(t => { t.clip.cuts[index].start = s; t.clip.cuts[index].end = e; })
                                }
                            }
                            // Trim handles.
                            Repeater {
                                model: 2
                                Rectangle {
                                    required property int index
                                    objectName: "trim-" + index
                                    readonly property real at: index === 0 ? clipTrack.trimS : clipTrack.trimE
                                    property real live: at
                                    property bool dragging: false
                                    x: (dragging ? live : at) * tlv.pps - width / 2
                                    width: 10; height: clipTrack.height + 6; y: -3
                                    radius: Appearance.rounding.full
                                    color: Appearance.colors.colPrimary
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "drag_indicator"
                                        iconSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnPrimary
                                    }
                                    MouseArea {
                                        anchors { fill: parent; margins: -4 }
                                        cursorShape: Qt.SizeHorCursor
                                        preventStealing: true
                                        onPressed: { parent.live = parent.at; parent.dragging = true; }
                                        onPositionChanged: (m) => {
                                            if (!pressed) return;
                                            const px = mapToItem(clipTrack, m.x, 0).x;
                                            const v = Math.max(0, Math.min(tlv.dur, px / tlv.pps));
                                            parent.live = index === 0 ? Math.min(v, clipTrack.trimE - 0.5) : Math.max(v, clipTrack.trimS + 0.5);
                                            tlv.doc.playhead = parent.live;
                                        }
                                        onReleased: {
                                            const v = parent.live;
                                            parent.dragging = false;
                                            tlv.doc.edit(t => { if (index === 0) t.clip.trim_start = v; else t.clip.trim_end = v >= t.source.duration - 0.01 ? null : v; });
                                        }
                                    }
                                }
                            }
                        }

                        // ── Audio waveform (visible window only) ──
                        Canvas {
                            id: wave
                            visible: tlv.hasWave
                            y: clipTrack.y + clipTrack.height + 8
                            x: scroller.contentX
                            width: scroller.width
                            height: 26
                            readonly property color ink: Appearance.colors.colPrimary
                            readonly property real a: lanes.visA
                            readonly property real pps: tlv.pps
                            onAChanged: requestPaint()
                            onPpsChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onVisibleChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                const w = tlv.doc.assets && tlv.doc.assets.wave;
                                if (!w) return;
                                ctx.fillStyle = ink;
                                const mid = height / 2;
                                for (let px = 0; px < width; px += 2) {
                                    const t0 = a + px / pps, t1 = a + (px + 2) / pps;
                                    let peak = 0;
                                    for (let i = Math.floor(t0 / w.bucket); i <= Math.floor(t1 / w.bucket) && i < w.peaks.length; ++i)
                                        if (i >= 0) peak = Math.max(peak, w.peaks[i]);
                                    const hh = Math.max(1, peak * (height - 2) / 2);
                                    ctx.fillRect(px, mid - hh, 1.5, hh * 2);
                                }
                            }
                            Connections { target: tlv.doc; function onAssetsChanged() { wave.requestPaint(); } }
                        }

                        // ── Zoom track ──
                        Item {
                            id: zoomTrack
                            y: (tlv.hasWave ? wave.y + wave.height : clipTrack.y + clipTrack.height) + 8
                            width: parent.width
                            height: tlv.trackH
                            Rectangle { anchors.fill: parent; radius: Appearance.rounding.verysmall; color: Appearance.colors.colLayer1 }
                            Repeater {
                                model: tlv.t ? tlv.t.segments : []
                                CastBlock {
                                    required property var modelData
                                    required property int index
                                    objectName: "block-zoom-" + index
                                    id: zoomBlk
                                    onMenuRequested: (x, y) => tlv.blockMenu(zoomBlk, x, y, "zoom", index)
                                    height: zoomTrack.height
                                    start: modelData.start; end: modelData.end
                                    minStart: tlv.lo(tlv.t.segments, index); maxEnd: tlv.hi(tlv.t.segments, index)
                                    pxPerSec: tlv.pps; duration: tlv.dur
                                    icon: modelData.focus ? "point_scan" : (modelData.kind === "typing" ? "keyboard" : (modelData.kind === "click" ? "ads_click" : "zoom_in"))
                                    label: modelData.zoom.toFixed(1) + "×"
                                    dim: tlv.t && !tlv.t.zoom.auto && modelData.kind !== "manual"
                                    fill: Appearance.colors.colPrimaryContainer; onFill: Appearance.colors.colOnPrimaryContainer
                                    selected: tlv.sel("zoom", index)
                                    onPicked: {
                                        tlv.doc.selection = { track: "zoom", index: index };
                                        // Show the zoomed state so a target can be clicked.
                                        if (tlv.doc.playhead < modelData.start || tlv.doc.playhead > modelData.end)
                                            tlv.doc.playhead = Math.min(modelData.end, modelData.start + Math.min(1.2, (modelData.end - modelData.start) / 2));
                                    }
                                    onCommitted: (s, e) => tlv.doc.edit(t => { t.segments[index].start = s; t.segments[index].end = e; t.segments[index].kind = "manual"; })
                                }
                            }
                        }

                        // ── Camera track ──
                        Item {
                            id: camTrack
                            visible: tlv.doc.hasWebcam
                            y: zoomTrack.y + tlv.trackH + 8
                            width: parent.width
                            height: tlv.trackH
                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.verysmall
                                color: Appearance.colors.colLayer1
                                StyledText {
                                    x: scroller.contentX + 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tlv.t && tlv.t.webcam && tlv.t.webcam.visible === false ? "Hidden" : "Bubble"
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            Repeater {
                                model: tlv.t && tlv.t.webcam ? tlv.t.webcam.segments : []
                                CastBlock {
                                    required property var modelData
                                    required property int index
                                    objectName: "block-camera-" + index
                                    id: camBlk
                                    onMenuRequested: (x, y) => tlv.blockMenu(camBlk, x, y, "camera", index)
                                    height: camTrack.height
                                    start: modelData.start; end: modelData.end
                                    minStart: tlv.lo(tlv.t.webcam.segments, index); maxEnd: tlv.hi(tlv.t.webcam.segments, index)
                                    pxPerSec: tlv.pps; duration: tlv.dur
                                    icon: ({ hidden: "videocam_off", bubble: "account_circle", fullscreen: "fullscreen" })[modelData.mode]
                                    label: modelData.mode
                                    fill: Appearance.colors.colSecondaryContainer; onFill: Appearance.colors.colOnSecondaryContainer
                                    selected: tlv.sel("camera", index)
                                    onPicked: tlv.doc.selection = { track: "camera", index: index }
                                    onCommitted: (s, e) => tlv.doc.edit(t => { t.webcam.segments[index].start = s; t.webcam.segments[index].end = e; })
                                }
                            }
                        }

                        // ── Window track: mode spans, and the window switches ──
                        Item {
                            id: windowTrack
                            objectName: "windowTrack"
                            visible: tlv.doc.hasWindows
                            y: cursorTrack.y + tlv.cursorH + 8
                            width: parent.width
                            height: tlv.cursorH
                            readonly property var segs: tlv.t && tlv.t.window ? (tlv.t.window.segments || []) : []
                            readonly property var switches: tlv.doc.windowSwitches()
                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.verysmall
                                color: Appearance.colors.colLayer1
                                StyledText {
                                    x: scroller.contentX + 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: ({ screen: "Screen", follow: "Follow focus", pin: "Pinned window" })[tlv.t && tlv.t.window ? tlv.t.window.mode : "screen"] ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            Repeater {
                                model: windowTrack.segs
                                CastBlock {
                                    id: windowBlk
                                    required property var modelData
                                    required property int index
                                    objectName: "block-window-" + index
                                    onMenuRequested: (x, y) => tlv.blockMenu(windowBlk, x, y, "window", index)
                                    height: windowTrack.height
                                    start: modelData.start; end: modelData.end
                                    minStart: tlv.lo(windowTrack.segs, index); maxEnd: tlv.hi(windowTrack.segs, index)
                                    pxPerSec: tlv.pps; duration: tlv.dur
                                    icon: ({ screen: "desktop_windows", follow: "ads_click", pin: "push_pin" })[modelData.mode]
                                    label: ({ screen: "Screen", follow: "Follow", pin: "Pin" })[modelData.mode]
                                    fill: Appearance.colors.colPrimaryContainer; onFill: Appearance.colors.colOnPrimaryContainer
                                    selected: tlv.sel("window", index)
                                    onPicked: tlv.doc.selection = { track: "window", index: index }
                                    onCommitted: (s, e) => tlv.doc.edit(t => { t.window.segments[index].start = s; t.window.segments[index].end = e; })
                                }
                            }
                            // Switch markers: right-click picks this switch's transition.
                            Repeater {
                                model: windowTrack.switches
                                Rectangle {
                                    required property var modelData
                                    required property int index
                                    objectName: "switch-" + index
                                    readonly property string kind: tlv.doc.switchTransition(modelData.t) ?? ""
                                    x: modelData.t * tlv.pps - width / 2
                                    y: (windowTrack.height - height) / 2
                                    width: 12; height: 12
                                    rotation: 45
                                    radius: 2
                                    color: kind.length > 0 ? Appearance.colors.colTertiary : (modelData.workspace ? Appearance.colors.colSecondary : Appearance.colors.colOnLayer1)
                                    border.width: 1
                                    border.color: Appearance.colors.colLayer0
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        hoverEnabled: true
                                        onClicked: (m) => {
                                            if (m.button === Qt.RightButton) tlv.switchMenu(parent, m.x, m.y, parent.modelData);
                                            else { tlv.doc.playing = false; tlv.doc.playhead = parent.modelData.t; }
                                        }
                                    }
                                    StyledToolTip { text: (parent.modelData.workspace ? "Workspace switch" : "Window switch") + " · " + (parent.kind.length > 0 ? parent.kind : "default transition") }
                                }
                            }
                        }

                        // ── Cursor track: spans where the cursor is hidden (or shown) ──
                        Item {
                            id: cursorTrack
                            objectName: "cursorTrack"
                            y: (camTrack.visible ? camTrack.y : zoomTrack.y) + tlv.trackH + 8
                            width: parent.width
                            height: tlv.cursorH
                            readonly property var segs: tlv.t && tlv.t.cursor ? (tlv.t.cursor.segments || []) : []
                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.verysmall
                                color: Appearance.colors.colLayer1
                                StyledText {
                                    x: scroller.contentX + 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tlv.t && tlv.t.cursor && tlv.t.cursor.visible === false ? "Hidden" : "Visible"
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            Repeater {
                                model: cursorTrack.segs
                                CastBlock {
                                    id: cursorBlk
                                    required property var modelData
                                    required property int index
                                    objectName: "block-cursor-" + index
                                    onMenuRequested: (x, y) => tlv.blockMenu(cursorBlk, x, y, "cursor", index)
                                    height: cursorTrack.height
                                    start: modelData.start; end: modelData.end
                                    minStart: tlv.lo(cursorTrack.segs, index); maxEnd: tlv.hi(cursorTrack.segs, index)
                                    pxPerSec: tlv.pps; duration: tlv.dur
                                    icon: modelData.visible ? "visibility" : "visibility_off"
                                    label: modelData.visible ? "Shown" : "Hidden"
                                    fill: Appearance.colors.colTertiaryContainer; onFill: Appearance.colors.colOnTertiaryContainer
                                    selected: tlv.sel("cursor", index)
                                    onPicked: tlv.doc.selection = { track: "cursor", index: index }
                                    onCommitted: (s, e) => tlv.doc.edit(t => { t.cursor.segments[index].start = s; t.cursor.segments[index].end = e; })
                                }
                            }
                        }

                        // ── Media lane: layers (when they show) and cut-ins, in output
                        // time mapped onto the recording; one row per layer (up to 4),
                        // the cut-ins on a row of their own ──
                        Item {
                            id: mediaTrack
                            objectName: "mediaTrack"
                            visible: tlv.doc.mediaRows > 0
                            y: (windowTrack.visible ? windowTrack.y : cursorTrack.y) + tlv.cursorH + 8
                            width: parent.width
                            readonly property var layers: tlv.t && tlv.t.media ? (tlv.t.media.layers || []) : []
                            readonly property var inserts: tlv.t && tlv.t.media ? (tlv.t.media.inserts || []) : []
                            readonly property int layerRows: Math.min(4, layers.length)
                            height: tlv.doc.mediaRows * (tlv.cursorH + 8) - 8
                            function pick(kind, i) {
                                tlv.doc.selection = null;
                                tlv.doc.layerSel = kind === "layer" ? i : -1;
                                tlv.doc.insertSel = kind === "insert" ? i : -1;
                                tlv.doc.showTab("media");
                            }
                            Repeater {
                                model: tlv.doc.mediaRows
                                Rectangle {
                                    required property int index
                                    y: index * (tlv.cursorH + 8)
                                    width: mediaTrack.width
                                    height: tlv.cursorH
                                    radius: Appearance.rounding.verysmall
                                    color: Appearance.colors.colLayer1
                                    StyledText {
                                        x: scroller.contentX + 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: index >= mediaTrack.layerRows
                                        text: "Cut in"
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }
                            Repeater {
                                model: mediaTrack.layers
                                CastBlock {
                                    id: layerBlk
                                    required property var modelData
                                    required property int index
                                    objectName: "block-layer-" + index
                                    y: (index % 4) * (tlv.cursorH + 8)
                                    height: tlv.cursorH
                                    // output seconds ⇄ recording seconds (cuts and speed-ups between)
                                    start: tlv.doc.outToSrc(modelData.at)
                                    end: modelData.dur > 0 ? tlv.doc.outToSrc(modelData.at + modelData.dur) : tlv.dur
                                    // "to the end" moves past the end and stays "to the end"
                                    maxEnd: modelData.dur > 0 ? tlv.dur : 1e9
                                    pxPerSec: tlv.pps; duration: tlv.dur
                                    icon: /\.(png|jpe?g|webp|gif|bmp|svg)$/i.test(modelData.file) ? "image" : "movie"
                                    label: modelData.name || modelData.file.split("/").pop()
                                    dim: !modelData.visible
                                    fill: Appearance.colors.colSecondaryContainer; onFill: Appearance.colors.colOnSecondaryContainer
                                    selected: tlv.doc.layerSel === index
                                    onPicked: mediaTrack.pick("layer", index)
                                    onMenuRequested: (x, y) => tlv.doc.menu(layerBlk, x, y, [
                                        { icon: modelData.visible ? "visibility_off" : "visibility", label: modelData.visible ? "Hide" : "Show",
                                          onTriggered: () => { const i = index; tlv.doc.edit(t => t.media.layers[i].visible = !t.media.layers[i].visible); } },
                                        { icon: "start", label: "Start at the playhead",
                                          onTriggered: () => { const i = index, at = tlv.doc.srcToOut(tlv.doc.playhead); tlv.doc.edit(t => t.media.layers[i].at = at); } },
                                        { icon: "last_page", label: "Show to the end",
                                          onTriggered: () => { const i = index; tlv.doc.edit(t => t.media.layers[i].dur = 0); } },
                                        { separator: true },
                                        { icon: "delete", label: "Remove layer", danger: true,
                                          onTriggered: () => { const i = index; tlv.doc.layerSel = -1; tlv.doc.edit(t => t.media.layers.splice(i, 1)); } }
                                    ])
                                    onCommitted: (s, e) => {
                                        const i = index, toEnd = e >= tlv.dur - 0.01;
                                        const at = Math.max(0, tlv.doc.srcToOut(s));
                                        const dur = toEnd ? 0 : Math.max(0.2, tlv.doc.srcToOut(e) - at);
                                        tlv.doc.edit(t => { t.media.layers[i].at = at; t.media.layers[i].dur = dur; });
                                    }
                                }
                            }
                            Repeater {
                                model: mediaTrack.inserts
                                CastBlock {
                                    id: insBlk
                                    required property var modelData
                                    required property int index
                                    objectName: "block-insert-" + index
                                    y: mediaTrack.layerRows * (tlv.cursorH + 8)
                                    height: tlv.cursorH
                                    // a point in output time; the clip itself is not on the recording
                                    resizable: false
                                    start: tlv.doc.outToSrc(modelData.at)
                                    end: start + 30 / tlv.pps
                                    maxEnd: tlv.dur + 30 / tlv.pps
                                    pxPerSec: tlv.pps; duration: tlv.dur
                                    icon: "splitscreen_add"
                                    fill: Appearance.colors.colTertiaryContainer; onFill: Appearance.colors.colOnTertiaryContainer
                                    selected: tlv.doc.insertSel === index
                                    onPicked: mediaTrack.pick("insert", index)
                                    onMenuRequested: (x, y) => tlv.doc.menu(insBlk, x, y, [
                                        { icon: "start", label: "Move to the playhead",
                                          onTriggered: () => { const i = index, at = tlv.doc.srcToOut(tlv.doc.playhead); tlv.doc.edit(t => t.media.inserts[i].at = at); } },
                                        { separator: true },
                                        { icon: "delete", label: "Remove cut-in", danger: true,
                                          onTriggered: () => { const i = index; tlv.doc.insertSel = -1; tlv.doc.edit(t => t.media.inserts.splice(i, 1)); } }
                                    ])
                                    onCommitted: (s, e) => { const i = index, at = Math.max(0, tlv.doc.srcToOut(s)); tlv.doc.edit(t => t.media.inserts[i].at = at); }
                                    StyledToolTip { text: (modelData.name || modelData.file.split("/").pop()) + " cut in at " + tlv.doc.fmt(modelData.at) }
                                }
                            }
                        }

                        // Playhead.
                        Rectangle {
                            x: tlv.doc.playhead * tlv.pps - 1
                            width: 2
                            height: parent.height
                            color: Appearance.colors.colPrimary
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 12; height: 12; radius: 6
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }

                // ── Overview: whole recording, the visible window, drag to scroll ──
                Item {
                    id: overview
                    objectName: "timelineOverview"
                    Layout.fillWidth: true
                    implicitHeight: 14
                    readonly property real k: width / tlv.dur
                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colLayer1
                    }
                    // Faint ticks where zooms are; not bars, so it never reads as a
                    // second scrollbar.
                    Repeater {
                        model: tlv.t ? tlv.t.segments : []
                        Rectangle {
                            required property var modelData
                            x: modelData.start * overview.k
                            width: Math.max(2, (modelData.end - modelData.start) * overview.k)
                            y: parent.height / 2 - 1; height: 2
                            radius: 1
                            color: Appearance.colors.colPrimary
                            opacity: 0.3
                        }
                    }
                    Rectangle {
                        x: tlv.doc.playhead * overview.k - 1
                        width: 2; height: parent.height
                        color: Appearance.colors.colPrimary
                    }
                    // The visible window (the whole bar when the timeline fits).
                    Rectangle {
                        id: viewBox
                        objectName: "overviewWindow"
                        x: scroller.contentX / tlv.pps * overview.k
                        width: Math.min(overview.width - x, Math.max(12, scroller.width / tlv.pps * overview.k))
                        height: parent.height
                        radius: Appearance.rounding.full
                        color: Qt.alpha(Appearance.colors.colPrimary, 0.12)
                        border.width: 1
                        border.color: Qt.alpha(Appearance.colors.colPrimary, tlv.zoom > 1.001 ? 0.9 : 0.35)
                    }
                    MouseArea {
                        anchors.fill: parent
                        function scrollTo(px) {
                            const t = px / overview.k;
                            scroller.contentX = Math.max(0, Math.min(scroller.contentWidth - scroller.width, t * tlv.pps - scroller.width / 2));
                        }
                        onPressed: (m) => scrollTo(m.x)
                        onPositionChanged: (m) => { if (pressed) scrollTo(m.x); }
                    }
                }
            }
        }
    }
}
