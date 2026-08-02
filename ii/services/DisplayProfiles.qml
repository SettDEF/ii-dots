pragma Singleton
pragma ComponentBehavior: Bound

// Per-monitor display configuration.
//
// WHY THIS EXISTS
// Every monitor setting in this shell used to go through
// `hyprctl keyword monitor ...`, and under a Lua config Hyprland answers
// "unknown request" to `keyword` — so none of it did anything. HyprDispatch
// already documented that for dispatchers and gave up on keywords; both
// MonitorManager and DisplaySettings.applyMonitor called execDetached directly
// and so bypassed even that warning. Sliders moved, Apply lit up, nothing
// changed.
//
// The working transport on Hyprland 0.56 is the `eval` IPC request carrying
// Lua, which is what the config itself is written in:
//
//   hyprctl eval 'hl.monitor({ output = "eDP-1", mode = "2560x1600@180",
//                              position = "0x0", scale = "1.67",
//                              sdrsaturation = "1.15" })'
//
// TYPE CONTRACT (verified against 0.56.0-31-gdd90383 by probing each key)
//   strings : output, mode, position, scale, sdrbrightness, sdrsaturation, cm, mirror
//   numbers : vrr, bitdepth, transform
// Passing vrr as a string fails loudly with
//   "field 'vrr': integer type requires a bool or an integer"
// while a wrong-typed key elsewhere can make the WHOLE call a no-op that still
// answers "ok" — which is why every setter here goes through luaField().
//
// hl.monitor merges into the existing monitor config rather than replacing it,
// so omitting a key leaves it alone. Profiles therefore store only what the
// user has actually chosen, and an empty profile is a real "leave it alone".

