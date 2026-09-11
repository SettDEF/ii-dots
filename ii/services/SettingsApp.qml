pragma Singleton
pragma ComponentBehavior: Bound

// The settings window is a SEPARATE quickshell instance (`qs -p settings.qml`),
// not a panel inside this shell — so unlike `display` or `kinetix` it cannot be
// toggled by flipping a GlobalStates bool. It has to be launched and killed as
// a process.
//
// Everything that opens settings goes through here. Before this, three call
// sites each ran their own `execDetached(["qs", "-p", ...])` with no duplicate
// check, so clicking settings in the sidebar and again in the start menu left
// you with two windows fighting over the same config file.
//
//   -n / --no-duplicate   makes the launch itself idempotent
//   qs kill -p <path>     selects the instance by config path

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string qmlPath: Quickshell.shellPath("settings.qml")

    // Tracks the last known state so the UI can reflect it. Updated by check().
    property bool running: false

    function open() {
        Quickshell.execDetached(["qs", "-n", "-p", root.qmlPath]);
        root.running = true;
    }

    function close() {
        Quickshell.execDetached(["qs", "kill", "-p", root.qmlPath]);
        root.running = false;
    }

    // Ask qs which instances exist rather than trusting our own flag: the
    // window can be closed from its own titlebar, which we never hear about.
    function toggle() {
        Quickshell.execDetached(["bash", "-c",
            "if qs list --all 2>/dev/null | grep -qF 'Config path: " + root.qmlPath + "'; then "
            + "qs kill -p '" + root.qmlPath + "'; else "
            + "qs -n -p '" + root.qmlPath + "'; fi"]);
    }

    function check() {
        checkProc.running = true;
    }

    Process {
        id: checkProc
        command: ["bash", "-c",
            "qs list --all 2>/dev/null | grep -cF 'Config path: " + root.qmlPath + "'"]
        stdout: StdioCollector {
            onStreamFinished: root.running = parseInt(text.trim() || "0") > 0
        }
    }
}
