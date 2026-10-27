//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_IM_MODULE=compose

// Mocap correction editor: drag the detected skeleton onto the dancer where
// the detection is off; mark frames that show somebody else. Launch:
//   MOCAP_DIR=<video dir> MOCAP_WHO=dancer qs -p ~/.config/quickshell/mocap/mocapEditor.qml
// Reads <dir>/frames/NNNNN.jpg and <dir>/lift_<who>.jsonl, writes
// <dir>/corrections_<who>.json (applied by `posetrack correct`).
// MOCAP_SHOT=<png> renders the window to a file and quits (MOCAP_FRAME=<n>).

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ApplicationWindow {

    // browser-like scrolling for every list in the window (Momentum.qml)

    MomentumInjector { root: parent }
    id: root
    visible: true
    width: 1500
    height: 1000
    minimumWidth: 900
    minimumHeight: 640
    title: "Mocap corrections — " + who
    color: theme.layer0

    readonly property string dir: (Quickshell.env("MOCAP_DIR") || "").replace(/\/$/, "")
    readonly property string who: Quickshell.env("MOCAP_WHO") || "dancer"
    readonly property string shot: Quickshell.env("MOCAP_SHOT") || ""

    // BlazePose landmarks that can be corrected, with their names.
    readonly property var joints: [
        [0, "Head"], [11, "Shoulder L"], [12, "Shoulder R"], [13, "Elbow L"], [14, "Elbow R"],
        [15, "Wrist L"], [16, "Wrist R"], [23, "Hip L"], [24, "Hip R"], [25, "Knee L"], [26, "Knee R"],
        [27, "Ankle L"], [28, "Ankle R"], [29, "Heel L"], [30, "Heel R"], [31, "Toe L"], [32, "Toe R"]
    ]
    readonly property var bones: [[11, 12], [11, 13], [13, 15], [12, 14], [14, 16], [11, 23], [12, 24], [23, 24],
        [23, 25], [25, 27], [24, 26], [26, 28], [27, 29], [27, 31], [29, 31], [28, 30], [28, 32], [30, 32], [0, 11], [0, 12]]

    // The shell's tinct palette, read straight from its generated colours
    // (no shell services: the editor also runs headless for tests).
    QtObject {
        id: theme
        property var c: ({})
        readonly property color layer0: c.background || "#191a21"
        readonly property color layer1: c.surface_container_high || "#282a36"
        readonly property color layer2: c.outline_variant || "#44475a"
        readonly property color onLayer: c.on_surface || "#f8f8f2"
        readonly property color subtext: Qt.rgba(onLayer.r, onLayer.g, onLayer.b, 0.6)
        readonly property color primary: c.primary || "#bd93f9"
        readonly property color primaryContainer: c.primary_container || "#44475a"
        readonly property color onPrimaryContainer: c.on_primary_container || "#f8f8f2"
        readonly property color error: c.error || "#ffb86c"
    }
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell/user/generated/colors.json"
        onLoaded: { try { theme.c = JSON.parse(text()); } catch (e) {} }
    }

    property var frames: []          // per frame: {img: [[x,y,v]...], world: [[x,y,z]...]}
    property int frame: 0
    property var points: ({})        // "frame" -> {"lm": [x, y]}
    property var bad: []             // frames showing somebody else / unusable
    property int selected: -1        // landmark being edited
    property bool dirty: false
    property int rev: 0              // bumped on every edit, re-evaluates bindings

    function pt(f, lm) {
        const c = points[String(f)];
        if (c && c[String(lm)]) return c[String(lm)];
        const d = frames[f];
        return d ? [d.img[lm][0], d.img[lm][1]] : [0, 0];
    }
    function corrected(f, lm) { const c = points[String(f)]; return !!(c && c[String(lm)]); }
    function setPoint(f, lm, x, y) {
        const p = Object.assign({}, points);
        const c = Object.assign({}, p[String(f)] || {});
        c[String(lm)] = [Math.round(x * 10) / 10, Math.round(y * 10) / 10];
        p[String(f)] = c;
        points = p; dirty = true; rev++;
    }
    function resetPoint(f, lm) {
        const p = Object.assign({}, points);
        const c = Object.assign({}, p[String(f)] || {});
        delete c[String(lm)];
        if (Object.keys(c).length === 0) delete p[String(f)]; else p[String(f)] = c;
        points = p; dirty = true; rev++;
    }
    function toggleBad(f) {
        const b = bad.slice();
        const i = b.indexOf(f);
        if (i >= 0) b.splice(i, 1); else { b.push(f); b.sort((a, c) => a - c); }
        bad = b; dirty = true; rev++;
    }
    /// metres per video pixel at frame f: the torso's 3D length over its screen length
    function mPerPx(f) {
        const d = frames[f];
        if (!d) return 0;
        const mid = (a, b, arr) => [(arr[a][0] + arr[b][0]) / 2, (arr[a][1] + arr[b][1]) / 2, ((arr[a][2] || 0) + (arr[b][2] || 0)) / 2];
        const si = mid(11, 12, d.img), hi = mid(23, 24, d.img);
        const sw = mid(11, 12, d.world), hw = mid(23, 24, d.world);
        const px = Math.hypot(si[0] - hi[0], si[1] - hi[1]);
        const m = Math.hypot(sw[0] - hw[0], sw[1] - hw[1], sw[2] - hw[2]);
        return px > 1 ? m / px : 0;
    }
    function errPx(f, lm) {
        const d = frames[f]; const c = points[String(f)];
        if (!d || !c || !c[String(lm)]) return -1;
        return Math.hypot(c[String(lm)][0] - d.img[lm][0], c[String(lm)][1] - d.img[lm][1]);
    }
    /// Accuracy over every correction: per joint and overall, in px and cm.
    readonly property var accuracy: {
        rev;
        const per = {}; let n = 0, sumPx = 0, sumCm = 0;
        for (const fk of Object.keys(points)) {
            const f = Number(fk); const s = mPerPx(f);
            for (const lk of Object.keys(points[fk])) {
                const e = errPx(f, Number(lk));
                if (e < 0) continue;
                const a = per[lk] || { n: 0, px: 0, cm: 0 };
                a.n++; a.px += e; a.cm += e * s * 100; per[lk] = a;
                n++; sumPx += e; sumCm += e * s * 100;
            }
        }
        return { per: per, n: n, px: n ? sumPx / n : 0, cm: n ? sumCm / n : 0, frames: Object.keys(points).length };
    }

    function save() {
        out.setText(JSON.stringify({ version: 1, who: who, points: points, bad: bad }, null, 1));
        dirty = false;
    }
    function go(f) { frame = Math.max(0, Math.min(frames.length - 1, f)); selected = -1; }

    FileView {
        id: lift
        path: root.dir + "/lift_" + root.who + ".jsonl"
        onLoaded: {
            const out = [];
            for (const l of text().split("\n")) {
                if (l.length < 2) continue;
                const o = JSON.parse(l);
                out.push({ img: o.img, world: o.world });
            }
            root.frames = out;
            const f = Number(Quickshell.env("MOCAP_FRAME") || "NaN");
            if (!isNaN(f)) root.go(f);
            if (root.shot.length > 0) shotTimer.start();
        }
    }
    FileView {
        id: out
        path: root.dir + "/corrections_" + root.who + ".json"
        onLoaded: {
            try {
                const o = JSON.parse(text());
                root.points = o.points || {};
                root.bad = o.bad || [];
                root.rev++;
            } catch (e) {}
        }
    }
    Timer { id: shotTimer; interval: 800; onTriggered: stage.grabToImage(r => { r.saveToFile(root.shot); Qt.quit(); }) }



    Shortcut { sequence: "Right"; onActivated: root.go(root.frame + 1) }
    Shortcut { sequence: "Left"; onActivated: root.go(root.frame - 1) }
    Shortcut { sequence: "Shift+Right"; onActivated: root.go(root.frame + 10) }
    Shortcut { sequence: "Shift+Left"; onActivated: root.go(root.frame - 10) }
    Shortcut { sequence: "B"; onActivated: root.toggleBad(root.frame) }
    Shortcut { sequence: "Ctrl+S"; onActivated: root.save() }
    Shortcut { sequence: "Delete"; onActivated: if (root.selected >= 0) root.resetPoint(root.frame, root.selected) }
    Shortcut { sequence: "N"; onActivated: { const k = Object.keys(root.points).map(Number).filter(f => f > root.frame).sort((a, b) => a - b); if (k.length) root.go(k[0]); } }
    Shortcut { sequence: "P"; onActivated: { const k = Object.keys(root.points).map(Number).filter(f => f < root.frame).sort((a, b) => b - a); if (k.length) root.go(k[0]); } }

    Rectangle {
        id: stage
        anchors.fill: parent
        color: theme.layer0

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            // ── the frame, the skeleton, the handles ─────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 17
                    color: theme.layer1
                    clip: true

                    Flickable {
                        id: flick
                        anchors.fill: parent
                        anchors.margins: 6
                        property real zoom: 1
                        contentWidth: width * zoom
                        contentHeight: height * zoom
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: zoom > 1

                        WheelHandler {
                            acceptedModifiers: Qt.ControlModifier
                            onWheel: e => {
                                const old = flick.zoom;
                                flick.zoom = Math.max(1, Math.min(8, flick.zoom * (e.angleDelta.y > 0 ? 1.25 : 0.8)));
                                const k = flick.zoom / old;
                                flick.contentX = Math.max(0, (flick.contentX + e.x) * k - e.x);
                                flick.contentY = Math.max(0, (flick.contentY + e.y) * k - e.y);
                            }
                        }

                        Item {
                            id: view
                            width: flick.contentWidth
                            height: flick.contentHeight

                            Image {
                                id: img
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectFit
                                source: root.dir.length ? "file://" + root.dir + "/frames/" + String(root.frame + 1).padStart(5, "0") + ".jpg" : ""
                                asynchronous: false
                                cache: false
                                smooth: true
                                // video px → view coordinates
                                readonly property real sc: sourceSize.width > 0 ? paintedWidth / sourceSize.width : 1
                                readonly property real ox: (width - paintedWidth) / 2
                                readonly property real oy: (height - paintedHeight) / 2
                            }

                            Canvas {
                                id: bonesCanvas
                                anchors.fill: parent
                                property int dep: root.rev + root.frame + (img.status === Image.Ready ? 1 : 0) + Math.round(flick.zoom * 100)
                                onDepChanged: requestPaint()
                                onPaint: {
                                    const ctx = getContext("2d");
                                    ctx.reset();
                                    if (!root.frames[root.frame]) return;
                                    const isBad = root.bad.indexOf(root.frame) >= 0;
                                    const map = p => [img.ox + p[0] * img.sc, img.oy + p[1] * img.sc];
                                    // detection (thin, dim) under the corrected skeleton (thick)
                                    ctx.lineWidth = 1.5;
                                    ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.35);
                                    for (const b of root.bones) {
                                        const a = map(root.frames[root.frame].img[b[0]]), c = map(root.frames[root.frame].img[b[1]]);
                                        ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(c[0], c[1]); ctx.stroke();
                                    }
                                    ctx.lineWidth = 3;
                                    ctx.strokeStyle = isBad ? theme.error : theme.primary;
                                    for (const b of root.bones) {
                                        const a = map(root.pt(root.frame, b[0])), c = map(root.pt(root.frame, b[1]));
                                        ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(c[0], c[1]); ctx.stroke();
                                    }
                                }
                            }

                            Repeater {
                                model: root.joints
                                delegate: Rectangle {
                                    id: handle
                                    required property var modelData
                                    readonly property int lm: modelData[0]
                                    readonly property var p: { root.rev; return root.pt(root.frame, lm); }
                                    readonly property bool fixed: { root.rev; return root.corrected(root.frame, lm); }
                                    width: 14; height: 14; radius: 7
                                    x: img.ox + p[0] * img.sc - width / 2
                                    y: img.oy + p[1] * img.sc - height / 2
                                    visible: root.frames.length > 0
                                    color: fixed ? theme.primary : theme.layer2
                                    border.width: root.selected === lm ? 3 : 1.5
                                    border.color: root.selected === lm ? theme.onLayer : theme.primary
                                    DragHandler {
                                        target: null
                                        cursorShape: Qt.ClosedHandCursor
                                        property var start
                                        onActiveChanged: if (active) { root.selected = handle.lm; start = handle.p; }
                                        onTranslationChanged: if (active)
                                            root.setPoint(root.frame, handle.lm, start[0] + translation.x / img.sc, start[1] + translation.y / img.sc)
                                    }
                                    TapHandler { onTapped: root.selected = handle.lm }
                                    HoverHandler { id: hov; cursorShape: Qt.OpenHandCursor }
                                    ToolTip.visible: hov.hovered
                                    ToolTip.text: modelData[1]
                                }
                            }
                        }
                    }
                }

                // ── timeline: corrected frames (accent), bad frames (error) ──
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: 12
                    color: theme.layer1
                    Repeater {
                        model: { root.rev; return Object.keys(root.points).map(Number); }
                        delegate: Rectangle {
                            required property var modelData
                            x: 8 + (parent.width - 16) * modelData / Math.max(1, root.frames.length - 1) - 1
                            y: 6; width: 3; height: parent.height - 12; radius: 1
                            color: theme.primary
                        }
                    }
                    Repeater {
                        model: { root.rev; return root.bad; }
                        delegate: Rectangle {
                            required property var modelData
                            x: 8 + (parent.width - 16) * modelData / Math.max(1, root.frames.length - 1) - 1
                            y: 6; width: 3; height: parent.height - 12; radius: 1
                            color: theme.error
                        }
                    }
                    Rectangle {
                        x: 8 + (parent.width - 16) * root.frame / Math.max(1, root.frames.length - 1) - 1
                        y: 2; width: 2; height: parent.height - 4
                        color: theme.onLayer
                    }
                    MouseArea {
                        anchors.fill: parent
                        function seek(mx) { root.go(Math.round((mx - 8) / (width - 16) * (root.frames.length - 1))); }
                        onPressed: m => seek(m.x)
                        onPositionChanged: m => { if (pressed) seek(m.x); }
                    }
                }
            }

            // ── inspector ─────────────────────────────────────────────────
            Rectangle {
                Layout.preferredWidth: 330
                Layout.fillHeight: true
                radius: 17
                color: theme.layer1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 14

                    ColumnLayout {
                        spacing: 2
                        Text {
                            text: "Frame " + root.frame + " / " + Math.max(0, root.frames.length - 1)
                            color: theme.onLayer
                            font.pixelSize: 19
                            font.family: "monospace"
                        }
                        Text {
                            text: (root.frame / 30).toFixed(2) + " s · " + root.who + (root.bad.indexOf(root.frame) >= 0 ? " · marked unusable" : "")
                            color: root.bad.indexOf(root.frame) >= 0 ? theme.error : theme.subtext
                            font.pixelSize: 15
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitWidth: 0
                        Layout.maximumWidth: 298
                        implicitHeight: accCol.implicitHeight + 24
                        radius: 12
                        color: theme.layer2
                        ColumnLayout {
                            id: accCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 4
                            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: "Detection accuracy"; color: theme.onLayer; font.bold: true; font.pixelSize: 15 }
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: root.accuracy.n
                                    ? "off by " + root.accuracy.cm.toFixed(1) + " cm (" + root.accuracy.px.toFixed(0) + " px) on average"
                                    : "drag points onto the dancer to measure"
                                color: theme.onLayer
                                font.pixelSize: 12
                            }
                            Text {
                                text: root.accuracy.n + " points in " + root.accuracy.frames + " frames · " + root.bad.length + " unusable"
                                color: theme.subtext
                                font.pixelSize: 10
                            }
                        }
                    }

                    Text { text: "Joints (this frame · all corrections)"; color: theme.subtext; font.pixelSize: 12 }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.joints
                        spacing: 2
                        delegate: Rectangle {
                            required property var modelData
                            readonly property int lm: modelData[0]
                            readonly property real here: { root.rev; return root.errPx(root.frame, lm); }
                            readonly property var all: { root.rev; return root.accuracy.per[String(lm)]; }
                            width: ListView.view.width
                            height: 28
                            radius: 8
                            color: root.selected === lm ? theme.primaryContainer : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData[1]
                                    color: root.selected === lm ? theme.onPrimaryContainer : theme.onLayer
                                    font.pixelSize: 12
                                }
                                Text {
                                    text: here >= 0 ? (here * root.mPerPx(root.frame) * 100).toFixed(1) + " cm" : "—"
                                    color: here >= 0 ? theme.primary : theme.subtext
                                    font.pixelSize: 12
                                    font.family: "monospace"
                                }
                                Text {
                                    Layout.preferredWidth: 70
                                    horizontalAlignment: Text.AlignRight
                                    text: all ? "⌀ " + (all.cm / all.n).toFixed(1) : ""
                                    color: theme.subtext
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                }
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.selected = lm }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        implicitWidth: 0
                        Layout.maximumWidth: 298
                        spacing: 6
                        Button { Layout.fillWidth: true; Layout.preferredWidth: 1; text: root.bad.indexOf(root.frame) >= 0 ? "Usable" : "Unusable"; onClicked: root.toggleBad(root.frame) }
                        Button { Layout.fillWidth: true; Layout.preferredWidth: 1; text: "Reset"; enabled: root.selected >= 0; onClicked: root.resetPoint(root.frame, root.selected) }
                        Button { Layout.fillWidth: true; Layout.preferredWidth: 1; text: root.dirty ? "Save ●" : "Saved"; highlighted: root.dirty; onClicked: root.save() }
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: "←/→ frame · Shift ±10 · N/P next/previous correction · Ctrl+wheel zoom · B unusable · Del reset point · Ctrl+S save"
                        color: theme.subtext
                        font.pixelSize: 10
                    }
                }
            }
        }
    }
}