import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string storePath:
        Quickshell.env("HOME") + "/.local/state/quickshell/user/displayProfiles.json"

    // { monitorName: { mode, scale, position, vrr, bitdepth, transform,
    //                  sdrbrightness, sdrsaturation, cm, mirror, disabled } }
    property var profiles: ({})

    // Re-apply a monitor's profile whenever it reappears (dock/undock, cable
    // swap). Off by default because it fights manual `hyprctl` experiments.
    property bool autoApply: false

    // Set while applying so the HyprlandData refresh we trigger does not look
    // like a user-initiated change and bounce back into apply().
    property bool applying: false

    signal applied(string name, string summary)
    signal failed(string name, string message)

    // ── Which keys exist, and how each must be serialised ────────────────
    // Kept as data rather than a switch so the UI can enumerate the axes
    // instead of hard-coding a second copy of this list.
    readonly property var axes: [
        { key: "mode",          type: "string", label: "Resolution & refresh" },
        { key: "position",      type: "string", label: "Position" },
        { key: "scale",         type: "string", label: "Scale" },
        { key: "transform",     type: "int",    label: "Rotation" },
        { key: "vrr",           type: "int",    label: "Variable refresh" },
        { key: "bitdepth",      type: "int",    label: "Colour depth" },
        { key: "cm",            type: "string", label: "Colour management" },
        { key: "sdrbrightness", type: "string", label: "SDR brightness" },
        { key: "sdrsaturation", type: "string", label: "SDR saturation" },
        { key: "mirror",        type: "string", label: "Mirror of" },
    ]

    function axisType(key) {
        const a = root.axes.find(x => x.key === key);
        return a ? a.type : "string";
    }

    // ── Lua serialisation ────────────────────────────────────────────────
    function luaQuote(s) {
        return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
    }

    /// Render one `key = value` pair with the type Hyprland demands, or ""
    /// when the value is absent/unusable. Returning "" rather than guessing is
    /// deliberate: a wrongly typed field silently voids the entire call.
    function luaField(key, value) {
        if (value === undefined || value === null || value === "")
            return "";
        if (root.axisType(key) === "int") {
            const n = Number(value);
            if (!isFinite(n)) return "";
            // Booleans arrive from switches; Lua wants 0/1 here.
            return key + " = " + Math.round(n);
        }
        return key + " = " + root.luaQuote(value);
    }

    /// Build the full `hl.monitor({...})` expression for a profile.
    /// Returns "" when there is nothing to say.
    function luaFor(name, profile) {
        if (!name) return "";
        const p = profile ?? root.profiles[name] ?? {};
        const parts = [ "output = " + root.luaQuote(name) ];

        // Disabled is a whole-monitor verb, not a field — and it must not be
        // combined with mode/scale, which Hyprland would then try to apply to
        // a monitor it is switching off.
        if (p.disabled === true)
            return "hl.monitor({ output = " + root.luaQuote(name) + ", disabled = true })";

        for (const axis of root.axes) {
            const f = root.luaField(axis.key, p[axis.key]);
            if (f.length > 0) parts.push(f);
        }
        if (parts.length === 1) return "";   // only the output name — nothing set
        return "hl.monitor({ " + parts.join(", ") + " })";
    }

    // ── Guards ───────────────────────────────────────────────────────────
    /// Refuse anything that would leave no enabled output. Losing every
    /// display means a TTY to recover, which is not a thing a settings panel
    /// should ever be able to do to you.
    function wouldBlackout(name, profile) {
        if (!(profile?.disabled === true)) return false;
        const live = HyprlandData.monitors ?? [];
        const stillOn = live.filter(m =>
            m.name !== name && (m.disabled ?? false) !== true);
        return stillOn.length === 0;
    }

    // ── Apply ────────────────────────────────────────────────────────────
    function apply(name) {
        const p = root.profiles[name];
        if (!p) return;
        if (root.wouldBlackout(name, p)) {
            root.failed(name, "Refused: that would turn off the last active display.");
            return;
        }
        const lua = root.luaFor(name, p);
        if (lua.length === 0) return;

        root.applying = true;
        applyProc.command = ["hyprctl", "eval", lua];
        applyProc.pendingName = name;
        applyProc.running = true;
    }

    function applyAll() {
        for (const name of Object.keys(root.profiles))
            root.apply(name);
    }

    // ── Mutation ─────────────────────────────────────────────────────────
    /// Set one axis on one monitor. Pass undefined to clear it back to
    /// "inherit whatever Hyprland is doing".
    function set(name, key, value) {
        if (!name) return;
        const next = Object.assign({}, root.profiles);
        const p = Object.assign({}, next[name] ?? {});
        if (value === undefined || value === null || value === "")
            delete p[key];
        else
            p[key] = value;
        next[name] = p;
        root.profiles = next;
        root.save();
    }

    function get(name, key, fallback) {
        const v = root.profiles[name]?.[key];
        return (v === undefined) ? fallback : v;
    }

    function has(name, key) {
        return root.profiles[name]?.[key] !== undefined;
    }

    /// Number of axes explicitly set for a monitor — drives the "N overrides"
    /// badge so a monitor with a profile is distinguishable at a glance.
    function overrideCount(name) {
        const p = root.profiles[name];
        if (!p) return 0;
        return Object.keys(p).filter(k => p[k] !== undefined && p[k] !== "").length;
    }

    /// Snapshot a monitor's CURRENT live state into its profile, so "make this
    /// stick" does not mean re-typing values that are already correct.
    function capture(name) {
        const m = (HyprlandData.monitors ?? []).find(x => x.name === name);
        if (!m) return;
        const next = Object.assign({}, root.profiles);
        next[name] = {
            mode: `${m.width}x${m.height}@${Number(m.refreshRate).toFixed(3)}`,
            position: `${m.x}x${m.y}`,
            scale: Number(m.scale).toFixed(6).replace(/0+$/, "").replace(/\.$/, ""),
            transform: m.transform ?? 0,
            vrr: (m.vrr === true || m.vrr === 1) ? 1 : 0,
            bitdepth: String(m.currentFormat ?? "").indexOf("2101010") >= 0 ? 10 : 8,
            cm: m.colorManagementPreset ?? "srgb",
            sdrbrightness: Number(m.sdrBrightness ?? 1).toFixed(2),
            sdrsaturation: Number(m.sdrSaturation ?? 1).toFixed(2),
        };
        root.profiles = next;
        root.save();
    }

    /// Drop a monitor's profile entirely. Does NOT revert the live state —
    /// Hyprland has no "undo", so this only stops us re-imposing it. Reload
    /// the compositor config to get back to declared defaults.
    function clear(name) {
        const next = Object.assign({}, root.profiles);
        delete next[name];
        root.profiles = next;
        root.save();
    }

    function clearAll() {
        root.profiles = ({});
        root.save();
    }

    /// Copy one monitor's settings onto another, minus the ones that are
    /// inherently about a specific panel (position, mode) — those would place
    /// two monitors on top of each other or ask for a mode the target lacks.
    function copyTo(fromName, toName) {
        const src = root.profiles[fromName];
        if (!src || !toName || fromName === toName) return;
        const next = Object.assign({}, root.profiles);
        const dst = Object.assign({}, next[toName] ?? {});
        for (const axis of root.axes) {
            if (axis.key === "position" || axis.key === "mode" || axis.key === "mirror")
                continue;
            if (src[axis.key] !== undefined) dst[axis.key] = src[axis.key];
        }
        next[toName] = dst;
        root.profiles = next;
        root.save();
    }

    // ── Persistence ──────────────────────────────────────────────────────
    function save() {
        store.setText(JSON.stringify({
            profiles: root.profiles,
            autoApply: root.autoApply,
        }, null, 2));
    }

    onAutoApplyChanged: root.save()

    Process {
        id: applyProc
        property string pendingName: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const out = String(this.text ?? "").trim();
                // Hyprland answers "ok" on success and "error: ..." on a Lua
                // fault. It also answers "ok" for a call that parsed but did
                // nothing, so this is a floor on correctness, not a ceiling.
                if (out.startsWith("error")) {
                    root.failed(applyProc.pendingName, out);
                } else {
                    root.applied(applyProc.pendingName, out);
                }
                HyprlandData.updateMonitors();
                root.applying = false;
            }
        }
    }

    FileView {
        id: store
        path: Qt.resolvedUrl(root.storePath)
        onLoaded: {
            try {
                const d = JSON.parse(store.text() || "{}");
                root.profiles = d.profiles ?? {};
                root.autoApply = d.autoApply === true;
            } catch (e) {
                root.profiles = ({});
            }
        }
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound)
                store.setText(JSON.stringify({ profiles: {}, autoApply: false }, null, 2));
        }
    }
}
