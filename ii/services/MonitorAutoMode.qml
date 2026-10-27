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
import Quickshell.Io

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
        const best = root.saverMode(m) ?? root.bestMode(m);
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

        // Where it is now, not "auto": auto could move the screen.
        const fields = {
            mode: r.wantMode ? r.wantMode.str : "preferred",
            position: m.x + "x" + m.y,
            scale: String(r.wantScale ?? m.scale ?? 1)
        };
        // MonitorManager owns the eval transport and the type contract.
        MonitorManager._runMonitor(Object.assign({ output: m.name }, fields));
        root._remember(m, fields);

        const bits = [];
        if (!r.modeOk && r.wantMode) bits.push(r.current + " to " + r.wantMode.str);
        if (!r.scaleOk) bits.push("scale " + m.scale + " to " + r.wantScale
                                  + " (was " + r.logical + " logical)");
        const line = bits.join(", ");
        root.history = [{ name: m.name, detail: line, reason: why ?? "" }]
            .concat(root.history).slice(0, 20);

        if (root.notify) {
            // The screen's model, not its port: "AOC 2590G5", not "DP-12".
            const model = (m.description ?? "").replace(/\s+0x[0-9A-Fa-f]+$/, "").trim() || m.name;
            const parts = [];
            if (!r.modeOk && r.wantMode) {
                parts.push(r.wantMode.w === m.width && r.wantMode.h === m.height
                    ? Translation.tr("Refresh rate %1 Hz → %2 Hz")
                        .arg(Math.round(Number(m.refreshRate) * 100) / 100).arg(r.wantMode.rr)
                    : Translation.tr("Resolution %1 × %2 at %3 Hz")
                        .arg(r.wantMode.w).arg(r.wantMode.h).arg(r.wantMode.rr));
            }
            if (!r.scaleOk)
                parts.push(Translation.tr("Scale %1 → %2 for sharp text").arg(m.scale).arg(r.wantScale));
            Quickshell.execDetached(["notify-send", "-a", Translation.tr("Displays"),
                "-i", "video-display",
                Translation.tr("%1 optimised").arg(model),
                parts.join("\n") + "\n" + Translation.tr("Set to the best mode this screen supports.")]);
        }
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

    // ── Battery saver ────────────────────────────────────────────────────
    // The laptop panel at 60 Hz on battery: at 180 Hz the compositor redraws and
    // blurs three times as often, and the chip ran at ~38 W with the desktop idle.
    // Full rate again on the charger, or while something is fullscreen on the panel
    // (a game). Live only: monitor_auto.lua keeps the best mode, so the charger
    // case needs nothing.
    readonly property bool lowRefreshOnBattery: Config.options?.monitors?.lowRefreshOnBattery ?? true
    readonly property int saverHz: 60

    function _internal(m) { return /^(eDP|LVDS|DSI)/.test(m?.name ?? "") }

    /// The mode the panel should be in right now, or null to leave it alone.
    function saverMode(m) {
        if (!root.lowRefreshOnBattery || !root._internal(m) || Battery.isPluggedIn) return null;
        if (HyprlandData.workspaceById?.[m.activeWorkspace?.id]?.hasfullscreen === true) return null;
        let pick = null;
        for (const s of (m.availableModes ?? [])) {
            const p = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(String(s).trim());
            if (!p || +p[1] !== m.width || +p[2] !== m.height) continue;
            const rr = +p[3];
            if (!pick || Math.abs(rr - root.saverHz) < Math.abs(pick.rr - root.saverHz))
                pick = { w: +p[1], h: +p[2], rr: rr, str: p[1] + "x" + p[2] + "@" + p[3] };
        }
        return pick;
    }

    function _enforceSaver() {
        for (const m of (HyprlandData.monitors ?? [])) {
            if (!root._internal(m)) continue;
            const low = root.saverMode(m);
            const want = low ?? root.bestMode(m);
            if (!want || Math.abs(Number(m.refreshRate) - want.rr) < 0.5) continue;
            // the panel keeps its rule's vrr 2 (variable refresh while fullscreen)
            MonitorManager._runMonitor({ output: m.name, mode: want.str,
                position: m.x + "x" + m.y, scale: String(m.scale ?? 1), vrr: 2 });
        }
    }

    // Debounced both ways: a charger that flaps or a quick fullscreen toggle must
    // not switch the panel mode (a short blank) back and forth.
    Timer { id: saverSettle; interval: 2500; onTriggered: root._enforceSaver() }
    Connections {
        target: Battery
        function onIsPluggedInChanged() { saverSettle.restart() }
    }
    Connections {
        target: HyprlandData
        // these fire on most Hyprland events: start the wait, never extend it
        function onWorkspacesChanged() { if (!saverSettle.running) saverSettle.start() }
        function onMonitorsChanged() { if (!saverSettle.running) saverSettle.start() }
    }
    onLowRefreshOnBatteryChanged: saverSettle.restart()

    // ── Remembering ──────────────────────────────────────────────────────
    // A choice made only live was undone by the next config apply (any
    // `hl.config`, e.g. Palette > Glass): the monitors.conf rule put the
    // screen back to its old mode, this service switched it again, and an
    // external screen blanked twice per change. So the choice is saved as a
    // rule in hypr/lua/monitor_auto.lua, which lua/local.lua loads AFTER the
    // user's monitor rules: every later apply lands on the same mode.
    readonly property string _rulesPath: Quickshell.env("HOME") + "/.config/hypr/lua/monitor_auto.lua"
    readonly property string _statePath: Quickshell.env("HOME") + "/.local/state/quickshell/user/monitorAuto.json"
    /// description -> { mode, position, scale }
    property var _saved: ({})

    function _remember(m, fields) {
        const desc = m?.description ?? "";
        if (!desc) return;
        const next = Object.assign({}, root._saved);
        next[desc] = fields;
        root._saved = next;
        let lua = "-- Written by the shell (MonitorAutoMode): the best mode it picked for each\n"
            + "-- screen, so a config re-apply does not switch back. Delete a line to undo.\n";
        for (const d in next) {
            const f = next[d];
            lua += `hl.monitor({ output = ${DisplayProfiles.luaQuote("desc:" + d)}, mode = ${DisplayProfiles.luaQuote(f.mode)},`
                + ` position = ${DisplayProfiles.luaQuote(f.position)}, scale = ${DisplayProfiles.luaQuote(f.scale)} })\n`;
        }
        saveProc.command = ["bash", "-c",
            "printf '%s' \"$1\" > \"$2\"; mkdir -p \"$(dirname \"$4\")\"; printf '%s' \"$3\" > \"$4\"",
            "save", lua, root._rulesPath, JSON.stringify(next), root._statePath];
        saveProc.running = true;
    }

    Process { id: saveProc; command: ["true"] }

    FileView {
        path: root._statePath
        printErrors: false
        onLoaded: { try { root._saved = JSON.parse(text()) ?? {}; } catch (e) { root._saved = {}; } }
    }

    Component.onCompleted: { settle.restart(); saverSettle.restart(); }
}
