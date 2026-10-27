import QtQuick
import Quickshell
import Quickshell.Io

/// The open recording: timeline.json (the single source of truth, edited
/// here and rendered by the tinct-cast CLI), undo/redo, the playhead, the
/// selection, and the CLI jobs that keep the preview current.
QtObject {
    id: doc

    /// Recording directory, and the tinct-cast binary (empty: `tinct-cast` on
    /// PATH, with ~/.local/bin added since that is where it gets installed).
    property string dir: ""
    property string bin: ""
    function cli(args) {
        if (bin.length > 0) return [bin].concat(args);
        return ["sh", "-c", 'PATH="$HOME/.local/bin:$PATH" exec tinct-cast "$@"', "tinct-cast"].concat(args);
    }

    /// Parsed timeline.json; replaced (never mutated in place) on each edit.
    property var tl: null
    readonly property bool ready: tl !== null
    readonly property real duration: tl ? tl.source.duration : 0
    readonly property bool hasWebcam: !!(tl && tl.webcam)

    /// Playhead in SOURCE seconds; the preview maps it to output time.
    property real playhead: 0
    property bool playing: false
    /// { track: "zoom"|"cut"|"speed"|"camera"|"cursor", index } or null.
    property var selection: null
    /// Media selection, shared by the canvas, the timeline's Media lane and
    /// the inspector's Media tab (-1 = none).
    property int layerSel: -1
    property int insertSel: -1
    /// Ask the inspector to show a tab (picking a layer on the canvas or lane).
    signal showTab(string name)
    /// A media file as an absolute path (layers may be relative to the recording).
    function mediaPath(f) { return !f ? "" : (f.startsWith("/") ? f : dir + "/" + f); }
    /// Rows of the timeline's Media lane: one per layer (up to 4), one for the cut-ins.
    readonly property int mediaRows: tl && tl.media ? Math.min(4, (tl.media.layers || []).length) + ((tl.media.inserts || []).length > 0 ? 1 : 0) : 0

    property var undoStack: []
    property var redoStack: []
    readonly property bool canUndo: undoStack.length > 0
    readonly property bool canRedo: redoStack.length > 0

    /// Bumped whenever the proxy video or the scrub frame is replaced.
    property int proxyRev: 0
    property int frameRev: 0
    property string proxyPath: ""
    property string framePath: ""
    property bool proxyBusy: false
    property real proxyProgress: 0
    /// Export settings (not part of the timeline).
    property string exportFormat: "mp4"
    property int exportRes: 1080
    property int exportFps: 60
    property string exportQuality: "high"
    property string exportEncoder: "auto"

    /// Output size of the scrub frame.
    property size frameSize: Qt.size(960, 600)

    /// Where the last scrub frame sits: { size, rect (frame px), view (source px) }.
    property var frameInfo: null
    /// Filmstrip + waveform from `tinct-cast assets` (null until made).
    property var assets: null
    readonly property string assetsDir: dir + "/.cast-assets"

    signal loaded()

    // ── load / save ──────────────────────────────────────────────────────
    property FileView file: FileView {
        path: doc.dir.length > 0 ? doc.dir + "/timeline.json" : ""
        blockLoading: true
        printErrors: false
        // Never analysed (no timeline.json yet): make one, then load it.
        onLoadFailed: (err) => { if (!doc.analyzeProc.running && !doc.analyzeTried) { doc.analyzeTried = true; doc.analyzeProc.running = true; } }
        onLoaded: {
            // Only the first load: later "loaded" signals echo our own writes.
            if (doc.tl !== null) return;
            try {
                doc.tl = doc.normalize(JSON.parse(text()));
                doc.restoreHistory();
                doc.addRecent(doc.dir);
                doc.loaded();
                doc.requestFrame();
                doc.requestProxy();
                if (!doc.assetsProc.running && doc.assets === null) doc.assetsProc.running = true;
            } catch (e) {
                console.warn("castEditor: bad timeline.json", e);
            }
        }
    }

    property bool analyzeTried: false
    property Process analyzeProc: Process {
        command: doc.cli(["analyze", doc.dir])
        onExited: (code) => { if (code === 0) doc.file.reload(); else console.warn("castEditor: analyze failed for " + doc.dir); }
    }

    /// Fill fields older timeline.json files lack, so the UI can bind freely.
    function normalize(t) {
        t.clip = Object.assign({ trim_start: 0, trim_end: null, cuts: [], speed: [] }, t.clip || {});
        t.zoom = Object.assign({ auto: true, level: 2 }, t.zoom || {});
        t.markers = t.markers || [];
        t.cursor.hide_idle = t.cursor.hide_idle || 0;
        t.style.aspect = t.style.aspect || "auto";
        t.audio = Object.assign({ tracks: [], fade_in: 0, fade_out: 0, normalize: false, duck: 0 }, t.audio || {});
        t.audio.tracks = t.audio.tracks.map(a => Object.assign({ label: "", volume: 1, muted: false, denoise: false, voice: false, mutes: [] }, a));
        if (t.media) {
            t.media.layers = t.media.layers || [];
            t.media.inserts = t.media.inserts || [];
            t.media.canvas = Object.assign({ main: [0, 0, 1, 1], color: [0, 0, 0], fit_output: false }, t.media.canvas || {});
        }
        if (t.webcam) {
            t.webcam.segments = t.webcam.segments || [];
            if (t.webcam.visible === undefined) t.webcam.visible = true;
        }
        return t;
    }

    function clone(o) { return JSON.parse(JSON.stringify(o)); }

    /// Apply `fn(tl)` to a copy, push undo, save and refresh the preview.
    function edit(fn) {
        if (!tl) return;
        const before = JSON.stringify(tl);
        const next = clone(tl);
        fn(next);
        if (JSON.stringify(next) === before) return;
        undoStack = undoStack.concat([before]).slice(-200);
        redoStack = [];
        tl = next;
        saveTimer.restart();
    }
    function undo() {
        if (!canUndo) return;
        redoStack = redoStack.concat([JSON.stringify(tl)]);
        tl = JSON.parse(undoStack[undoStack.length - 1]);
        undoStack = undoStack.slice(0, -1);
        selection = null;
        saveTimer.restart();
    }
    function redo() {
        if (!canRedo) return;
        undoStack = undoStack.concat([JSON.stringify(tl)]);
        tl = JSON.parse(redoStack[redoStack.length - 1]);
        redoStack = redoStack.slice(0, -1);
        selection = null;
        saveTimer.restart();
    }

    property Timer saveTimer: Timer {
        interval: 250
        onTriggered: {
            doc.file.setText(JSON.stringify(doc.tl, null, 2) + "\n");
            doc.savedRev++;
            doc.saveHistory();
            doc.requestFrame();
            proxyTimer.restart();
        }
    }
    property Timer proxyTimer: Timer { interval: 900; onTriggered: doc.requestProxy() }

    // ── clip maths (mirrors analyze/clip.rs) ─────────────────────────────
    function pieces() {
        if (!tl) return [];
        const c = tl.clip || {};
        const d = duration;
        const a = Math.max(0, Math.min(d, c.trim_start || 0));
        const b = Math.max(0, Math.min(d, (c.trim_end === null || c.trim_end === undefined) ? d : c.trim_end));
        const cuts = (c.cuts || []).filter(x => x.end > x.start).slice().sort((x, y) => x.start - y.start);
        const kept = [];
        let t = a;
        for (const x of cuts) {
            if (x.start > t) kept.push([t, Math.min(x.start, b)]);
            t = Math.max(t, x.end);
            if (t >= b) break;
        }
        if (t < b) kept.push([t, b]);
        const out = [];
        for (const [s, e] of kept.filter(k => k[1] > k[0])) {
            const edges = [s, e];
            for (const sp of (c.speed || [])) for (const x of [sp.start, sp.end]) if (x > s && x < e) edges.push(x);
            edges.sort((p, q) => p - q);
            for (let i = 0; i + 1 < edges.length; ++i) {
                if (edges[i + 1] <= edges[i]) continue;
                const mid = (edges[i] + edges[i + 1]) / 2;
                const sp = (c.speed || []).slice().reverse().find(q => mid >= q.start && mid < q.end);
                out.push({ start: edges[i], end: edges[i + 1], speed: sp ? Math.max(0.1, Math.min(16, sp.speed)) : 1 });
            }
        }
        return out;
    }
    readonly property real outDuration: {
        tl;
        return pieces().reduce((acc, p) => acc + (p.end - p.start) / p.speed, 0);
    }
    function srcToOut(t) {
        let acc = 0;
        for (const p of pieces()) {
            if (t < p.start) return acc;
            if (t <= p.end) return acc + (t - p.start) / p.speed;
            acc += (p.end - p.start) / p.speed;
        }
        return acc;
    }
    function outToSrc(t) {
        let acc = 0;
        const ps = pieces();
        for (const p of ps) {
            const len = (p.end - p.start) / p.speed;
            if (t < acc + len) return p.start + (t - acc) * p.speed;
            acc += len;
        }
        return ps.length ? ps[ps.length - 1].end : 0;
    }

    /// The block list of a track ("cut", "speed", "zoom", "camera").
    function listOf(t, track) {
        if (!t) return null;
        if (track === "cursor" && t.cursor && !t.cursor.segments) t.cursor.segments = [];
        if (track === "window" && !t.window) t.window = { mode: "screen", segments: [], switches: [] };
        if (track === "window" && !t.window.segments) t.window.segments = [];
        return { cut: t.clip.cuts, speed: t.clip.speed, zoom: t.segments, camera: t.webcam ? t.webcam.segments : null, cursor: t.cursor ? t.cursor.segments : null, window: t.window ? t.window.segments : null }[track] ?? null;
    }
    /// Add a block at the playhead without overlapping its track: inside an
    /// existing block it selects that one instead; otherwise it stops at the
    /// next block. Returns false when nothing was added.
    /// Move the selected block by `d` seconds, stopping at its neighbours.
    function nudgeSelection(d) {
        const s = selection;
        const list = s ? listOf(tl, s.track) : null;
        if (!list || !list[s.index]) return false;
        const b = list[s.index];
        const lo = s.index > 0 ? list[s.index - 1].end : 0;
        const hi = s.index + 1 < list.length ? list[s.index + 1].start : duration;
        const ns = Math.max(lo, Math.min(hi - (b.end - b.start), b.start + d));
        if (Math.abs(ns - b.start) < 1e-9) return false;
        edit(t => { const x = listOf(t, s.track)[s.index]; x.end = ns + (x.end - x.start); x.start = ns; });
        return true;
    }

    /// Delete the selected block; nothing selected is a no-op.
    function deleteSelection() {
        const s = selection;
        if (!s || !listOf(tl, s.track) || !listOf(tl, s.track)[s.index]) return false;
        selection = null;
        edit(t => listOf(t, s.track).splice(s.index, 1));
        return true;
    }
    function addAt(kind) {
        const p = doc.playhead;
        const list0 = listOf(doc.tl, kind);
        if (!list0) return false;
        const spec = { list: list0, len: { cut: 1, speed: 2, zoom: 2.5, camera: 2, cursor: 2, window: 3 }[kind], track: kind };
        const inside = spec.list.findIndex(b => p >= b.start && p < b.end);
        if (inside >= 0) { doc.selection = { track: spec.track, index: inside }; return false; }
        const next = spec.list.filter(b => b.start > p).reduce((m, b) => Math.min(m, b.start), doc.duration);
        const end = Math.min(next, p + spec.len);
        if (end - p < 0.2) return false;
        doc.edit(t => {
            const mk = {
                cut: () => ({ start: p, end: end }),
                speed: () => ({ start: p, end: end, speed: 2 }),
                zoom: () => ({ start: p, end: end, zoom: t.zoom.level, kind: "manual", focus: null }),
                camera: () => ({ start: p, end: end, mode: "fullscreen", corner: null, size: null }),
                cursor: () => ({ start: p, end: end, visible: !t.cursor.visible }),
                window: () => ({ start: p, end: end, mode: (t.window && t.window.mode !== "screen") ? "screen" : "follow", pin: null, decorations: null, transition: null })
            }[kind];
            const list = listOf(t, kind);
            list.push(mk());
            list.sort((a, b) => a.start - b.start);
        });
        doc.selection = { track: kind, index: listOf(doc.tl, kind).findIndex(b => b.start === p) };
        return true;
    }

    // ── Block operations shared by menus, shortcuts and the inspector ──
    /// Split block `index` of `track` at time `t` (inside it, ≥0.2 s each side).
    function splitAt(track, index, t) {
        const b = listOf(tl, track) ? listOf(tl, track)[index] : null;
        if (!b || t <= b.start + 0.2 || t >= b.end - 0.2) return false;
        edit(x => {
            const l = listOf(x, track);
            const right = JSON.parse(JSON.stringify(l[index]));
            l[index].end = t;
            right.start = t;
            l.splice(index + 1, 0, right);
        });
        selection = { track: track, index: index + 1 };
        return true;
    }
    /// The block of `track` under time `t`, or -1.
    function blockAt(track, t) {
        const l = listOf(tl, track);
        return l ? l.findIndex(b => t >= b.start && t < b.end) : -1;
    }
    /// Copy block `index` right after itself, as far as there is room.
    function duplicate(track, index) {
        const l = listOf(tl, track);
        const b = l ? l[index] : null;
        if (!b) return false;
        const next = index + 1 < l.length ? l[index + 1].start : duration;
        const len = Math.min(b.end - b.start, next - b.end);
        if (len < 0.2) return false;
        edit(x => {
            const c = JSON.parse(JSON.stringify(listOf(x, track)[index]));
            c.start = b.end;
            c.end = b.end + len;
            if (track === "zoom") c.kind = "manual";
            listOf(x, track).splice(index + 1, 0, c);
        });
        selection = { track: track, index: index + 1 };
        return true;
    }
    /// Turn a cut into a speed change (2x) or a speed change into a cut.
    function convertClip(track, index) {
        const b = listOf(tl, track) ? listOf(tl, track)[index] : null;
        if (!b || (track !== "cut" && track !== "speed")) return false;
        const to = track === "cut" ? "speed" : "cut";
        const clash = listOf(tl, to).some(o => o.start < b.end && o.end > b.start);
        if (clash) return false;
        edit(x => {
            listOf(x, track).splice(index, 1);
            const l = listOf(x, to);
            l.push(to === "speed" ? { start: b.start, end: b.end, speed: 2 } : { start: b.start, end: b.end });
            l.sort((p, q) => p.start - q.start);
        });
        selection = { track: to, index: listOf(tl, to).findIndex(o => o.start === b.start) };
        return true;
    }
    /// Trim start ("start") or end ("end") at time `t`.
    function setTrim(which, t) {
        if (!tl) return false;
        const s = tl.clip.trim_start || 0;
        const e = tl.clip.trim_end === null || tl.clip.trim_end === undefined ? duration : tl.clip.trim_end;
        if (which === "start" && t >= e - 0.5) return false;
        if (which === "end" && t <= s + 0.5) return false;
        edit(x => { if (which === "start") x.clip.trim_start = Math.max(0, t); else x.clip.trim_end = t >= duration - 0.01 ? null : t; });
        return true;
    }
    function addMarker(t) {
        edit(x => { x.markers = (x.markers || []).concat([{ t: t }]).sort((a, b) => a.t - b.t); });
    }
    function removeMarker(i) { edit(x => x.markers.splice(i, 1)); }

    /// Every boundary on every track (blocks, trims, markers), sorted.
    readonly property var editPoints: {
        if (!tl) return [];
        const pts = [0, duration, tl.clip.trim_start || 0];
        if (tl.clip.trim_end !== null && tl.clip.trim_end !== undefined) pts.push(tl.clip.trim_end);
        for (const k of ["cut", "speed", "zoom", "camera", "cursor", "window"]) for (const b of (listOf(tl, k) || [])) pts.push(b.start, b.end);
        for (const m of (tl.markers || [])) pts.push(m.t);
        const s = pts.filter(p => p >= 0 && p <= duration).sort((a, b) => a - b);
        return s.filter((p, i) => i === 0 || p - s[i - 1] > 1e-3);
    }
    function nextEditPoint(t) { return editPoints.find(p => p > t + 1e-3) ?? duration; }
    function prevEditPoint(t) { const l = editPoints.filter(p => p < t - 1e-3); return l.length ? l[l.length - 1] : 0; }

    // ── Playback ──
    /// Loop the whole clip, or the selected block when one is selected.
    property bool loop: false
    property real playbackRate: 1
    readonly property real trimStart: tl ? (tl.clip.trim_start || 0) : 0
    readonly property real trimEnd: tl && tl.clip.trim_end !== null && tl.clip.trim_end !== undefined ? tl.clip.trim_end : duration
    /// [start, end) on the recording that playback loops or stops at.
    readonly property var playRange: {
        const s = selection, l = s ? listOf(tl, s.track) : null;
        // Never past the trims: the proxy ends at the trim end.
        if (loop && l && l[s.index]) return [Math.max(trimStart, l[s.index].start), Math.min(trimEnd, l[s.index].end)];
        return [trimStart, trimEnd];
    }

    // ── Reset to defaults (from `tinct-cast defaults`) ──
    property var defaults: null
    property Process defaultsProc: Process {
        command: doc.cli(["defaults"])
        running: true
        stdout: StdioCollector { onStreamFinished: { try { doc.defaults = JSON.parse(text); } catch (e) {} } }
    }
    /// card: background | frame | cursor | zoom | follow | camera
    function resetCard(card) {
        const d = defaults;
        if (!d || !tl) return false;
        edit(x => {
            if (card === "background") x.style.background = d.style.background;
            if (card === "frame") { for (const k of ["padding", "radius", "shadow", "shadow_opacity"]) x.style[k] = d.style[k]; }
            if (card === "cursor") x.cursor = Object.assign({}, d.cursor, { segments: x.cursor.segments || [] });
            if (card === "zoom") x.zoom = d.zoom;
            if (card === "follow") x.camera = d.camera;
            if (card === "camera" && x.webcam) {
                for (const k of ["shape", "size", "aspect", "corner", "margin", "mirror", "border", "zoomed_scale", "dodge", "visible", "spring"]) x.webcam[k] = d.webcam[k];
            }
        });
        return true;
    }

    /// Play/pause; at the end of the range, play starts from its beginning.
    /// Play was pressed before the first proxy existed: start once it does.
    property bool playWhenReady: false
    function togglePlay() {
        if (proxyPath.length === 0) { playWhenReady = !playWhenReady; return; }
        if (!playing && playhead >= playRange[1] - 0.05) playhead = playRange[0];
        playing = !playing;
    }

    // ── Opening recordings, recents ──
    /// Switch to another recording directory (clears all per-recording state).
    function open(path) {
        path = String(path).replace(/^file:\/\//, "").replace(/\/$/, "");
        if (path.length === 0) return;
        playing = false;
        selection = null;
        tl = null;
        undoStack = []; redoStack = [];
        assets = null; frameInfo = null;
        framePath = ""; proxyPath = "";
        savedRev = 0; proxyDoneRev = -1;
        analyzeTried = false;
        playhead = 0;
        dir = path;
        file.reload();
    }
    readonly property string stateDir: (Quickshell.env("HOME") || "") + "/.local/state/tinct-cast"
    property var recents: []
    property FileView recentsFile: FileView {
        path: doc.stateDir + "/recents.json"
        blockLoading: true
        printErrors: false
        // Merge, don't replace: the recording opened at start is often added before this
        // load finishes, and replacing dropped it (then the old list was saved back)
        onLoaded: {
            let saved = [];
            try { saved = JSON.parse(text()); } catch (e) {}
            const mine = doc.recents;
            doc.recents = mine.concat(saved.filter(p => !mine.includes(p))).slice(0, 12);
        }
    }
    function addRecent(path) {
        const r = [path].concat(recents.filter(p => p !== path)).slice(0, 12);
        recents = r;
        mkState.running = true;
    }
    property Process mkState: Process {
        command: ["mkdir", "-p", doc.stateDir]
        onExited: doc.recentsFile.setText(JSON.stringify(doc.recents, null, 1) + "\n")
    }

    // ── Undo history kept next to the recording, so reopening keeps it ──
    property FileView historyFile: FileView {
        path: doc.dir.length > 0 ? doc.dir + "/.cast-history.json" : ""
        blockLoading: true
        printErrors: false
    }
    function saveHistory() {
        historyFile.setText(JSON.stringify({ current: JSON.stringify(tl), undo: undoStack.slice(-50), redo: redoStack.slice(-50) }));
    }
    /// Restore undo/redo if the history was written for exactly this timeline.
    function restoreHistory() {
        try {
            const h = JSON.parse(historyFile.text());
            if (h.current === JSON.stringify(tl)) { undoStack = h.undo || []; redoStack = h.redo || []; }
        } catch (e) {}
    }

    // ── Settings (`tinct-cast config --json`): export defaults, paths, file manager ──
    property var config: null
    property bool configApplied: false
    property Process configProc: Process {
        command: doc.cli(["config", "--json"].concat(doc.dir.length > 0 ? ["--dir", doc.dir] : []))
        stdout: StdioCollector {
            onStreamFinished: {
                try { doc.config = JSON.parse(text); } catch (e) { return; }
                if (doc.configApplied) return;
                doc.configApplied = true;
                const x = doc.config.config.export;
                doc.exportFormat = x.format; doc.exportRes = x.resolution; doc.exportFps = x.fps;
                doc.exportQuality = x.quality; doc.exportEncoder = x.encoder;
            }
        }
    }
    /// A multi-monitor recording is a session dir holding one recording per
    /// screen (session.json + <monitor>/): open the primary screen's.
    property FileView sessionFile: FileView { blockLoading: true; printErrors: false }
    onDirChanged: {
        if (dir.length > 0) {
            sessionFile.path = dir + "/session.json";
            const t = sessionFile.text();
            if (t && t.length > 0) {
                try {
                    const s = JSON.parse(t);
                    if (s.primary) { dir = dir + "/" + s.primary; return; }
                } catch (e) {}
            }
        }
        configProc.running = true; windowsInfo = null; if (dir.length > 0) windowsProc.running = true;
    }

    // ── Window mode facts from the event log (`tinct-cast windows`) ──
    /// { switches: [{t, from, to}], windows: [{address, class}], focus: [[t, address]], has_windows }
    property var windowsInfo: null
    property Process windowsProc: Process {
        command: doc.cli(["windows", doc.dir])
        stdout: StdioCollector { onStreamFinished: { try { doc.windowsInfo = JSON.parse(text); } catch (e) { doc.windowsInfo = null; } } }
    }
    /// Focus changes that become window switches (shorter focus is ignored).
    function windowSwitches() {
        if (!windowsInfo || !tl || !tl.window) return [];
        const min = tl.window.min_focus ?? 0.4;
        const f = windowsInfo.focus.filter(x => x[1]);
        const out = [];
        let cur = f.length ? f[0][1] : null;
        for (let i = 1; i < f.length; i++) {
            const until = i + 1 < f.length ? f[i + 1][0] : duration;
            if (f[i][1] === cur || until - f[i][0] < min) continue;
            const ws = windowsInfo.switches.some(s => Math.abs(s.t - f[i][0]) < 0.02);
            out.push({ t: f[i][0], workspace: ws });
            cur = f[i][1];
        }
        return out;
    }
    /// Per-switch transition (null = the default).
    function setSwitchTransition(t, kind) {
        edit(x => {
            if (!x.window.switches) x.window.switches = [];
            x.window.switches = x.window.switches.filter(s => Math.abs(s.t - t) > 0.02);
            if (kind) x.window.switches.push({ t: t, transition: kind });
        });
    }
    function switchTransition(t) {
        const s = tl && tl.window && tl.window.switches ? tl.window.switches.find(s => Math.abs(s.t - t) <= 0.02) : null;
        return s ? s.transition : null;
    }
    /// Cut Hyprland's workspace animation after each switch (skips covered spots).
    function cutWorkspaceAnimations(len) {
        if (!windowsInfo) return 0;
        let n = 0;
        edit(x => {
            for (const s of windowsInfo.switches) {
                const a = s.t, b = Math.min(duration, s.t + len);
                if (x.clip.cuts.some(c => c.start < b && c.end > a)) continue;
                x.clip.cuts.push({ start: a, end: b });
                n++;
            }
            x.clip.cuts.sort((p, q) => p.start - q.start);
        });
        return n;
    }
    Component.onCompleted: { configProc.running = true; if (dir.length > 0) windowsProc.running = true; }
    readonly property bool hasWindows: !!(windowsInfo && windowsInfo.has_windows)
    /// Open the global config file in the default editor (written with
    /// commented defaults first if missing).
    function openConfig() {
        const c = cli(["config", "--init"]).map(a => "'" + a.replace(/'/g, "'\\''") + "'").join(" ");
        run(["sh", "-c", 'f="$1"; [ -e "$f" ] || ' + c + ' >/dev/null; xdg-open "$f"', "sh", config ? config.global : (Quickshell.env("HOME") + "/.config/tinct-cast/config.toml")]);
    }

    // ── Desktop helpers (export toast, menus) ──
    property string lastExport: ""
    property Process helper: Process {}
    /// Tests set this to capture desktop commands instead of running them.
    property var helperSpy: null
    function run(cmd) { if (helperSpy) helperSpy(cmd); else Quickshell.execDetached(cmd); }
    function showInFolder(path) { run(["xdg-open", path]); }

    /// How "Show in folder" reveals a file: the last choice, else the config's.
    property string revealWith: ""
    readonly property string fileManager: config ? config.config.editor.file_manager : "xdg"
    readonly property string customFileManager: fileManager !== "xdg" && fileManager !== "dolphin" ? fileManager : ""
    readonly property string revealDefault: revealWith.length > 0 ? revealWith : (fileManager === "dolphin" ? "dolphin" : fileManager === "xdg" ? "xdg" : "custom")
    property FileView uiFile: FileView {
        path: doc.stateDir + "/ui.json"
        blockLoading: true
        printErrors: false
        onLoaded: { try { doc.revealWith = JSON.parse(text()).revealWith || ""; } catch (e) {} }
    }
    function setRevealWith(how) {
        revealWith = how;
        run(["sh", "-c", 'mkdir -p "$1" && printf "%s\\n" "$2" > "$1/ui.json"', "sh", stateDir, JSON.stringify({ revealWith: how })]);
    }
    /// Show `path` selected in a file manager ("xdg" | "dolphin" | "custom").
    function reveal(path, how) {
        how = how || revealDefault;
        const folder = path.replace(/\/[^/]*$/, "");
        if (how === "dolphin") run(["dolphin", "--select", path]);
        else if (how === "custom" && customFileManager.length > 0)
            run(["sh", "-c", customFileManager.replace(/\{path\}/g, '"$1"').replace(/\{dir\}/g, '"$2"'), "sh", path, folder]);
        else
            // FileManager1 selects the file (Dolphin, Nautilus, Nemo...); else open the folder.
            run(["sh", "-c", 'dbus-send --session --print-reply --dest=org.freedesktop.FileManager1 /org/freedesktop/FileManager1 org.freedesktop.FileManager1.ShowItems array:string:"file://$1" string:"" >/dev/null 2>&1 || xdg-open "$2"', "sh", path, folder]);
    }
    function openFile(path) { run(["xdg-open", path]); }
    function copyPath(path) { run(["sh", "-c", 'printf "%s" "$1" | wl-copy', "sh", path]); }
    /// The ▾ menu next to "Show in folder".
    function revealMenu(item, x, y, path) {
        const pick = (how) => () => { setRevealWith(how); reveal(path, how); };
        const tick = (how, icon) => revealDefault === how ? "check" : icon;
        const items = [
            { icon: tick("dolphin", "folder_open"), label: "Dolphin", onTriggered: pick("dolphin") },
            { icon: tick("xdg", "folder"), label: "Default file manager", onTriggered: pick("xdg") }
        ];
        if (customFileManager.length > 0) items.push({ icon: tick("custom", "terminal"), label: "Custom (" + customFileManager.split(" ")[0] + ")", onTriggered: pick("custom") });
        items.push({ separator: true },
            { icon: "play_circle", label: "Open video", onTriggered: () => openFile(path) },
            { icon: "content_paste", label: "Copy path", onTriggered: () => copyPath(path) });
        menu(item, x, y, items);
    }
    function copyFile(path) {
        helper.command = ["sh", "-c", "printf 'file://%s\\n' \"$1\" | wl-copy -t text/uri-list", "sh", path];
        helper.running = true;
    }
    /// Copy the exact current frame (full size) to the clipboard as PNG.
    function copyFrame() {
        helper.command = ["sh", "-c", 'f="$1/.cast-copy.png"; PATH="$HOME/.local/bin:$PATH"; ' + (bin.length > 0 ? '"' + bin + '"' : "tinct-cast")
                          + ' frame "$1" --t "$2" --src --resolution 1080 -o "$f" >/dev/null && wl-copy -t image/png < "$f"', "sh", dir, playhead.toFixed(4)];
        helper.running = true;
    }
    /// Save the exact current frame next to the recording; returns the path.
    property Process frameSaver: Process {}
    function saveFrame() {
        const out = dir + "/frame-" + playhead.toFixed(2).replace(".", "_") + "s.png";
        frameSaver.command = cli(["frame", dir, "--t", playhead.toFixed(4), "--src", "--resolution", "1080", "-o", out]);
        frameSaver.running = true;
        return out;
    }

    // ── Menus: set by the window (it owns the popup) ──
    property var openMenu: null
    function menu(item, x, y, items) { if (openMenu) openMenu(item, x, y, items); }
    /// A check-mark icon for "current value" rows.
    function tick(on, icon) { return on ? "check" : (icon || ""); }

    // ── CLI jobs ─────────────────────────────────────────────────────────
    /// Exact frame at the playhead (debounced; the newest request wins).
    property bool frameWanted: false
    function requestFrame() { frameWanted = true; frameTimer.restart(); }
    property Timer frameTimer: Timer {
        interval: 60
        onTriggered: {
            if (frameProc.running || !doc.frameWanted || !doc.tl) return;
            doc.frameWanted = false;
            frameProc.target = doc.dir + "/.cast-frame-" + ((doc.frameRev + 1) % 2) + ".png";
            frameProc.command = doc.cli(["frame", doc.dir, "--t", doc.playhead.toFixed(4), "--src",
                                 "--size", Math.round(doc.frameSize.width) + "x" + Math.round(doc.frameSize.height), "-o", frameProc.target]);
            frameProc.running = true;
        }
    }
    property Process frameProc: Process {
        property string target: ""
        stdout: StdioCollector { id: frameOut }
        onExited: (code) => {
            if (code === 0) {
                try { doc.frameInfo = JSON.parse(frameOut.text); } catch (e) { doc.frameInfo = null; }
                doc.framePath = target;
                doc.frameRev++;
            }
            if (doc.frameWanted) doc.frameTimer.restart();
        }
    }

    /// Low-res proxy the player shows while playing.
    /// Saves of timeline.json, and the save the shown proxy was made from.
    property int savedRev: 0
    property int proxyDoneRev: -1
    readonly property bool proxyStale: proxyDoneRev !== savedRev
    function requestProxy() {
        // One render at a time; a newer save is picked up when it ends.
        if (proxyProc.running) return;
        if (!tl) return;
        proxyProc.rev = savedRev;
        proxyProc.target = dir + "/.cast-proxy-" + ((proxyRev + 1) % 2) + ".mp4";
        proxyProc.command = cli(["preview", dir, "-o", proxyProc.target]);
        proxyBusy = true;
        proxyProgress = 0;
        proxyProc.running = true;
    }
    property Process proxyProc: Process {
        property string target: ""
        property int rev: 0
        stdout: SplitParser {
            onRead: (line) => {
                const m = line.match(/^progress (\d+) (\d+)/);
                if (m && Number(m[2]) > 0) doc.proxyProgress = Number(m[1]) / Number(m[2]);
            }
        }
        onExited: (code) => {
            doc.proxyBusy = false;
            if (code === 0) { doc.proxyPath = target; doc.proxyRev++; doc.proxyDoneRev = rev; }
            if (code === 0 && doc.playWhenReady) { doc.playWhenReady = false; doc.togglePlay(); }
            // Edits arrived meanwhile: go again (after a failure only on the next edit).
            if (code === 0 && doc.proxyStale) doc.proxyTimer.restart();
        }
    }

    /// Filmstrip thumbnails and the waveform, made once in the background.
    property Process assetsProc: Process {
        command: doc.cli(["assets", doc.dir])
        onExited: (code) => { if (code === 0) assetsFile.reload(); }
    }
    property FileView assetsFile: FileView {
        path: doc.dir.length > 0 ? doc.assetsDir + "/assets.json" : ""
        blockLoading: true
        printErrors: false
        onLoaded: { try { doc.assets = JSON.parse(text()); } catch (e) {} }
    }

    onPlayheadChanged: if (!playing) requestFrame()

    // ── helpers for the UI ───────────────────────────────────────────────
    function fmt(t) {
        t = Math.max(0, t);
        const m = Math.floor(t / 60), s = t - m * 60;
        return m + ":" + (s < 10 ? "0" : "") + s.toFixed(2);
    }
    /// A colour role as the [r, g, b] the renderer wants.
    function rgb(c) { return [Number(c.r.toFixed(4)), Number(c.g.toFixed(4)), Number(c.b.toFixed(4))]; }
}
