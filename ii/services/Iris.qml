pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * Keyboard backlight control.
 *
 * The GZ302 folio is a SINGLE-ZONE RGB backlight — ASUS's own spec confirms it,
 * and both HID transports were tested across every interface. So there is one
 * colour for the whole board, not per-key. Everything here is built around that.
 *
 * Colour goes over direct HID rather than asusd, because asusd persists its
 * config on every colour write (~30 ms and a disk write each). Sending the
 * Aura apply command without the save command costs nothing, which is what
 * makes live animation viable.
 *
 * Brightness still goes through asusd: it is the same value the Fn key moves,
 * so sharing it keeps the panel and the hardware key in agreement.
 */
Singleton {
    id: root

    readonly property string bin: FileUtils.trimFileProtocol(`${Directories.home}/.local/bin/iris`)

    property int brightness: 0
    readonly property int maxBrightness: 3
    property string currentColor: ""
    property string activeEffect: ""
    property bool available: false

    readonly property var effects: [
        { name: "rainbow",  icon: "gradient",       label: "Rainbow" },
        { name: "spectrum", icon: "palette",        label: "Spectrum" },
        { name: "wave",     icon: "waves",          label: "Wave" },
        { name: "fire",     icon: "local_fire_department", label: "Fire" },
        { name: "ocean",    icon: "water",          label: "Ocean" },
        { name: "pulse",    icon: "favorite",       label: "Pulse" },
        { name: "react",    icon: "keyboard",       label: "Reactive" }
    ]

    // Restarting a Process by toggling `running` false->true in one tick does
    // NOT restart it — the change is coalesced and the command never runs.
    // Deferring the restart is what actually re-executes it.
    function refresh(): void {
        if (stateProc.running) {
            stateProc.running = false;
            Qt.callLater(() => stateProc.running = true);
        } else {
            stateProc.running = true;
        }
    }

    // execDetached rather than a Process: these are fire-and-forget one-shots,
    // and a slider emits them faster than a Process can cycle its lifecycle.
    // The local property updates immediately so the UI never lags the drag.
    function setBrightness(v: int): void {
        const n = Math.max(0, Math.min(root.maxBrightness, Math.round(v)));
        root.brightness = n;
        Quickshell.execDetached([root.bin, "bright", String(n)]);
    }

    /**
     * Stops any running effect first: an effect writes colour continuously, so
     * setting a colour under one would be overwritten within a frame.
     */
    function setColor(hex: string): void {
        if (!hex) return;
        root.stopEffect();
        root.currentColor = hex;
        Quickshell.execDetached([root.bin, "hid", "solid", hex, "--vivid"]);
    }

    function runEffect(name: string): void {
        root.stopEffect();
        root.activeEffect = name;
        effectProc.command = [root.bin, "fx", name];
        effectProc.running = true;
    }

    function stopEffect(): void {
        root.activeEffect = "";
        effectProc.running = false;
    }

    /** Re-apply the wallpaper palette colour that tinct last wrote. */
    function followWallpaper(): void {
        root.stopEffect();
        Quickshell.execDetached(["bash", "-c",
            `cat ~/.config/iris/color | ${root.bin} hid solid - --vivid`]);
        colorTimer.restart();
    }

    // Long-running: an effect renders until stopped. Killed on switch.
    Process { id: effectProc }

    // Re-read the remembered colour shortly after applying it.
    Timer {
        id: colorTimer
        interval: 400
        onTriggered: {
            colorProc.running = false;
            Qt.callLater(() => colorProc.running = true);
        }
    }

    Process {
        id: stateProc
        running: true
        command: [root.bin, "state"]
        stdout: StdioCollector {
            id: stateOut
            onStreamFinished: {
                const m = stateOut.text.match(/brightness\s+(\d+)/);
                if (m) root.brightness = parseInt(m[1]);
                root.available = (m !== null);
            }
        }
    }

    Process {
        id: colorProc
        running: true
        command: ["cat", FileUtils.trimFileProtocol(`${Directories.home}/.config/iris/color`)]
        stdout: StdioCollector {
            id: colorOut
            onStreamFinished: root.currentColor = colorOut.text.trim()
        }
    }
}
