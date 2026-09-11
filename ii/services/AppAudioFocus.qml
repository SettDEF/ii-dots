pragma Singleton
pragma ComponentBehavior: Bound

// Per-app "audio follows focus" manager.
//
// Each output stream (sink-input) can be set to one of three modes:
//   0  Always play        (default; unmanaged — we never touch its mute)
//   1  Only on workspace   (muted unless one of its windows is on an active workspace)
//   2  Only when focused   (muted unless one of its windows is the focused window)
//
// Streams are mapped to windows by PID (PipeWire "application.process.id"
// ↔ Hyprland client "pid"). HyprlandData refreshes on every Hyprland event,
// so windowList changes drive re-evaluation on focus/workspace changes.
//
// Opt-in by design: a stream in mode 0 is left completely alone, so nothing
// goes silent until you explicitly configure it.

import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // { appKey: mode } — only non-zero modes are stored.
    property var modes: ({})

    // Stable key for a stream, preferred to survive restarts.
    function appKey(node) {
        if (!node)
            return "";
        return (node.properties?.["application.name"]) || node.name || "";
    }

    function getMode(node) {
        return root.modes[appKey(node)] ?? 0;
    }

    function setMode(node, mode) {
        const key = appKey(node);
        if (key.length === 0)
            return;
        const next = Object.assign({}, root.modes);
        if (mode === 0)
            delete next[key];
        else
            next[key] = mode;
        root.modes = next;
        modesFile.setText(JSON.stringify(root.modes));
        // Back to "always" → clear any mute we imposed.
        if (mode === 0 && node.audio)
            node.audio.muted = false;
        Qt.callLater(root.reevaluate);
    }

    function cycleMode(node) {
        root.setMode(node, (root.getMode(node) + 1) % 3);
    }

    function modeName(mode) {
        return mode === 1 ? Translation.tr("On workspace")
            : mode === 2 ? Translation.tr("When focused")
            : Translation.tr("Always");
    }

    function modeIcon(mode) {
        return mode === 1 ? "select_window"
            : mode === 2 ? "recenter"
            : "volume_up";
    }

    function _pidOf(node) {
        const p = node?.properties?.["application.process.id"];
        return p !== undefined ? parseInt(p) : -1;
    }

    // Should this stream be audible right now, given its mode?
    function _shouldBeAudible(node, mode) {
        const pid = _pidOf(node);
        if (pid < 0)
            return true;                       // no PID → never silence blindly
        const wins = HyprlandData.windowList.filter(w => w.pid === pid);
        if (wins.length === 0)
            return true;                       // no mapped window → leave audible
        if (mode === 2)
            return wins.some(w => w.focusHistoryID === 0);
        // mode 1: audible if any window is on a currently-active workspace.
        const activeWs = HyprlandData.monitors
            .map(m => m.activeWorkspace?.id)
            .filter(x => x !== undefined);
        return wins.some(w => activeWs.includes(w.workspace?.id));
    }

    // Apply mute state to every managed stream.
    function reevaluate() {
        const nodes = Audio.outputAppNodes;
        for (let i = 0; i < nodes.length; i++) {
            const n = nodes[i];
            const mode = getMode(n);
            if (mode === 0 || !n.audio)
                continue;                       // unmanaged → untouched
            const audible = _shouldBeAudible(n, mode);
            if (n.audio.muted === audible)      // only write on real change
                n.audio.muted = !audible;
        }
    }

    // Focus / workspace changes arrive as windowList refreshes.
    Connections {
        target: HyprlandData
        function onWindowListChanged() { root.reevaluate(); }
    }
    // New/removed streams.
    Connections {
        target: Audio
        function onOutputAppNodesChanged() { Qt.callLater(root.reevaluate); }
    }

    FileView {
        id: modesFile
        path: Qt.resolvedUrl(`${Directories.state}/user/appAudioFocus.json`)
        onLoaded: {
            try {
                root.modes = JSON.parse(modesFile.text() || "{}");
            } catch (e) {
                root.modes = ({});
            }
            Qt.callLater(root.reevaluate);
        }
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound)
                modesFile.setText("{}");
        }
    }
}
