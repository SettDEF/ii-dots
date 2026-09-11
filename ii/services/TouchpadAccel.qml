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
    function tpKeywords(dev) {
        return " ; keyword " + dev + ":tap-to-click true"
             + " ; keyword " + dev + ":tap-and-drag true"
             + " ; keyword " + dev + ":natural_scroll true"
             + " ; keyword " + dev + ":clickfinger_behavior true"
             + " ; keyword " + dev + ":disable_while_typing true";
    }

    function apply() {
        if (root.deviceName.length === 0) { probe.running = true; return; }
        const dev = "device[" + root.deviceName + "]";
        if (root.enabled) {
            Quickshell.execDetached(["hyprctl", "--batch",
                "keyword " + dev + ":accel_profile " + (root.flat ? "flat" : "adaptive") + " ; "
                + "keyword " + dev + ":sensitivity " + root.clampedSens().toFixed(3)
                + root.tpKeywords(dev)]);
        } else {
            Quickshell.execDetached(["hyprctl", "--batch",
                "keyword " + dev + ":accel_profile adaptive ; "
                + "keyword " + dev + ":sensitivity 0"
                + root.tpKeywords(dev)]);
        }
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
