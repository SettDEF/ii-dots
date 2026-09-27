pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

/**
 * Backlight control, one BrightnessMonitor per screen.
 *
 * Two transports, picked per screen: an internal panel goes through
 * `brightnessctl`, an external one over DDC/CI through `ddcutil`. DDC is slow
 * and dislikes being written to in bursts, so its writes are debounced and its
 * changes are not animated; a laptop panel takes them immediately.
 *
 * `brightness` is what the user asked for. `multipliedBrightness` is what is
 * actually written, after the anti-flashbang multiplier that dims the backlight
 * when the screen content is bright.
 */
Singleton {
    id: root

    reloadableId: "brightness"

    signal brightnessChanged()

    /// One entry per DDC display found: { name, busNum }.
    property var ddcMonitors: []

    readonly property list<BrightnessMonitor> monitors:
        Quickshell.screens.map(screen => monitorComponent.createObject(root, { screen }))

    function getMonitorForScreen(screen: ShellScreen): var {
        return root.monitors.find(m => m.screen === screen);
    }

    function focusedMonitor(): var {
        const name = Hyprland.focusedMonitor?.name;
        return root.monitors.find(m => m.screen.name === name);
    }

    function stepBrightness(delta: real): void {
        const monitor = root.focusedMonitor();
        if (monitor) monitor.setBrightness(monitor.brightness + delta);
    }

    function increaseBrightness(): void { root.stepBrightness(0.05); }
    function decreaseBrightness(): void { root.stepBrightness(-0.05); }

    // ── Discovery ──────────────────────────────────────────────────────────
    // Screens are enumerated first; the DDC probe follows, and each monitor is
    // initialised in turn once it knows whether it has a bus to talk to.

    onMonitorsChanged: {
        root.ddcMonitors = [];
        ddcDetectProc.running = true;
    }

    /// Sequential, not parallel: two ddcutil calls at once on the same i2c bus
    /// is how you get a display that stops answering.
    function initializeMonitor(index: int): void {
        if (index >= 0 && index < root.monitors.length)
            root.monitors[index].initialize();
    }

    Process {
        id: ddcDetectProc
        command: ["ddcutil", "detect", "--brief"]
        stdout: SplitParser {
            // One blank-line-separated stanza per display.
            splitMarker: "\n\n"
            onRead: data => {
                if (!data.startsWith("Display ")) return;
                const lines = data.split("\n").map(l => l.trim());
                const connector = lines.find(l => l.startsWith("DRM connector:"));
                const bus = lines.find(l => l.startsWith("I2C bus:"));
                if (!connector || !bus) return;
                root.ddcMonitors.push({
                    // "card1-DP-2" -> "DP-2", which is what ShellScreen.name is.
                    name: connector.split("-").slice(1).join("-"),
                    busNum: bus.split("/dev/i2c-")[1]
                });
            }
        }
        onExited: root.initializeMonitor(0)
    }

    /// One writer for every monitor. Writes are short and already serialised by
    /// each monitor's own debounce.
    Process { id: writeProc }

    component BrightnessMonitor: QtObject {
        id: monitor

        required property ShellScreen screen

        property bool isDdc: false
        property string busNum: ""
        property int rawMaxBrightness: 100
        /// What the user asked for, 0..1.
        property real brightness: 0
        /// Anti-flashbang scaling, 0..1.
        property real brightnessMultiplier: 1.0
        property bool ready: false

        /// DDC round-trips take long enough that an animation would queue writes
        /// faster than the display can retire them.
        readonly property bool animateChanges: !monitor.isDdc

        // Not readonly: a Behavior needs to be able to drive it.
        property real multipliedBrightness: {
            const scale = Config.options.light.antiFlashbang.enable
                ? monitor.brightnessMultiplier : 1;
            return Math.max(0, Math.min(1, monitor.brightness * scale));
        }

        onBrightnessChanged: if (monitor.ready) root.brightnessChanged()

        Behavior on multipliedBrightness {
            enabled: monitor.animateChanges
            NumberAnimation {
                duration: 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }

        onMultipliedBrightnessChanged: {
            if (monitor.isDdc) writeTimer.restart();
            else monitor.write();
        }

        function initialize(): void {
            monitor.ready = false;

            // Two screens can report the same connector name; take the first
            // unclaimed bus so they do not both drive one display.
            const claimed = root.monitors
                .slice(0, root.monitors.indexOf(monitor))
                .map(m => m.busNum);
            const match = root.ddcMonitors.find(m =>
                m.name === monitor.screen.name && !claimed.includes(m.busNum));

            monitor.isDdc = !!match;
            monitor.busNum = match?.busNum ?? "";

            readProc.command = monitor.isDdc
                ? ["ddcutil", "-b", monitor.busNum, "getvcp", "10", "--brief"]
                : ["sh", "-c", "printf '%s %s\\n' \"$(brightnessctl g)\" \"$(brightnessctl m)\""];
            readProc.running = true;
        }

        /// Reads the current and maximum value, then hands off to the next
        /// screen whether or not this one answered.
        readonly property Process readProc: Process {
            stdout: StdioCollector {
                onStreamFinished: {
                    // ddcutil --brief: "VCP 10 C <current> <max>"
                    // brightnessctl:   "<current> <max>"
                    const fields = text.trim().split(/\s+/);
                    const max = parseInt(fields[fields.length - 1]);
                    const current = parseInt(fields[fields.length - 2]);
                    if (max > 0 && !isNaN(current)) {
                        monitor.rawMaxBrightness = max;
                        monitor.brightness = current / max;
                        monitor.ready = true;
                    }
                }
            }
            onExited: root.initializeMonitor(root.monitors.indexOf(monitor) + 1)
        }

        /// Debounce for DDC only; a panel writes on the spot.
        readonly property Timer writeTimer: Timer {
            interval: 300
            onTriggered: monitor.write()
        }

        function write(): void {
            const value = Math.max(0, monitor.multipliedBrightness);

            if (monitor.isDdc) {
                // Never 0: some displays read that as "off" and do not come back
                // without a power cycle.
                const raw = Math.max(1, Math.floor(value * monitor.rawMaxBrightness));
                writeProc.exec(["ddcutil", "-b", monitor.busNum, "setvcp", "10", raw]);
                return;
            }

            let percent = Math.floor(value * 100);

            // This panel's firmware curve folds over at the top. amdgpu logs
            // "Using custom brightness curve" and reports a non-linear scale.
            // Measured on the raw device (max 65535), reading actual_brightness
            // back after each write:
            //     64224  (98%) -> actual 65290   brightest, stable
            //     64450        -> actual 65535   last good value
            //     64550        -> actual     0   backlight OFF
            //     65535 (100%) -> actual     0   backlight OFF
            // Above ~64500 the backlight physically switches off, which is why a
            // slider reading 100 looked darker than 0 (at 0 the panel clamps to
            // a lit floor of ~3084). 98% is 99.6% of maximum light, with margin.
            if (percent > 98) percent = 98;

            // "1%" and not "1": brightnessctl reads a bare number as a RAW
            // value, so "1" means 1/65535 — indistinguishable from off.
            const arg = percent <= 0 ? "1%" : `${percent}%`;
            writeProc.exec(["brightnessctl", "--class", "backlight", "s", arg, "--quiet"]);
        }

        function setBrightness(value: real): void {
            monitor.brightness = Math.max(0, Math.min(1, value));
        }

        function setBrightnessMultiplier(value: real): void {
            monitor.brightnessMultiplier = value;
        }
    }

    Component {
        id: monitorComponent
        BrightnessMonitor {}
    }

    // ── Anti-flashbang ─────────────────────────────────────────────────────
    // A dark theme on a screen that suddenly fills with white is the thing this
    // exists for. The screen is sampled after it settles and the backlight is
    // scaled down in proportion to how bright the content turned out to be.

    /// A workspace switch animates, so sampling has to wait for it to finish.
    property int workspaceAnimationDelay: 500
    /// Was 30, which fired a full-screen grim per monitor on every window and
    /// title change — a title storm ran them back to back. 400 coalesces a
    /// burst into one capture.
    property int contentSwitchDelay: 400

    /// Fitted to hand-picked pairs of (screen lightness, comfortable multiplier):
    /// 6.600135 + 216.360356 * e^(-0.0811129189x), over 100 to land in 0..1.
    function brightnessMultiplierForLightness(x: real): real {
        return (6.600135 + 216.360356 * Math.exp(-0.0811129189 * x)) / 100.0;
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: screenScope
            required property var modelData
            readonly property string screenName: screenScope.modelData.name

            Connections {
                enabled: Config.options.light.antiFlashbang.enable
                    && Appearance.m3colors.darkmode
                target: Hyprland
                function onRawEvent(event) {
                    if (event.name === "activewindowv2" || event.name === "windowtitlev2")
                        sampleTimer.interval = root.contentSwitchDelay;
                    else if (event.name === "workspacev2")
                        sampleTimer.interval = root.workspaceAnimationDelay;
                    else return;
                    sampleTimer.restart();
                }
            }

            Timer {
                id: sampleTimer
                interval: root.workspaceAnimationDelay
                onTriggered: {
                    // Restart rather than start: a capture still running is
                    // sampling a screen that has since changed.
                    sampleProc.running = false;
                    sampleProc.running = true;
                }
            }

            /// Straight down a pipe — no temp file to write, clean up, or leave
            /// behind when the shell reloads mid-capture.
            Process {
                id: sampleProc
                command: ["bash", "-c",
                    `grim -o '${StringUtils.shellSingleQuoteEscape(screenScope.screenName)}' -`
                    + ` | "$HOME/.local/bin/tinct" image mean -`]
                stdout: StdioCollector {
                    id: lightnessCollector
                    onStreamFinished: {
                        const lightness = parseFloat(lightnessCollector.text);
                        if (isNaN(lightness)) return;
                        root.getMonitorForScreen(screenScope.modelData)
                            ?.setBrightnessMultiplier(
                                root.brightnessMultiplierForLightness(lightness));
                    }
                }
            }
        }
    }

    // ── External triggers ──────────────────────────────────────────────────

    IpcHandler {
        target: "brightness"
        function increment(): void { root.increaseBrightness() }
        function decrement(): void { root.decreaseBrightness() }
        function set(value: real): void { root.focusedMonitor()?.setBrightness(value) }
    }

    GlobalShortcut {
        name: "brightnessIncrease"
        description: "Increase brightness"
        onPressed: root.increaseBrightness()
    }

    GlobalShortcut {
        name: "brightnessDecrease"
        description: "Decrease brightness"
        onPressed: root.decreaseBrightness()
    }
}
