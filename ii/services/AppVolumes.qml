pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell

/**
 * Per-app output volume for every OPEN application, not just the ones making
 * noise right now.
 *
 * PipeWire only creates a node while an app is actually playing, so a silent
 * Telegram has nothing to control. This merges two sources:
 *   - live streams  (Audio.outputAppNodes) — real, immediate control
 *   - open windows  (HyprlandData.windowList) — apps with no stream yet
 *
 * For the second group the level is remembered here and applied to the app's
 * stream the moment it opens one. WirePlumber's own stream-properties db was
 * the obvious source but is useless for this: it is full of dead entries
 * (installers, keygen.exe, Wine hosts) and holds nothing for an app that has
 * never played a sound — which is exactly the case we care about.
 */
Singleton {
    id: root

    // Window classes that never produce app audio, or that are this shell.
    readonly property var _ignoredClasses: ["qs", "quickshell", "qml"]

    property var storedVolumes: ({})

    function _loadStored() {
        try {
            root.storedVolumes = JSON.parse(Persistent.states.audio.appVolumes || "{}") ?? ({});
        } catch (e) {
            root.storedVolumes = ({});
        }
    }
    function _persist() {
        Persistent.states.audio.appVolumes = JSON.stringify(root.storedVolumes);
    }
    Component.onCompleted: {
        root._loadStored();
        root.rows = root._buildRows();
    }

    // Normalised identity shared by a window class and a PipeWire app name:
    // "TelegramDesktop" / "org.telegram.desktop" / "telegram.exe" → "telegram".
    function appKey(str) {
        let s = String(str ?? "").toLowerCase();
        if (s.length === 0) return "";
        s = s.replace(/\.(exe|desktop|so)$/, "");
        const dot = s.lastIndexOf(".");
        if (dot >= 0 && dot < s.length - 1) s = s.slice(dot + 1);   // reverse-DNS tail
        return s.replace(/[^a-z0-9]/g, "");
    }

    function keyForNode(node) {
        const bin = String(node?.properties?.["application.process.binary"] ?? "");
        if (bin.length > 0) return root.appKey(bin);
        return root.appKey(Audio.appNodeDisplayName(node));
    }

    // ── Rows ────────────────────────────────────────────────────────────
    // Live streams first (they can actually be controlled), then any open app
    // that has no stream of its own.
    //
    // windowList churns on every focus/move/resize. Rebuilding `rows` on each
    // of those destroys and recreates every delegate bound to it, which shows
    // up as StyledToolTip's "destroy is not a function" and stalls the UI — so
    // the array is only replaced when the actual set of apps changes.
    property var rows: []

    readonly property string _rowSignature: {
        const keys = [];
        // node.id, NOT keyForNode(): that reads node.properties, which is
        // empty until something tracks the node and populates it. The key
        // therefore flips as trackers come and go, the signature changes,
        // rows rebuild, and whatever is bound to rows re-triggers it —
        // a binding loop, logged twice today right before a segfault in
        // PipeWire's protocol handler. The id is stable and needs no tracker.
        for (const node of (Audio.outputAppNodes ?? []))
            if (node) keys.push("L:" + node.id);
        for (const win of (HyprlandData.windowList ?? []))
            keys.push("W:" + root.appKey(win?.class ?? ""));
        return keys.join("|");
    }
    on_RowSignatureChanged: root.rows = root._buildRows()

    function _buildRows() {
        const out = [];
        const seen = ({});

        for (const node of (Audio.outputAppNodes ?? [])) {
            if (!node) continue;
            const key = root.keyForNode(node);
            if (seen[key]) continue;
            seen[key] = true;
            out.push({
                key: key,
                name: Audio.appNodeDisplayName(node),
                node: node,
                live: true
            });
        }

        for (const win of (HyprlandData.windowList ?? [])) {
            const cls = String(win?.class ?? "");
            if (cls.length === 0) continue;
            const key = root.appKey(cls);
            if (key.length === 0 || seen[key]) continue;
            if (root._ignoredClasses.includes(key)) continue;
            seen[key] = true;
            out.push({
                key: key,
                name: cls,
                node: null,
                live: false
            });
        }
        return out;
    }

    function volumeFor(row) {
        if (row?.live && row.node?.audio)
            return row.node.audio.volume;
        const v = root.storedVolumes[row?.key];
        return v === undefined ? 1.0 : v;
    }

    function setVolume(row, value) {
        const v = Math.max(0, Math.min(1, value));
        if (row?.live && row.node?.audio) {
            row.node.audio.volume = v;
            return;
        }
        const next = Object.assign({}, root.storedVolumes);
        next[row.key] = v;
        root.storedVolumes = next;
        root._persist();
    }

    function mutedFor(row) {
        return (row?.live && row.node?.audio) ? row.node.audio.muted : false;
    }

    function toggleMute(row) {
        if (row?.live && row.node?.audio)
            row.node.audio.muted = !row.node.audio.muted;
    }

    // A remembered level only becomes real once the app opens a stream, so
    // apply it the first time we see a node for that app.
    property var _applied: ({})
    Connections {
        target: Audio
        function onOutputAppNodesChanged() {
            for (const node of (Audio.outputAppNodes ?? [])) {
                if (!node?.audio) continue;
                const key = root.keyForNode(node);
                if (root._applied[key]) continue;
                const want = root.storedVolumes[key];
                if (want === undefined) continue;
                node.audio.volume = want;
                root._applied[key] = true;
            }
        }
    }
}
