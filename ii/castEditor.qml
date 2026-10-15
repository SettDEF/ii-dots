//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
// No text fields here: a plain compose input context keeps Qt off the Wayland
// text-input-v3 path, whose focus juggling logged
// "QWaylandTextInputv3::disableSurface ... but 0x0 is focused".
//@ pragma Env QT_IM_MODULE=compose

// tinct-cast editor. Launch:
//   CAST_DIR=<recording dir> qs -p ~/.config/quickshell/ii/castEditor.qml
// Optional: CAST_BIN=<path to tinct-cast>; CAST_SHOT=<png> renders the window
// to a file and quits (CAST_SHOT_TAB, CAST_SHOT_SEL=zoom:0, CAST_SHOT_T=<s>,
// CAST_SHOT_EXPORT=1 set the state first).

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.castEditor

ApplicationWindow {
    id: root
    visible: true
    width: 1680
    height: 1050
    minimumWidth: 1000
    minimumHeight: 680
    title: "tinct-cast"
    color: Appearance.colors.colLayer0
    // quickshell keeps running when its last window closes (it is made for
    // shells): without this every closed editor stayed alive in the background
    onClosing: Qt.quit()

    readonly property string shot: Quickshell.env("CAST_SHOT") || ""

    CastDoc {
        id: doc
        dir: (Quickshell.env("CAST_DIR") || "").replace(/\/$/, "")
        bin: Quickshell.env("CAST_BIN") || ""
        onLoaded: {
            const t = Number(Quickshell.env("CAST_SHOT_T") || "NaN");
            if (!isNaN(t)) doc.playhead = t;
            const sel = Quickshell.env("CAST_SHOT_SEL") || "";
            if (sel.length > 0) doc.selection = { track: sel.split(":")[0], index: Number(sel.split(":")[1] || 0) };
            // Test hook: drive the editor (edits, undo) before the screenshot.
            const script = Quickshell.env("CAST_SHOT_EVAL") || "";
            if (script.length > 0) eval(script);
        }
    }

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        doc.openMenu = (item, x, y, items) => { const p = item.mapToItem(stage, x, y); ctxMenu.popup(p.x, p.y, items); };
        const tab = Quickshell.env("CAST_SHOT_TAB") || "";
        if (tab.length > 0) inspector.tab = tab;
        if ((Quickshell.env("CAST_SHOT_EXPORT") || "").length > 0) exportDialog.open = true;
    }

    /// A text field has the keys: editor shortcuts stand back.
    readonly property bool typing: {
        const f = root.activeFocusItem;
        return !!f && (f.cursorPosition !== undefined && f.selectByMouse !== undefined);
    }
    readonly property real frameStep: 1 / 60
    /// Shortcut labels, shown in menus and tooltips.
    readonly property var keys: ({ play: "Space", split: "S", del: "Del", dup: "Ctrl+D", zoom: "Z", cut: "C", trimStart: "[", trimEnd: "]",
                                  loop: "L", back: "J", start: "Home", end: "End", prevEdit: "Shift+←", nextEdit: "Shift+→", exportIt: "Ctrl+E" })
    function stepPlayhead(d) { doc.playing = false; doc.playhead = Math.max(0, Math.min(doc.duration, doc.playhead + d)); }
    function seek(t) { doc.playing = false; doc.playhead = Math.max(0, Math.min(doc.duration, t)); }
    /// S: split the selected block at the playhead, else whatever block is under it.
    function splitHere() {
        const s = doc.selection;
        if (s && doc.splitAt(s.track, s.index, doc.playhead)) return true;
        for (const k of ["zoom", "speed", "cut", "camera"]) {
            const i = doc.blockAt(k, doc.playhead);
            if (i >= 0 && doc.splitAt(k, i, doc.playhead)) return true;
        }
        return false;
    }
    component Key: Shortcut { enabled: !root.typing && doc.ready }
    Key { sequences: ["Space", "K"]; onActivated: doc.togglePlay() }
    Key { sequence: StandardKey.Undo; onActivated: doc.undo() }
    Key { sequences: [StandardKey.Redo, "Ctrl+Shift+Z"]; onActivated: doc.redo() }
    // Arrows: a frame; Alt: a second; Shift: edit points; Ctrl: nudge the selected block.
    Key { sequence: "Left"; onActivated: root.stepPlayhead(-root.frameStep) }
    Key { sequence: "Right"; onActivated: root.stepPlayhead(root.frameStep) }
    Key { sequence: "Alt+Left"; onActivated: root.stepPlayhead(-1) }
    Key { sequence: "Alt+Right"; onActivated: root.stepPlayhead(1) }
    Key { sequence: "Shift+Left"; onActivated: root.seek(doc.prevEditPoint(doc.playhead)) }
    Key { sequence: "Shift+Right"; onActivated: root.seek(doc.nextEditPoint(doc.playhead)) }
    Key { sequence: "Ctrl+Left"; onActivated: doc.nudgeSelection(-0.1) }
    Key { sequence: "Ctrl+Right"; onActivated: doc.nudgeSelection(0.1) }
    Key { sequence: "Home"; onActivated: root.seek(doc.trimStart) }
    Key { sequence: "End"; onActivated: root.seek(doc.trimEnd) }
    Key { sequence: "J"; onActivated: root.stepPlayhead(-2) }
    Key { sequence: "L"; onActivated: doc.loop = !doc.loop }
    Key { sequence: "S"; onActivated: root.splitHere() }
    Key { sequence: "Ctrl+D"; onActivated: { const s = doc.selection; if (s) doc.duplicate(s.track, s.index); } }
    Key { sequence: "Z"; onActivated: doc.addAt("zoom") }
    Key { sequence: "C"; onActivated: doc.addAt("cut") }
    Key { sequence: "["; onActivated: doc.setTrim("start", doc.playhead) }
    Key { sequence: "]"; onActivated: doc.setTrim("end", doc.playhead) }
    Key { sequence: "Ctrl+E"; onActivated: exportDialog.open = true }
    Key { sequences: [StandardKey.Delete, "Backspace"]; onActivated: doc.deleteSelection() }
    Shortcut { sequence: "Escape"; onActivated: { if (ctxMenu.opened) ctxMenu.dismiss(); else if (exportDialog.open) exportDialog.open = false; else doc.selection = null; } }

    Rectangle {
        id: stage
        anchors.fill: parent
        color: Appearance.colors.colLayer0

        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            visible: doc.dir.length > 0

            CastTopBar {
                Layout.fillWidth: true
                doc: doc
                onExportRequested: exportDialog.open = true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                CastPreview {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    doc: doc
                }
                Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Appearance.colors.colLayer0Border }
                CastInspector {
                    id: inspector
                    Layout.preferredWidth: 400
                    Layout.fillHeight: true
                    doc: doc
                    onExportRequested: exportDialog.open = true
                }
            }

            CastTimeline {
                objectName: "timeline"
                Layout.fillWidth: true
                Layout.preferredHeight: 214 + 36 + (doc.hasWindows ? 36 : 0) + (doc.assets && doc.assets.wave ? 34 : 0) + (doc.hasWebcam ? 48 : 0) + doc.mediaRows * 36
                doc: doc
            }
        }

        // No recording given: recents, open, record new.
        CastStart {
            anchors.fill: parent
            visible: doc.dir.length === 0
            doc: doc
        }

        CastExportDialog {
            id: exportDialog
            anchors.fill: parent
            doc: doc
        }

        CastToast {
            id: toast
            anchors { right: parent.right; bottom: parent.bottom; margins: 20 }
            doc: doc
        }

        // One context menu for the whole window; components ask for it via doc.menu().
        PopupContextMenu {
            id: ctxMenu
            objectName: "contextMenu"
            panelWidth: 260
        }
    }

    // Test mode (CAST_TEST=<js>): once the first frame is in, run the script
    // with `drag`, `click` and `find(objectName)` available, then screenshot.
    Loader {
        id: tester
        active: (Quickshell.env("CAST_TEST") || "").length > 0
        sourceComponent: CastTester {}
    }
    function find(name, item) {
        // From the window root: popups live beside contentItem.
        item = item || ctxMenu.overlayHost;
        if (item.objectName === name) return item;
        for (const c of item.children) {
            const r = root.find(name, c);
            if (r) return r;
        }
        if (item.contentItem && item.contentItem !== item) return root.find(name, item.contentItem);
        return null;
    }
    function drag(name, x, y, dx, dy) {
        const it = root.find(name);
        if (!it) { console.warn("castEditor test: no item " + name); return; }
        // Map once to the stage: the dragged item moves under the pointer.
        const p = it.mapToItem(stage, x < 0 ? it.width + x : x, y < 0 ? it.height / 2 : y);
        tester.item.drag(stage, p.x, p.y, dx, dy || 0);
    }
    function click(name, x, y) {
        const it = root.find(name);
        if (!it) { console.warn("castEditor test: no item " + name); return; }
        const p = it.mapToItem(stage, x, y);
        tester.item.click(stage, p.x, p.y);
    }
    /// Right-click item `name` at (x, y) (item coords; negative = from the far edge).
    function rclick(name, x, y) {
        const it = root.find(name);
        if (!it) { console.warn("castEditor test: no item " + name); return; }
        const p = it.mapToItem(stage, x < 0 ? it.width + x : x, y < 0 ? it.height + y : y);
        tester.item.click(stage, p.x, p.y, Qt.RightButton);
    }
    /// Click a context-menu row by label (hover first, so submenus open).
    function pick(label) {
        const it = root.find("menuItem:" + label);
        if (!it) { console.warn("castEditor test: no menu row " + label); return false; }
        const p = it.mapToItem(stage, it.width / 2, it.height / 2);
        tester.item.hover(stage, p.x, p.y);
        tester.item.click(stage, p.x, p.y);
        return true;
    }
    property bool testRan: false
    property var lastSaved: null
    property var firstOut: ""
    property var p1: ""
    property var laneT: 0
    property var loopBlock: ""
    property var calls: []
    /// A test script can hold the screenshot until it is done.
    property bool holdShot: false
    Timer {
        running: tester.status === Loader.Ready && (doc.frameRev > 0 || doc.dir.length === 0) && !root.testRan
        interval: 600
        onTriggered: {
            root.testRan = true;
            try { eval(Quickshell.env("CAST_TEST")); } catch (e) { console.warn("castEditor test failed: " + e); }
        }
    }

    // Screenshot mode: wait for the first exact frame, then grab and quit.
    Timer {
        running: root.shot.length > 0 && (doc.frameRev > 0 || (doc.dir.length === 0 && root.testRan)) && !doc.proxyBusy && exportDialog.phase !== "running" && (tester.status !== Loader.Ready || root.testRan) && !doc.frameProc.running && !root.holdShot
        interval: 1200
        // The window root: menus and popups live beside the content item.
        onTriggered: { const ok = ctxMenu.overlayHost.grabToImage(r => { r.saveToFile(root.shot); Qt.quit(); }); if (!ok) stage.grabToImage(r => { r.saveToFile(root.shot); Qt.quit(); }); }
    }
    Timer {
        running: root.shot.length > 0
        interval: 60000
        onTriggered: { console.warn("castEditor: screenshot timed out"); Qt.quit(); }
    }
}
