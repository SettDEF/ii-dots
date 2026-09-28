// Best mode and a scale that divides the panel evenly, once per connection.
//
// `preferred` takes the EDID-preferred timing, which is not always the best —
// a TV listing 1080p@50 before @60 runs at 50 forever. And a scale that leaves
// fractional logical pixels makes the compositor resample every surface, which
// no mode choice fixes.
pragma Singleton

import qs.modules.common
import qs.services
import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property bool enabled: Config.options?.monitors?.autoBestMode ?? true
    readonly property bool notify: Config.options?.monitors?.notifyOnChange ?? true

    /// What was changed this session, newest first.
    property var history: []

    // name + description: a re-plug is a fresh decision, a workspace switch isn't.
    property var _handled: ({})

    // ── Picking ──────────────────────────────────────────────────────────
    /// Highest pixel count, and among equals the highest refresh.
    function bestMode(m) {
        const modes = m?.availableModes ?? [];
        let best = null;
        for (const s of modes) {
            const p = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(String(s).trim());
            if (!p) continue;
            const cand = { w: +p[1], h: +p[2], rr: +p[3], str: p[1] + "x" + p[2] + "@" + p[3] };
            if (!best || (cand.w * cand.h) > (best.w * best.h)
                || ((cand.w * cand.h) === (best.w * best.h) && cand.rr > best.rr))
                best = cand;
        }
        return best;
    }

    /// Scales that divide the panel into whole logical pixels.
    function cleanScales(w, h) {
        const out = [];
        for (let i = 100; i <= 300; i += 5) {
            const sc = i / 100;
            const lw = w / sc, lh = h / sc;
            if (Math.abs(lw - Math.round(lw)) < 1e-9 && Math.abs(lh - Math.round(lh)) < 1e-9)
                out.push(sc);
        }
        return out;
    }

    function isCleanScale(w, h, scale) {
        const lw = w / scale, lh = h / scale;
        return Math.abs(lw - Math.round(lw)) < 1e-9 && Math.abs(lh - Math.round(lh)) < 1e-9;
    }

    /// Nearest clean scale, so sharpness changes apparent size the least.
    function nearestCleanScale(w, h, current) {
        const opts = root.cleanScales(w, h);
        if (opts.length === 0) return null;
        let best = opts[0];
        for (const s of opts)
            if (Math.abs(s - current) < Math.abs(best - current)) best = s;
        return best;
    }

    // ── Reporting ────────────────────────────────────────────────────────
    /// What is wrong with a monitor right now, changing nothing.
    function inspect(m) {
        if (!m) return null;
        const best = root.bestMode(m);
        const scale = Number(m.scale) || 1;
        const scaleOk = root.isCleanScale(m.width, m.height, scale);
        const modeOk = !best || (m.width === best.w && m.height === best.h
                                 && Math.abs(Number(m.refreshRate) - best.rr) < 0.5);
        return {
            name: m.name,
            current: m.width + "x" + m.height + "@" + Number(m.refreshRate).toFixed(2),
            modeOk: modeOk,
            scaleOk: scaleOk,
            wantMode: best,
            wantScale: scaleOk ? scale : root.nearestCleanScale(m.width, m.height, scale),
            logical: (m.width / scale).toFixed(2) + "x" + (m.height / scale).toFixed(2)
        };
    }

    /// Every connected monitor, inspected — for a settings page to render.
    readonly property var report: {
        const out = [];
        for (const m of (HyprlandData.monitors ?? [])) {
            const r = root.inspect(m);
            if (r) out.push(r);
        }
        return out;
    }

    // ── Applying ─────────────────────────────────────────────────────────
    function apply(m, why) {
        const r = root.inspect(m);
        if (!r || (r.modeOk && r.scaleOk)) return false;

        // MonitorManager owns the eval transport and the type contract.
        MonitorManager._runMonitor({
            output: m.name,
            mode: r.wantMode ? r.wantMode.str : "preferred",
            position: "auto",
            scale: String(r.wantScale ?? m.scale ?? 1)
        });

        const bits = [];
        if (!r.modeOk && r.wantMode) bits.push(r.current + " to " + r.wantMode.str);
        if (!r.scaleOk) bits.push("scale " + m.scale + " to " + r.wantScale
                                  + " (was " + r.logical + " logical)");
        const line = bits.join(", ");
        root.history = [{ name: m.name, detail: line, reason: why ?? "" }]
            .concat(root.history).slice(0, 20);

        if (root.notify)
            Quickshell.execDetached(["notify-send",
                Translation.tr("Display adjusted: %1").arg(m.name), line, "-a", "Shell"]);
        return true;
    }

    /// Check everything now, whatever was handled before.
    function applyAll() {
        let n = 0;
        for (const m of (HyprlandData.monitors ?? []))
            if (root.apply(m, "manual")) n++;
        return n;
    }

    // ── Watching ─────────────────────────────────────────────────────────
    function _key(m) { return (m?.name ?? "?") + "|" + (m?.description ?? ""); }

    function _sweep() {
        if (!root.enabled) return;
        for (const m of (HyprlandData.monitors ?? [])) {
            const k = root._key(m);
            if (root._handled[k]) continue;
            // Marked before applying: the apply re-emits monitorsChanged.
            root._handled[k] = true;
            root.apply(m, "connected");
        }
    }

    // Debounced: a hotplug emits several changes while the mode settles.
    Timer {
        id: settle
        interval: 1200
        onTriggered: root._sweep()
    }

    Connections {
        target: HyprlandData
        function onMonitorsChanged() { settle.restart() }
    }

    Component.onCompleted: settle.restart()
}
