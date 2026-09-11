pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Fires whenever the clipboard changes.
 *
 * One long-lived `wl-paste --watch`, which is event-driven through the Wayland
 * data-control protocol — no polling, no timer. It also means KDE Connect works
 * for free: the clipboard plugin writes into the same Wayland clipboard, so a
 * push from a phone is indistinguishable from a local copy at this level.
 *
 * `wl-paste --watch CMD` pipes the new contents to CMD's stdin, so the preview
 * is built in-process rather than by shelling out a second time.
 */
Singleton {
    id: root

    property string preview: ""
    property bool isImage: false
    property string mime: ""
    /** Written only for image copies, so a thumbnail can be shown. */
    property string imagePath: ""
    /** Set when the copied text is a single URL — enables the "Open" action. */
    property string url: ""
    /** Bumped on every change — bind to this to trigger UI. */
    property int revision: 0

    // wl-paste fires once for whatever is already on the clipboard when it
    // starts. Without this the shell would flash a toast every time it reloads.
    property bool _armed: false
    Timer {
        running: true
        interval: 1500
        onTriggered: root._armed = true
    }

    Process {
        running: true
        command: ["wl-paste", "--watch", "bash", "-c",
            't=$(wl-paste --list-types 2>/dev/null | head -1); ' +
            'case "$t" in ' +
            // Images are written once to a fixed path so the thumbnail can be
            // shown without holding the bytes in QML. Fixed name, not a temp
            // file per copy, so this never accumulates.
            '  image/*) d="${XDG_RUNTIME_DIR:-/tmp}/quickshell-clip"; mkdir -p "$d"; ' +
            '           cat > "$d/last.img"; printf "IMG\\t%s\\t%s\\n" "$t" "$d/last.img" ;; ' +
            // Collapse newlines so one copy is always exactly one line out.
            '  *) printf "TXT\\t%s\\n" "$(head -c 200 | tr "\\r\\n" "  " | tr -s " ")" ;; ' +
            'esac']
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (!root._armed) return;
                const parts = line.split("\t");
                if (parts.length < 2) return;
                root.isImage = (parts[0] === "IMG");
                if (root.isImage) {
                    root.mime = parts[1];
                    // Cache-bust: the path never changes, so without this Qt
                    // would keep showing the first image it ever loaded.
                    root.imagePath = (parts[2] ?? "") + "?v=" + (root.revision + 1);
                    root.preview = "";
                    root.url = "";
                } else {
                    root.mime = "text/plain";
                    root.imagePath = "";
                    root.preview = parts[1].trim();
                    // Empty copies (a cleared selection) are not worth a toast.
                    if (root.preview.length === 0) return;
                    const m = root.preview.match(/^\s*(https?:\/\/\S+)\s*$/);
                    root.url = m ? m[1] : "";
                }
                root.revision++;
            }
        }
    }
}
