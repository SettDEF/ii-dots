pragma Singleton
pragma ComponentBehavior: Bound

// Context-switched pointer profiles for the KinetiX engine.
//
// Same idea as DisplayProfiles for monitors and statsHud's appProfiles for the
// overlay: what a pointer curve should be depends on what you are pointing AT.
// A shooter wants a flat, fast, snap-free curve; a drawing app wants heavy
// smoothing and no inertia; the external monitor is bigger and wants more
// travel per centimetre. Retuning by hand every time you switch is the thing
// this removes.
//
// THREE SCOPES, resolved most-specific-first:
//
//     app        the focused window's class          (highest priority)
//     workspace  the active workspace id
//     monitor    the focused monitor's name          (lowest)
//     — none matching → the base settings you last saved by hand
//
// The order is deliberate: a monitor rule is a broad statement about physical
// geometry, a workspace rule is about what you keep there, and an app rule is
// about the one thing in front of you. The narrower claim should win.
//
// This singleton also owns the WRITE path, which used to live in the panel.
// It has to: the panel is a lazy-loaded surface, and a profile that only
// applies while its settings window happens to be open is not a profile.

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    // ── Store ───────────────────────────────────────────────────────────
    // JSON text, not a JsonObject map: a `property var` holding dynamic keys
    // inside a nested JsonObject segfaults Quickshell (jsonadapter.cpp:164).
    // Same reason statsHud.appProfiles is a string.
    //
    // Shape: [ { scope, match, name, settings: {...} }, ... ]
    readonly property var profiles: {
        try {
            const p = JSON.parse(Config.options.kinetix.profiles || "[]");
            return Array.isArray(p) ? p : [];
        } catch (e) {
            console.warn("[KinetixProfiles] unreadable profile store:", e);
            return [];
        }
    }

    readonly property bool enabled: Config.options.kinetix.profilesEnabled ?? true

    function _store(list) {
        Config.options.kinetix.profiles = JSON.stringify(list);
    }

    // ── Live context ────────────────────────────────────────────────────
    readonly property string ctxApp: AppDisplay.focusedApp ?? ""
    readonly property string ctxWorkspace: String(HyprlandData.activeWorkspace?.id ?? "")
    readonly property string ctxMonitor: Hyprland.focusedMonitor?.name ?? ""

    function contextFor(scope) {
        switch (scope) {
            case "app":       return root.ctxApp;
            case "workspace": return root.ctxWorkspace;
            case "monitor":   return root.ctxMonitor;
        }
        return "";
    }

    // Most specific wins. Returns null when nothing claims the current context,
    // which is the signal to fall back to the hand-tuned base settings.
    readonly property var activeProfile: {
        if (!root.enabled) return null;
        const order = ["app", "workspace", "monitor"];
        for (let i = 0; i < order.length; ++i) {
            const scope = order[i];
            const ctx = root.contextFor(scope);
            if (!ctx || ctx.length === 0) continue;
            const hit = root.profiles.find(p => p.scope === scope && p.match === ctx);
            if (hit) return hit;
        }
        return null;
    }

    readonly property string activeLabel: root.activeProfile
        ? (root.activeProfile.name || (root.activeProfile.scope + ": " + root.activeProfile.match))
        : ""

    // ── Editing ─────────────────────────────────────────────────────────
    function upsert(scope, match, name, settings) {
        if (!scope || !match || match.length === 0) return false;
        const list = root.profiles.slice();
        const i = list.findIndex(p => p.scope === scope && p.match === match);
        const entry = { scope: scope, match: match, name: name ?? "", settings: settings };
        if (i >= 0) list[i] = entry; else list.push(entry);
        root._store(list);
        return true;
    }

    function remove(scope, match) {
        root._store(root.profiles.filter(p => !(p.scope === scope && p.match === match)));
    }

    function clearAll() { root._store([]); }

    function has(scope, match) {
        return root.profiles.some(p => p.scope === scope && p.match === match);
    }

    // ── Presets ─────────────────────────────────────────────────────────
    // A bezier curve is the wrong tool for an FPS. Aim is muscle memory: the
    // same physical distance must always produce the same on-screen distance,
    // and ANY curve breaks that by making the mapping depend on how fast you
    // moved. Smoothing is worse still — it buys visual polish with latency,
    // which is the one currency a shooter cannot spend.
    //
    // So "raw" is not a gentler curve. It is a straight diagonal with every
    // filter off, which is what a gaming mouse does natively.
    // "No curve" is a CURVE TYPE, not a curve shape.
    //
    //   bezier : gain = sensitivity * (curve_y / speed)   — speed-dependent
    //   linear : gain = sensitivity                        — constant
    //
    // See calculate_gain() in hyper-mouse-rust/src/main.rs.
    readonly property bool curveBypassed: (root.baseSettings?.curve_type ?? "bezier") === "linear"

    function setCurveBypassed(on) {
        const cur = Object.assign({}, root.baseSettings ?? {});
        cur.curve_type = on ? "linear" : "bezier";
        // curve_nodes are left untouched: switching back to bezier must return
        // the shape you drew, not a default.
        root.setBase(root.normalise(cur));
    }
    function toggleCurveBypass() { root.setCurveBypassed(!root.curveBypassed); }

    readonly property var presets: [
        {
            id: "raw",
            name: qsTr("Raw / FPS"),
            icon: "target",
            desc: qsTr("Constant gain at every speed. No acceleration."),
            settings: {
                enabled: true,
                // Linear: gain is exactly `sensitivity`, whatever your hand does.
                curve_type: "linear",
                // 1.0 is RAW, not 0.0: the engine derives its filter time
                // constant as (1 - smoothness) * 40ms, so 0.0 asks for the
                // MAXIMUM 40ms lag. Named as if it were an amount of smoothing;
                // it is really an amount of rawness.
                smoothness: 1.0,
                sensitivity: 1.0,       // the speed knob — raise for faster
                tremor_friction: 0.0,   // below this speed gain is squared away
                angle_snapping: false,
                snap_angle_deg: 6.0,
                kinetic_inertia: false,
                glide_friction: 0.82,
                exp_power: 1.0,
                sigmoid_mid: 0.5,
                sigmoid_steep: 4.0,
                velocity_cap: 0.0,
                gforce_gain: 0.0,
                soft_edge_damp: false
            }
        },
        {
            id: "balanced",
            name: qsTr("Balanced"),
            icon: "tune",
            desc: qsTr("Gentle curve with light smoothing. Everyday pointing."),
            settings: {
                enabled: true,
                curve_type: "bezier",
                curve_nodes: [
                    { x: 0, y: 0, p1x: 0, p1y: 0, p2x: 0.25, p2y: 0.18 },
                    { x: 1, y: 1, p1x: 0.7, p1y: 0.85, p2x: 1, p2y: 1 }
                ],
                smoothness: 0.75, sensitivity: 1.0, tremor_friction: 0.15,
                angle_snapping: false, snap_angle_deg: 6.0,
                kinetic_inertia: false, glide_friction: 0.82,
                exp_power: 1.0, sigmoid_mid: 0.5, sigmoid_steep: 4.0,
                velocity_cap: 0.0, gforce_gain: 0.0, soft_edge_damp: false
            }
        },
        {
            id: "precision",
            name: qsTr("Precision"),
            icon: "draw",
            desc: qsTr("Slow near zero, full speed on a flick. Design work."),
            settings: {
                enabled: true,
                curve_type: "bezier",
                curve_nodes: [
                    { x: 0, y: 0, p1x: 0, p1y: 0, p2x: 0.45, p2y: 0.12 },
                    { x: 1, y: 1, p1x: 0.75, p1y: 0.95, p2x: 1, p2y: 1 }
                ],
                smoothness: 0.55, sensitivity: 0.9, tremor_friction: 0.5,
                angle_snapping: false, snap_angle_deg: 6.0,
                kinetic_inertia: false, glide_friction: 0.82,
                exp_power: 1.0, sigmoid_mid: 0.5, sigmoid_steep: 4.0,
                velocity_cap: 0.0, gforce_gain: 0.0, soft_edge_damp: true
            }
        },
        {
            id: "glide",
            name: qsTr("Glide"),
            icon: "waves",
            desc: qsTr("Inertia and coasting. Big screens, lazy travel."),
            settings: {
                enabled: true,
                curve_type: "bezier",
                curve_nodes: [
                    { x: 0, y: 0.9, p1x: 0, p1y: 0.9, p2x: 0.33, p2y: 1.0 },
                    { x: 1, y: 1.2, p1x: 0.66, p1y: 1.2, p2x: 1, p2y: 1.2 }
                ],
                smoothness: 0.5, sensitivity: 1.1, tremor_friction: 0.2,
                angle_snapping: false, snap_angle_deg: 6.0,
                kinetic_inertia: true, glide_friction: 0.9,
                exp_power: 1.0, sigmoid_mid: 0.5, sigmoid_steep: 4.0,
                velocity_cap: 0.0, gforce_gain: 0.0, soft_edge_damp: false
            }
        }
    ]

    function presetById(id) {
        return root.presets.find(p => p.id === id) ?? null;
    }

    /// Applies a preset as the new base (i.e. what you get when no profile
    /// matches). Does not touch your saved per-app profiles.
    /// Which preset was applied last, so the panel can show one as selected.
    /// Cleared whenever settings are edited by hand — see setBase — because a
    /// chip that stays lit after you have turned a dial is telling you a lie.
    property string _lastPreset: ""

    function applyPreset(id) {
        const p = root.presetById(id);
        if (!p) return false;
        root._lastPreset = id;
        root.setBase(root.normalise(p.settings));
        return true;
    }

    /// True when the live settings are effectively raw — a straight curve with
    /// the filters off. Compared loosely because the panel's sliders can leave
    /// values a hair off exact.
    readonly property bool rawActive: {
        const s = root.baseSettings;
        if (!s) return false;
        const nodes = s.curve_nodes ?? [];
        if (nodes.length !== 2) return false;
        const top = nodes[nodes.length - 1];
        const straight = Math.abs((top?.y ?? 0) - 1) < 0.02 && Math.abs((top?.x ?? 0) - 1) < 0.02;
        return straight
            && Number(s.smoothness ?? 1) < 0.02
            && Number(s.tremor_friction ?? 1) < 0.02
            && !s.kinetic_inertia
            && !s.angle_snapping;
    }

    /// One-key raw toggle. Going in, the current base is stashed so coming back
    /// out restores exactly what you had rather than a guess at it.
    property var _preRaw: null
    function toggleRaw() {
        if (root.rawActive) {
            if (root._preRaw) root.setBase(root._preRaw);
            root._preRaw = null;
        } else {
            root._preRaw = root.baseSettings;
            root.applyPreset("raw");
        }
    }

    /// Pins a preset to whatever app is focused right now, so it engages by
    /// itself every time that app comes forward — the point of a profiles
    /// system you already have but had no presets to feed it.
    function pinPresetToFocusedApp(presetId) {
        const app = root.ctxApp;
        if (!app || app.length === 0) return false;
        const p = root.presetById(presetId);
        if (!p) return false;
        root.upsert("app", app, p.name, root.normalise(p.settings));
        return true;
    }

    // ── The base (no-profile) settings ──────────────────────────────────
    // Whatever was last written by hand. Kept so leaving a profiled context
    // restores what you had, rather than stranding you on the last profile
    // that happened to match.
    property var baseSettings: null

    // Seeded from the engine's own config file so the base is populated the
    // moment the shell starts, not only after you have opened the panel and
    // touched something. Without this, anything outside the panel that wanted
    // to READ the current settings — the Settings app page, say — had nothing
    // to show until you had visited the panel first.
    FileView {
        id: baseFile
        path: Quickshell.env("HOME") + "/.config/kinetix-config.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(String(baseFile.text()));
                if (parsed && typeof parsed === "object") root.baseSettings = parsed;
            } catch (e) {
                // Leave whatever we had; a half-written file is not a reset.
            }
        }
    }

    /** Patch one field of the base settings and apply. Used by surfaces that
     *  edit a single value at a time rather than owning the whole document. */
    function setBaseField(key, value) {
        const next = Object.assign({}, root.baseSettings ?? {});
        next[key] = value;
        root.setBase(next);
    }

    function baseField(key, fallback) {
        const v = root.baseSettings ? root.baseSettings[key] : undefined;
        return v === undefined ? fallback : v;
    }

    // ── Applying ────────────────────────────────────────────────────────
    // Every field the engine requires. Absent fields are NOT optional: the
    // daemon rejects a partial document outright and silently keeps running on
    // its built-in defaults, which is how "settings never took effect" used to
    // present. Booleans must be real booleans for the same reason.
    function normalise(s) {
        const n = s ?? {};
        return {
            enabled:          n.enabled === undefined ? true : !!n.enabled,
            // NOT hardcoded to bezier. The engine's "linear" mode returns
            // gain = sensitivity flat, which is what "no acceleration" means.
            // Forcing bezier here is what made the No-curve toggle express
            // itself as a flat bezier instead — and a flat bezier is
            // catastrophic, because gain is curve_y / speed, so a constant
            // height divided by a near-zero speed is a near-infinite gain
            // (clamped to 12x). The engine's own source warns about exactly
            // this.
            curve_type:       (n.curve_type === "linear") ? "linear" : "bezier",
            smoothness:       Number(n.smoothness ?? 1.0),
            sensitivity:      Number(n.sensitivity ?? 1.0),
            tremor_friction:  Number(n.tremor_friction ?? 0.4),
            angle_snapping:   !!n.angle_snapping,
            snap_angle_deg:   Number(n.snap_angle_deg ?? 6.0),
            kinetic_inertia:  !!n.kinetic_inertia,
            glide_friction:   Number(n.glide_friction ?? 0.82),
            exp_power:        Number(n.exp_power ?? 1.0),
            sigmoid_mid:      Number(n.sigmoid_mid ?? 0.5),
            sigmoid_steep:    Number(n.sigmoid_steep ?? 4.0),
            velocity_cap:     Number(n.velocity_cap ?? 0.0),
            gforce_gain:      Number(n.gforce_gain ?? 0.0),
            soft_edge_damp:   !!n.soft_edge_damp,
            curve_nodes:      Array.isArray(n.curve_nodes)
                ? n.curve_nodes.slice().sort((a, b) => a.x - b.x) : []
        };
    }

    // Hardware DPI is carried ALONGSIDE the engine document, not inside it:
    // the daemon's JSON schema is fixed and an unknown field sinks the whole
    // parse. It lives on the profile object instead, and is applied through
    // LogiTune. 0 or absent means "leave the mouse alone", so a profile that
    // only cares about the curve does not drag DPI around with it.
    function applyDpi(p) {
        const want = Number(p?.dpi ?? 0);
        if (!want || want <= 0) return;
        if (!LogiTune.available) return;
        LogiTune.setDpi(want);
    }

    // Writing the file IS applying it — the daemon watches
    // /dev/shm/kinetix-config.json and reloads within ~50ms. Written twice:
    // /dev/shm is what it reads but is tmpfs and does not survive a reboot;
    // the ~/.config copy is what kinetix-run restores from at login.
    //
    // Heredoc rather than echo '...': the JSON is interpolated into a shell
    // command and a single quote anywhere in it would end the string.
    function write(settings) {
        const doc = root.normalise(settings);
        Quickshell.execDetached(["bash", "-c",
            "cat > /dev/shm/kinetix-config.json <<'KXEOF'\n"
            + JSON.stringify(doc) + "\nKXEOF\n"
            + "cp -f /dev/shm/kinetix-config.json \"$HOME/.config/kinetix-config.json\" 2>/dev/null"]);
    }

    // Called by the panel when the user changes something by hand: that
    // becomes the new base, and is applied immediately unless a profile is
    // currently in charge.
    function setBase(settings) {
        root.baseSettings = settings;
        if (!root.activeProfile) root.write(settings);
    }

    property string _lastApplied: ""

    function apply() {
        const p = root.activeProfile;
        const target = p ? p.settings : root.baseSettings;
        if (!target) return;   // nothing hand-tuned yet and no profile matches
        // Cheap guard against rewriting the same document on every focus
        // change — the daemon reloads on every write, and a mouse that
        // re-initialises whenever you alt-tab feels like a stutter.
        const key = JSON.stringify(root.normalise(target));
        if (key === root._lastApplied) return;
        root._lastApplied = key;
        root.write(target);
        root.applyDpi(p ?? { dpi: root.baseDpi });
    }

    // DPI to return to when no profile claims the context, captured the first
    // time we see a real reading so leaving a profiled app restores it.
    property int baseDpi: 0
    Connections {
        target: LogiTune
        function onDpiChanged() {
            if (root.baseDpi === 0 && LogiTune.dpi > 0 && !root.activeProfile)
                root.baseDpi = LogiTune.dpi;
        }
    }

    onActiveProfileChanged: root.apply()
}
