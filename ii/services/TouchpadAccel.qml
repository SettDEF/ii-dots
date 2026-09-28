pragma Singleton
pragma ComponentBehavior: Bound

// Touchpad speed profile via libinput's per-device `sensitivity` (-1..1) — NOT
// a grab, and NOT a hand-rolled custom accel curve. A custom curve's velocity
// steps don't match a touchpad's raw units, so a slow finger landed on a
// high-gain step and flew. sensitivity is a simple, predictable speed scale on
// top of the well-behaved adaptive profile. Persisted to a sourced conf.

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string deviceName: ""
    property bool enabled: Config.options?.kinetixTouchpad?.enabled ?? false
    // Hyprland sensitivity: -1 (slowest) .. 0 (default) .. 1 (fastest).
    property real sensitivity: Config.options?.kinetixTouchpad?.sensitivity ?? 0.0
    // adaptive = libinput's normal acceleration; flat = 1:1, no accel.
    property bool flat: Config.options?.kinetixTouchpad?.flat ?? false

    readonly property string confPath:
        Quickshell.env("HOME") + "/.config/hypr/custom/touchpad-accel.conf"

    function clampedSens() {
        return Math.max(-1, Math.min(1, root.sensitivity));
    }

    // A per-device config stops the touchpad inheriting global input:touchpad,
    // so its click/scroll settings must be re-asserted or they silently turn
    // off — which is what killed tap-to-click.
    readonly property var tpDefaults: ({
        "tap-to-click": true,
        "tap-and-drag": true,
        natural_scroll: true,
        clickfinger_behavior: true,
        disable_while_typing: true
    })

    /// `hl.device`, not `keyword`. Under a Lua config every `keyword` request
    /// answers "unknown request", AND a failed request aborts the rest of a
    /// --batch — so the whole chain below did nothing, including the settings
    /// re-asserted to keep tap-to-click alive.
    function _applyDevice(fields) {
        const parts = [`name = '${root.deviceName.replace(/'/g, "\\'")}'`];
        for (const k of Object.keys(fields)) {
            const v = fields[k];
            const lit = (typeof v === "boolean" || typeof v === "number")
                ? String(v) : `'${String(v)}'`;
            // Hyprland's own keys contain hyphens, which are not bare Lua
            // identifiers, so every key goes through the bracket form.
            parts.push(`["${k}"] = ${lit}`);
        }
        Quickshell.execDetached(["hyprctl", "eval", `hl.device({ ${parts.join(", ")} })`]);
    }

    function apply() {
        if (root.deviceName.length === 0) { probe.running = true; return; }
        const fields = Object.assign({}, root.tpDefaults, root.enabled
            ? { accel_profile: root.flat ? "flat" : "adaptive",
                sensitivity: Number(root.clampedSens().toFixed(3)) }
            : { accel_profile: "adaptive", sensitivity: 0 });
        root._applyDevice(fields);
        root.persist();
    }

    function persist() {
        if (root.deviceName.length === 0) return;
        const body = root.enabled
            ? ("device {\n    name = " + root.deviceName
               + "\n    accel_profile = " + (root.flat ? "flat" : "adaptive")
               + "\n    sensitivity = " + root.clampedSens().toFixed(3)
               + "\n    natural_scroll = true"
               + "\n    tap-to-click = true"
               + "\n    tap-and-drag = true"
               + "\n    clickfinger_behavior = true"
               + "\n    disable_while_typing = true\n}\n")
            : "# touchpad: default\n";
        Quickshell.execDetached(["bash", "-c",
            "f='" + root.confPath + "'; cat > \"$f\" <<'TPEOF'\n" + body + "TPEOF\n"
            + "grep -q 'touchpad-accel.conf' ~/.config/hypr/hyprland.conf "
            + "|| echo 'source=custom/touchpad-accel.conf' >> ~/.config/hypr/hyprland.conf"]);
    }

    Process {
        id: probe
        command: ["bash", "-c",
            "hyprctl devices -j 2>/dev/null | jq -r '.mice[]?|select(.name|test(\"touchpad\";\"i\"))|.name' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = String(text).trim();
                if (n.length > 0 && n !== root.deviceName) {
                    root.deviceName = n;
                    if (root.enabled) root.apply();
                }
            }
        }
    }

    Component.onCompleted: probe.running = true
}
