pragma Singleton

import QtQuick
import qs.modules.common
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Simple hyprsunset service with automatic mode.
 * In theory we don't need this because hyprsunset has a config file, but it somehow doesn't work.
 * It should also be possible to control it via hyprctl, but it doesn't work consistently either so we're just killing and launching.
 */
Singleton {
    id: root
    property string from: Config.options?.light?.night?.from ?? "19:00" 
    property string to: Config.options?.light?.night?.to ?? "06:30"
    property bool automatic: Config.options?.light?.night?.automatic && (Config?.ready ?? true)
    property int colorTemperature: Config.options?.light?.night?.colorTemperature ?? 5000
    property bool shouldBeOn
    property bool firstEvaluation: true
    property bool active: false

    property int fromHour: Number(from.split(":")[0])
    property int fromMinute: Number(from.split(":")[1])
    property int toHour: Number(to.split(":")[0])
    property int toMinute: Number(to.split(":")[1])

    property int clockHour: DateTime.clock.hours
    property int clockMinute: DateTime.clock.minutes

    property var manualActive
    property int manualActiveHour
    property int manualActiveMinute

    onClockMinuteChanged: reEvaluate()
    onAutomaticChanged: {
        root.manualActive = undefined;
        root.firstEvaluation = true;
        reEvaluate();
    }

    function inBetween(t, from, to) {
        if (from < to) {
            return (t >= from && t <= to);
        } else {
            // Wrapped around midnight
            return (t >= from || t <= to);
        }
    }

    function reEvaluate() {
        const t = clockHour * 60 + clockMinute;
        const from = fromHour * 60 + fromMinute;
        const to = toHour * 60 + toMinute;
        const manualActive = manualActiveHour * 60 + manualActiveMinute;

        if (root.manualActive !== undefined && (inBetween(from, manualActive, t) || inBetween(to, manualActive, t))) {
            root.manualActive = undefined;
        }
        root.shouldBeOn = inBetween(t, from, to);
        if (firstEvaluation) {
            firstEvaluation = false;
            root.ensureState();
        }
    }

    onShouldBeOnChanged: ensureState()
    function ensureState() {
        // console.log("[Hyprsunset] Ensuring state:", root.shouldBeOn, "Automatic mode:", root.automatic);
        if (!root.automatic || root.manualActive !== undefined)
            return;
        if (root.shouldBeOn) {
            root.enable();
        } else {
            root.disable();
        }
    }

    function load() { } // Dummy to force init

    // Empty while the backend is healthy; otherwise why it isn't. Without
    // this a broken hyprsunset just left the toggle sitting on "inactive"
    // with no way to tell that the binary never started — which is exactly
    // what a partial Hypr upgrade does (it links a libhyprutils soname that
    // no longer exists).
    property string backendError: ""
    // undefined = not probed yet, so the first enable() checks once.
    property var backendOk: undefined

    Process {
        id: backendProbe
        command: ["bash", "-c", "hyprsunset --help >/dev/null 2>&1"]
        stderr: StdioCollector { id: probeErr }
        onExited: (code, status) => {
            root.backendOk = (code === 0);
            if (root.backendOk) {
                root.backendError = "";
                root._startHyprsunset();
            } else {
                const why = (probeErr.text || "").trim();
                root.backendError = why.length > 0 ? why : `hyprsunset exited ${code}`;
                console.warn("[Hyprsunset] backend unusable:", root.backendError,
                             "— falling back to redshift");
                root._startFallback();
            }
        }
    }

    function _startHyprsunset() {
        Quickshell.execDetached(["bash", "-c",
            `pidof hyprsunset || hyprsunset --temperature ${root.colorTemperature}`]);
    }

    // redshift sets the gamma ramp once and exits, so it needs re-applying
    // whenever the temperature changes — cheap, and it keeps working when
    // hyprsunset can't start.
    function _startFallback() {
        Quickshell.execDetached(["bash", "-c",
            `command -v redshift >/dev/null && redshift -P -O ${root.colorTemperature} >/dev/null 2>&1`]);
    }

    function enable() {
        root.active = true;
        if (root.backendOk === undefined) {
            backendProbe.running = true;   // probes, then starts the right one
            return;
        }
        if (root.backendOk) root._startHyprsunset();
        else root._startFallback();
    }

    function disable() {
        root.active = false;
        Quickshell.execDetached(["bash", "-c",
            "pkill hyprsunset; command -v redshift >/dev/null && redshift -x >/dev/null 2>&1"]);
    }

    function fetchState() {
        fetchProc.running = true;
    }

    Process {
        id: fetchProc
        running: true
        command: ["bash", "-c", "hyprctl hyprsunset temperature"]
        stdout: StdioCollector {
            id: stateCollector
            onStreamFinished: {
                const output = stateCollector.text.trim();
                if (output.length == 0 || output.startsWith("Couldn't"))
                    root.active = false;
                else
                    root.active = (output != "6500"); // 6500 is the default when off
                // console.log("[Hyprsunset] Fetched state:", output, "->", root.active);
            }
        }
    }

    function toggle(active = undefined) {
        if (root.manualActive === undefined) {
            root.manualActive = root.active;
            root.manualActiveHour = root.clockHour;
            root.manualActiveMinute = root.clockMinute;
        }

        root.manualActive = active !== undefined ? active : !root.manualActive;
        if (root.manualActive) {
            root.enable();
        } else {
            root.disable();
        }
    }

    // Change temp
    Connections {
        target: Config.options.light.night
        function onColorTemperatureChanged() {
            if (!root.active) return;
            if (root.backendOk === false) {
                root._startFallback();   // redshift: re-apply the new temperature
                return;
            }
            HyprDispatch.run(`hyprctl hyprsunset temperature ${Config.options.light.night.colorTemperature}`);
            Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", `${Config.options.light.night.colorTemperature}`]);
        }
    }
}
