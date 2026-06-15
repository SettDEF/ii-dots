pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Shared loader for the two on-disk recents files used by the wallpaper /
 * theme UIs:
 *   - wallpaper-recents.jsonl  (managed by switchwall.sh + wallpaper-recents.sh)
 *   - walltune-history.jsonl   (managed by WallTune reprocess writes)
 *
 * Three places used to maintain duplicate Process+StdioCollector blocks for
 * these. Now they all read from this singleton; refresh() should be called
 * whenever a panel that displays recents opens, or after a write that should
 * appear in the lists.
 */
Singleton {
    id: root

    // Resolved wallpaper paths, newest first. Empty until the first refresh.
    property var recents: []
    // Parsed WallTune history entries, newest first.
    property var walltuneHistory: []

    function refreshRecents() {
        recentsProc.command = ["bash",
            Quickshell.shellPath("scripts") + "/colors/wallpaper-recents.sh",
            "list"]
        recentsProc.running = true
    }

    function refreshWalltuneHistory() {
        walltuneProc.command = ["bash", "-c",
            `f="$HOME/.local/state/quickshell/walltune-history.jsonl"; ` +
            `[ -f "$f" ] && cat "$f" || true`]
        walltuneProc.running = true
    }

    function refresh() {
        refreshRecents()
        refreshWalltuneHistory()
    }

    Process {
        id: recentsProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.recents = text.trim().length === 0
                    ? []
                    : text.trim().split("\n")
            }
        }
    }

    Process {
        id: walltuneProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const lines = text.trim().split("\n").filter(l => l.trim())
                    root.walltuneHistory = lines.map(l => JSON.parse(l)).reverse()
                } catch (e) {
                    root.walltuneHistory = []
                }
            }
        }
    }

    // Singleton roots can't use Component.onCompleted — kick the initial
    // load via a one-shot Timer instead.
    Timer {
        interval: 0
        running: true
        repeat: false
        onTriggered: root.refresh()
    }
}
