import qs.modules.common
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Io

/// Media layers on the paused canvas: each one that shows at the playhead,
/// as a still at the right moment of its source, where the export puts it.
/// Click a layer to select it; drag it to move, its corners to resize
/// (snaps to the canvas edges and centre; Shift keeps its shape). One undo
/// step per drag. While playing, the proxy video shows the real composite.
Item {
    id: root
    required property var doc
    property var layers: []
    property real outNow: 0
    property bool interactive: true

    /// Rect being dragged: { index, rect } (fractions), or null.
    property var live: null
    function rectOf(i) { return live && live.index === i ? live.rect : root.layers[i].rect; }

    function isImage(f) { return /\.(png|jpe?g|webp|gif|bmp|svg)$/i.test(f || ""); }
    /// Seconds into layer `l`'s source at output time `t`, or -1 when it is not shown.
    function srcTime(l, t) {
        if (!l.visible || t < l.at - 1e-6 || (l.dur > 0 && t >= l.at + l.dur)) return -1;
        let s = (t - l.at) * (l.speed || 1);
        const len = l.src_end > 0 ? l.src_end - l.src_start : 0;
        if (len > 0) s = l.looped ? s % len : Math.min(s, Math.max(0, len - 0.04));
        return l.src_start + s;
    }

    // Empty canvas: a click drops the layer selection.
    MouseArea {
        anchors.fill: parent
        enabled: root.interactive && root.doc.layerSel >= 0
        onClicked: root.doc.layerSel = -1
    }

    Repeater {
        model: root.layers.length
        Item {
            id: lay
            required property int index
            readonly property var l: root.layers[index]
            readonly property real st: l ? root.srcTime(l, root.outNow) : -1
            readonly property bool shown: st >= 0
            readonly property var r: root.rectOf(index)
            readonly property bool selected: root.doc.layerSel === index
            x: r[0] * root.width
            y: r[1] * root.height
            width: r[2] * root.width
            height: r[3] * root.height
            visible: shown || selected
            z: index

            // ── the picture: a file as is, a video as a still at `st` ──
            property string still: ""
            property int rev: 0
            property real stillT: -1
            Process {
                id: grab
                property string target: ""
                stderr: StdioCollector { id: grabErr }
                onExited: (code) => {
                    if (code === 0) { lay.still = grab.target; lay.rev++; }
                    else console.warn("castEditor: layer still: " + grabErr.text.trim());
                }
            }
            Timer {
                id: grabTimer
                interval: 120
                onTriggered: {
                    if (grab.running) { restart(); return; }
                    const t = Math.round(lay.st * 30) / 30;
                    if (t === lay.stillT && lay.still.length > 0) return;
                    lay.stillT = t;
                    grab.target = root.doc.dir + "/.cast-layer-" + lay.index + "-" + (lay.rev % 2) + ".png";
                    grab.command = ["ffmpeg", "-v", "error", "-y", "-ss", t.toFixed(3), "-i", root.doc.mediaPath(lay.l.file),
                                    "-frames:v", "1", "-vf", "scale='min(960,iw)':-2", grab.target];
                    grab.running = true;
                }
            }
            // `st` itself, not `shown`: in this handler `shown` may not have
            // caught up with the new `st` yet
            onStChanged: if (st >= 0 && l && !root.isImage(l.file)) grabTimer.restart()
            Component.onCompleted: if (st >= 0 && l && !root.isImage(l.file)) grabTimer.restart()

            Item {
                id: pic
                // contain: the box shrinks to the picture's shape, centred
                readonly property real aspect: img.implicitHeight > 0 ? img.implicitWidth / img.implicitHeight : lay.width / Math.max(1, lay.height)
                readonly property bool contain: !lay.l || lay.l.fit !== "cover"
                width: contain ? Math.min(lay.width, lay.height * aspect) : lay.width
                height: contain ? width / aspect : lay.height
                anchors.centerIn: parent
                visible: lay.shown
                opacity: lay.l ? (lay.l.opacity ?? 1) : 1
                layer.enabled: lay.l && lay.l.radius > 0
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: pic.width
                        height: pic.height
                        radius: (lay.l ? lay.l.radius : 0) * Math.min(pic.width, pic.height)
                    }
                }
                Image {
                    id: img
                    anchors.fill: parent
                    source: !lay.l ? "" : (root.isImage(lay.l.file) ? "file://" + root.doc.mediaPath(lay.l.file)
                                          : (lay.still.length > 0 ? "file://" + lay.still + "?" + lay.rev : ""))
                    cache: false
                    fillMode: pic.contain ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                    clip: true
                    smooth: true
                    asynchronous: true
                    mirror: lay.l ? !!lay.l.mirror : false
                }
            }

            // outline: on hover, and always for the selected one
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                visible: root.interactive && (lay.selected || bodyArea.containsMouse)
                border.width: lay.selected ? 2 : 1
                border.color: Appearance.colors.colPrimary
                opacity: lay.selected ? 1 : 0.6
            }

            // ── move ──
            MouseArea {
                id: bodyArea
                objectName: "layerBody-" + lay.index
                anchors.fill: parent
                enabled: root.interactive
                hoverEnabled: true
                preventStealing: true
                cursorShape: lay.selected ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.PointingHandCursor
                property point p0
                property var r0
                onPressed: (m) => {
                    root.doc.selection = null;
                    root.doc.insertSel = -1;
                    root.doc.layerSel = lay.index;
                    root.doc.showTab("media");
                    p0 = mapToItem(root, m.x, m.y);
                    r0 = lay.r.slice();
                }
                onPositionChanged: (m) => {
                    if (!pressed) return;
                    const p = mapToItem(root, m.x, m.y);
                    let x = r0[0] + (p.x - p0.x) / root.width, y = r0[1] + (p.y - p0.y) / root.height;
                    x = root.snap(x, r0[2]); y = root.snap(y, r0[3]);
                    root.live = { index: lay.index, rect: [x, y, r0[2], r0[3]] };
                }
                onReleased: root.commit()
            }

            // ── resize: the four corners ──
            Repeater {
                model: lay.selected && root.interactive ? 4 : 0
                Rectangle {
                    id: handle
                    required property int index
                    objectName: "layerHandle-" + index
                    readonly property bool atRight: index === 1 || index === 2
                    readonly property bool atBottom: index >= 2
                    width: 12; height: 12; radius: 3
                    x: (atRight ? lay.width : 0) - width / 2
                    y: (atBottom ? lay.height : 0) - height / 2
                    color: Appearance.colors.colPrimary
                    border.width: 2
                    border.color: Appearance.colors.colOnPrimary
                    MouseArea {
                        anchors { fill: parent; margins: -6 }
                        preventStealing: true
                        cursorShape: handle.atRight === handle.atBottom ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                        property point p0
                        property var r0
                        onPressed: (m) => { p0 = mapToItem(root, m.x, m.y); r0 = lay.r.slice(); }
                        onPositionChanged: (m) => {
                            if (!pressed) return;
                            const p = mapToItem(root, m.x, m.y);
                            const dx = (p.x - p0.x) / root.width, dy = (p.y - p0.y) / root.height;
                            const min = 0.04;
                            // the opposite corner stays where it is
                            let x0 = r0[0], y0 = r0[1], x1 = r0[0] + r0[2], y1 = r0[1] + r0[3];
                            if (handle.atRight) x1 = Math.max(x0 + min, root.snapEdge(x1 + dx)); else x0 = Math.min(x1 - min, root.snapEdge(x0 + dx));
                            if (handle.atBottom) y1 = Math.max(y0 + min, root.snapEdge(y1 + dy)); else y0 = Math.min(y1 - min, root.snapEdge(y0 + dy));
                            if (m.modifiers & Qt.ShiftModifier) {
                                // keep the shape: the width leads, the height follows
                                const k = (r0[3] * root.height) / (r0[2] * root.width);
                                const h = (x1 - x0) * root.width * k / root.height;
                                if (handle.atBottom) y1 = y0 + h; else y0 = y1 - h;
                            }
                            root.live = { index: lay.index, rect: [x0, y0, x1 - x0, y1 - y0] };
                        }
                        onReleased: root.commit()
                    }
                }
            }
        }
    }

    /// Snap a box's start so it lines up with the canvas edges or centre (within 1 %).
    function snap(v, len) {
        for (const t of [0, 0.5 - len / 2, 1 - len]) if (Math.abs(v - t) < 0.01) return t;
        return v;
    }
    function snapEdge(v) {
        for (const t of [0, 0.5, 1]) if (Math.abs(v - t) < 0.01) return t;
        return v;
    }
    function commit() {
        if (!root.live) return;
        const i = root.live.index, r = root.live.rect.map(v => Math.round(v * 10000) / 10000);
        root.live = null;
        const old = root.layers[i].rect;
        if (r.every((v, k) => Math.abs(v - old[k]) < 1e-4)) return;
        root.doc.edit(t => t.media.layers[i].rect = r);
    }
}
