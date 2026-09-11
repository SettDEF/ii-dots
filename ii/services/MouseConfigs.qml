pragma Singleton
pragma ComponentBehavior: Bound

// Every config file on this machine that has an opinion about the mouse.
//
// There are more of them than anyone keeps in their head, they belong to
// different daemons, and several store the SAME setting independently:
//
//   ~/.config/kinetix-config.json   KinetiX engine   curve, smoothing, sensitivity
//   /dev/shm/kinetix-config.json    KinetiX (live)   the copy the daemon watches
//   ~/.config/logitune-cli.json     logitune-cli     dpi, smartshift, hi-res scroll
//   ~/.config/solaar/config.yaml    solaar           per-device HID++ state, incl. dpi
//
// Two of those record a DPI and nothing reconciles them: whichever daemon
// applies last wins, so they drift and the mouse behaves differently depending
// on start order. Listing the files is the small half; flagging the
// disagreement is the point.
//
// READ-ONLY by design. These belong to their daemons, and a settings panel that
// rewrites another tool's config behind its back is how they drift in the first
// place.
//
// Implemented with FileViews rather than a shell script. The first attempt
// shelled out, and the script — living inside a JS template literal — contained
// bash's ${x:-default}, which QML parsed as interpolation. That one syntax
// error took the whole config down. There is no shell here to get wrong.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") ?? ""

    property bool kinetixExists: false
    property bool kinetixLiveExists: false
    property bool logituneExists: false
    property bool solaarExists: false
    property int logituneDpi: 0
    property int solaarDpi: 0

    readonly property var entries: [
        {
            id: "kinetix", label: "KinetiX curve", owner: "kinetix daemon",
            path: root.home + "/.config/kinetix-config.json",
            exists: root.kinetixExists, dpi: 0,
            note: "Acceleration curve, smoothing, sensitivity"
        },
        {
            id: "kinetix-live", label: "KinetiX (live)", owner: "kinetix daemon",
            path: "/dev/shm/kinetix-config.json",
            exists: root.kinetixLiveExists, dpi: 0,
            note: "tmpfs copy the engine watches; gone after a reboot"
        },
        {
            id: "logitune", label: "LogiTune", owner: "logitune-cli",
            path: root.home + "/.config/logitune-cli.json",
            exists: root.logituneExists, dpi: root.logituneDpi,
            note: "DPI, SmartShift, hi-res scroll"
        },
        {
            id: "solaar", label: "Solaar", owner: "solaar",
            path: root.home + "/.config/solaar/config.yaml",
            exists: root.solaarExists, dpi: root.solaarDpi,
            note: "Per-device HID++ state"
        }
    ]

    readonly property var dpiClaims: root.entries.filter(e => e.exists && e.dpi > 0)

    // The state worth surfacing: two files disagreeing about the same knob.
    readonly property bool dpiConflict: {
        const v = root.dpiClaims.map(c => c.dpi);
        return v.length > 1 && v.some(x => x !== v[0]);
    }

    readonly property string dpiSummary: {
        if (root.dpiClaims.length === 0) return "";
        if (!root.dpiConflict)
            return root.dpiClaims[0].dpi + " dpi, agreed by " + root.dpiClaims.length
                + " source" + (root.dpiClaims.length === 1 ? "" : "s");
        return root.dpiClaims.map(c => c.label + ": " + c.dpi).join("   ·   ");
    }

    readonly property int presentCount: root.entries.filter(e => e.exists).length

    function refresh() {
        fKinetix.reload(); fKinetixLive.reload();
        fLogitune.reload(); fSolaar.reload();
    }

    function openInEditor(path) {
        if (!path || path.length === 0) return;
        Quickshell.execDetached(["xdg-open", path]);
    }

    // Existence is inferred from load success: FileView reports a failure for a
    // missing path, which is exactly the signal wanted, so no stat is needed.
    FileView {
        id: fKinetix
        path: root.home + "/.config/kinetix-config.json"
        onLoaded: root.kinetixExists = true
        onLoadFailed: root.kinetixExists = false
    }
    FileView {
        id: fKinetixLive
        path: "/dev/shm/kinetix-config.json"
        onLoaded: root.kinetixLiveExists = true
        onLoadFailed: root.kinetixLiveExists = false
    }

    FileView {
        id: fLogitune
        path: root.home + "/.config/logitune-cli.json"
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: {
            root.logituneExists = false;
            root.logituneDpi = 0;
        }
        onLoaded: {
            root.logituneExists = true;
            try {
                const j = JSON.parse(String(fLogitune.text()));
                root.logituneDpi = Number(j?.dpi ?? 0) || 0;
            } catch (e) {
                root.logituneDpi = 0;
            }
        }
    }

    // Solaar writes YAML. Rather than pull in a parser for one integer, the
    // `dpi:` line is matched directly — the file is a flat per-device mapping
    // and the key appears once per device.
    FileView {
        id: fSolaar
        path: root.home + "/.config/solaar/config.yaml"
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: {
            root.solaarExists = false;
            root.solaarDpi = 0;
        }
        onLoaded: {
            root.solaarExists = true;
            const m = /^\s*dpi:\s*(\d+)\s*$/m.exec(String(fSolaar.text()));
            root.solaarDpi = m ? parseInt(m[1], 10) : 0;
        }
    }
}
