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
    /// appKey -> -1 (left) .. 1 (right). Absent = centred.
    property var storedBalances: ({})

    function _loadStored() {
        try {
            root.storedVolumes = JSON.parse(Persistent.states.audio.appVolumes || "{}") ?? ({});
            root.storedBalances = JSON.parse(Persistent.states.audio.appBalances || "{}") ?? ({});
        } catch (e) {
            root.storedVolumes = ({});
        }
    }
    function _persist() {
        Persistent.states.audio.appVolumes = JSON.stringify(root.storedVolumes);
        Persistent.states.audio.appBalances = JSON.stringify(root.storedBalances);
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

        // One row per app, but `nodes` holds ALL its streams: a browser opens one
        // per tab/video, and controlling only the first missed the one playing.
        for (const node of (Audio.outputAppNodes ?? [])) {
            if (!node) continue;
            const key = root.keyForNode(node);
            if (seen[key]) { seen[key].nodes.push(node); continue; }
            seen[key] = {
                key: key,
                name: Audio.appNodeDisplayName(node),
                node: node,
                nodes: [node],
                live: true
            };
            out.push(seen[key]);
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
                nodes: [],
                live: false
            });
        }
        return out;
    }

    /// The loudest channel. `audio.volume` is their average, which reads a
    /// balanced stream as quieter than the level that was set.
    function _peak(audio) {
        const v = audio?.volumes ?? [];
        return v.length > 0 ? Math.max.apply(null, v) : (audio?.volume ?? 1);
    }

    function volumeFor(row) {
        if (row?.live && row.node?.audio)
            return root._peak(row.node.audio);
        const v = root.storedVolumes[row?.key];
        return v === undefined ? 1.0 : v;
    }

    function setVolume(row, value) {
        const v = Math.max(0, Math.min(1, value));
        if (row?.live && row.node?.audio) {
            const b = root.balanceFor(row);
            for (const a of root._audios(row)) root._writeLive(a, v, b);
            return;
        }
        const next = Object.assign({}, root.storedVolumes);
        next[row.key] = v;
        root.storedVolumes = next;
        root._persist();
    }

    /// Every stream of the row that can be written to.
    function _audios(row) {
        // Only bound (tracked) nodes: a write to an unbound one is dropped with an error.
        return (row?.nodes ?? (row?.node ? [row.node] : [])).filter(n => n?.ready).map(n => n.audio).filter(a => a);
    }

    /// Writes a level and a balance together. Assigning `audio.volume` alone sets
    /// every channel equal, which would silently undo the balance.
    function _writeLive(audio, volume, balance) {
        const count = audio?.volumes?.length ?? 0;
        if (count === 2) audio.volumes = AudioLayout.volumesForBalance([volume, volume], balance);
        else audio.volume = volume;
    }

    /// Only a stereo stream can be moved left or right. An app with no stream
    /// yet can: the balance is applied when its stream opens.
    function canBalance(row) {
        return !(row?.live && row.node?.audio) || (row.node.audio.volumes?.length ?? 0) === 2;
    }

    function balanceFor(row) {
        const audio = (row?.live) ? row.node?.audio : null;
        const v = audio?.volumes ?? [];
        // Zero volume has no direction, so fall back to what was chosen.
        if (v.length === 2 && Math.max(v[0], v[1]) > 0.001) return AudioLayout.balanceOf(v);
        return root.storedBalances[row?.key] ?? 0;
    }

    /// -1 (left) .. 1 (right). Snaps to the middle near it, so centre is easy to
    /// hit with a slider.
    function setBalance(row, value) {
        let b = Math.max(-1, Math.min(1, value));
        if (Math.abs(b) < 0.05) b = 0;
        const next = Object.assign({}, root.storedBalances);
        if (b === 0) delete next[row.key]; else next[row.key] = b;
        root.storedBalances = next;
        root._persist();
        if (row?.live)
            for (const a of root._audios(row)) root._writeLive(a, root._peak(a), b);
    }

    function mutedFor(row) {
        return (row?.live && row.node?.audio) ? row.node.audio.muted : false;
    }

    function toggleMute(row) {
        if (!(row?.live && row.node?.audio)) return;
        const m = !row.node.audio.muted;
        for (const a of root._audios(row)) a.muted = m;
    }

    // A remembered level only becomes real once the app opens a stream, so
    // apply it the first time we see a node for that app. Balance is kept
    // current by setBalance, so every new stream of the app gets it.
    property var _applied: ({})
    property var _panned: ({})
    Connections {
        target: Audio
        function onOutputAppNodesChanged() {
            for (const node of (Audio.outputAppNodes ?? [])) {
                if (!node?.ready || !node?.audio || root._panned[node.id]) continue;
                const key = root.keyForNode(node);
                const want = root._applied[key] ? undefined : root.storedVolumes[key];
                const pan = root.storedBalances[key];
                if (want === undefined && pan === undefined) continue;
                root._writeLive(node.audio, want ?? root._peak(node.audio), pan ?? 0);
                root._applied[key] = true;
                root._panned[node.id] = true;
            }
        }
    }
}
