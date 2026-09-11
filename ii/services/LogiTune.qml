pragma Singleton
pragma ComponentBehavior: Bound

// Hardware settings for the MX Master, via the user's own `logitune-cli`.
//
// Wraps ~/.scripts/logitune-cli rather than calling solaar directly. That
// script is already running as a daemon (`logitune-cli --daemon`), already
// reapplies settings when the mouse reconnects, and already publishes
// everything this needs to /dev/shm/logitune-cli-status.json. Reading that
// file is instant; shelling out to `solaar show` is a multi-second HID++
// round-trip over Bluetooth that would stall a binding.
//
// Why this belongs next to KinetiX: KinetiX shapes the pointer in SOFTWARE,
// reshaping deltas the kernel already produced. DPI decides how many counts
// exist to be reshaped in the first place. Tuning the curve without being able
// to set DPI is tuning half the system.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string statusPath: "/dev/shm/logitune-cli-status.json"

    property var status: ({})

    // logitune-cli targets one device by name (DEVICE_NAME in the script).
    readonly property string deviceLabel: "MX Master 3S"
    readonly property bool connected:   root.status?.connected === true
    readonly property int  dpi:         root.status?.dpi ?? 0
    readonly property int  battery:     root.status?.battery_percentage ?? 0
    readonly property string batteryState: root.status?.battery_state ?? ""
    readonly property bool smartShift:  root.status?.smartshift_enabled === true
    readonly property int  smartShiftThreshold: root.status?.smartshift_threshold ?? 10
    readonly property bool hiResScroll: root.status?.hires_scroll === true

    // True once the daemon has published anything at all. Distinguishes "no
    // MX Master on this machine" from "not read yet", so the UI can hide
    // rather than render a dead control.
    property bool available: false

    // The MX Master 3S sensor's own range, as reported by solaar:
    //   possible values: one of [ 200, 250, ... 8000 ]
    readonly property int minDpi: 200
    readonly property int maxDpi: 8000
    readonly property int step: 50

    property bool busy: false
    // The value we last ASKED the device for. `dpi` stays on the confirmed
    // reading from the status file, so the UI can show "3200 dpi…" during the
    // round-trip without ever presenting an unconfirmed value as fact.
    property int pendingDpi: 0

    FileView {
        id: statusFile
        // Qt.resolvedUrl, not a bare path: FileView takes a URL, and a bare
        // "/dev/shm/..." silently never loads — which is why the panel showed
        // 0 dpi while the status file said 3500.
        path: Qt.resolvedUrl(root.statusPath)
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(String(statusFile.text()));
                if (parsed && typeof parsed === "object") {
                    root.status = parsed;
                    root.available = true;
                }
            } catch (e) {
                // A half-written file is not a disconnected mouse — keep the
                // last good reading rather than blanking the UI mid-write.
            }
        }
    }

    function _run(args) {
        root.busy = true;
        proc.command = ["bash", "-c",
            "\"$HOME/.scripts/logitune-cli\" " + args + " >/dev/null 2>&1"];
        proc.running = true;
    }

    Process {
        id: proc
        onExited: {
            root.busy = false;
            // The daemon rewrites the status file after applying, but nudge a
            // read anyway: the device can clamp or refuse a value, and the UI
            // should show what the mouse actually took, not what we asked for.
            statusFile.reload();
        }
    }

    /** Snap to the sensor's 50-DPI grid and apply. */
    function setDpi(v) {
        if (!root.available) return false;
        const clamped = Math.max(root.minDpi, Math.min(root.maxDpi,
            Math.round(v / root.step) * root.step));
        if (clamped === root.dpi && !root.busy) return true;
        root.pendingDpi = clamped;
        root._run("--set-dpi " + clamped);
        return true;
    }

    function setSmartShift(mode) {   // "freespin" | "ratchet"
        if (!root.available) return false;
        root._run("--set-smartshift " + mode);
        return true;
    }

    function setSmartShiftThreshold(t) {
        if (!root.available) return false;
        root._run("--threshold " + Math.max(1, Math.min(255, Math.round(t))));
        return true;
    }

    function setHiResScroll(on) {
        if (!root.available) return false;
        root._run("--set-hires " + (on ? "on" : "off"));
        return true;
    }
}
