pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The handful of settings that belong to the machine rather than to the shell:
 * time zone, system locale, and the console keymap.
 *
 * These live in /etc and only root may change them, so every write goes
 * through pkexec and the user gets a password prompt. Reads are free, so the
 * page can always show the truth even when it cannot change it.
 *
 * Deliberately NOT the Hyprland keyboard layout — that is KeyboardLayout.qml,
 * which applies live and needs no root. The two are easy to confuse: this one
 * is what the TTY and the display manager use, that one is what your session
 * types with.
 */
Singleton {
    id: root

    property string timezone: ""
    property string locale: ""
    property string consoleKeymap: ""
    property var timezones: []
    property bool busy: false
    /// "" when the last write succeeded, otherwise what went wrong.
    property string lastError: ""

    readonly property bool canWrite: root._hasPkexec
    property bool _hasPkexec: false

    function refresh() {
        readProc.running = false;
        readProc.running = true;
    }

    function setTimezone(tz) {
        if (!tz || tz === root.timezone) return;
        root._apply(["pkexec", "timedatectl", "set-timezone", tz]);
    }

    function setLocale(loc) {
        if (!loc || loc === root.locale) return;
        // set-locale only succeeds for a locale that has been generated, so a
        // bad pick fails loudly here instead of leaving a system that boots
        // into C. The error is surfaced rather than swallowed.
        root._apply(["pkexec", "localectl", "set-locale", `LANG=${loc}`]);
    }

    function setConsoleKeymap(km) {
        if (!km || km === root.consoleKeymap) return;
        root._apply(["pkexec", "localectl", "set-keymap", km]);
    }

    function _apply(cmd) {
        if (root.busy) return;
        root.lastError = "";
        root.busy = true;
        applyProc.command = cmd;
        applyProc.running = false;
        applyProc.running = true;
    }

    Component.onCompleted: root.refresh()

    Process {
        id: readProc
        running: true
        // One shell for all of it: three separate Processes for three one-line
        // reads is three process spawns every time the page opens.
        command: ["bash", "-c",
            "command -v pkexec >/dev/null && echo 'PKEXEC=1' || echo 'PKEXEC=0'; " +
            "timedatectl show -p Timezone --value 2>/dev/null | sed 's/^/TZ=/'; " +
            "localectl status 2>/dev/null | sed -n 's/.*System Locale: LANG=\\(.*\\)/LOCALE=\\1/p'; " +
            "localectl status 2>/dev/null | sed -n 's/.*VC Keymap: \\(.*\\)/KEYMAP=\\1/p'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = String(text).split("\n");
                for (const line of lines) {
                    const eq = line.indexOf("=");
                    if (eq < 0) continue;
                    const k = line.slice(0, eq);
                    const v = line.slice(eq + 1).trim();
                    if (k === "PKEXEC") root._hasPkexec = v === "1";
                    else if (k === "TZ") root.timezone = v;
                    else if (k === "LOCALE") root.locale = v;
                    else if (k === "KEYMAP") root.consoleKeymap = v;
                }
            }
        }
    }

    Process {
        id: tzProc
        running: true
        command: ["timedatectl", "list-timezones"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.timezones = String(text).split("\n").map(l => l.trim()).filter(l => l.length > 0);
            }
        }
    }

    Process {
        id: applyProc
        stderr: StdioCollector {
            onStreamFinished: root.lastError = String(text).trim()
        }
        onExited: (code) => {
            root.busy = false;
            // 126 is pkexec's "dismissed or not authorised", which is the user
            // changing their mind rather than a failure worth shouting about.
            if (code === 126 || code === 127) root.lastError = "";
            root.refresh();
        }
    }
}
