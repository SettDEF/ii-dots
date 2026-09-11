pragma Singleton
pragma ComponentBehavior: Bound

// Per-application colours, via `tinct app`.
//
// tinct renders a palette into every app you have from one config.toml. Each
// [templates.*] entry there can also carry its own colours — a mode, a scheme,
// three sliders, and hand-pinned roles — and this is the front end for that.
//
// The config file stays the source of truth: nothing is cached here, every
// read is a `tinct app show --json` and every write is a `tinct app set` that
// edits the TOML in place with your comments intact. That means the panel and
// a text editor can't disagree, and it means uninstalling the panel loses
// nothing.
//
// Writes are debounced and coalesced: dragging a slider queues a value rather
// than spawning a process per frame, and one flush does set → render → show.
// Re-rendering is scoped with `--only <app>`, so moving kitty's hue slider
// doesn't rewrite GTK and signal every other app to reload.

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Absolute path to tinct, resolved once at startup.
    //
    // Not just "tinct": a Wayland session's PATH is whatever the compositor
    // was started with, and Hyprland's is typically /usr/local/bin:/usr/bin
    // with no ~/.local/bin — which is exactly where tinct installs. Spawning
    // a bare name from the shell fails with "binary could not be found" while
    // the same command works fine in every terminal, which is a miserable
    // thing to debug.
    property string bin: ""

    // [{name, output_path, overrides, has_overrides}]
    property var apps: []
    property string selected: ""
    // The parsed `tinct app show` object for `selected`.
    property var detail: ({})
    property bool available: true
    property bool busy: false
    property string error: ""

    // Values typed into sliders that haven't been written yet. The UI reads
    // through these so a drag stays smooth while the file catches up.
    property var pending: ({})

    // The roles worth showing before you ask for all fifty. Enough to see what
    // a change did without scrolling.
    readonly property var keyRoles: [
        "primary", "on_primary", "primary_container", "secondary", "tertiary",
        "surface", "on_surface", "surface_container", "outline", "error"
    ]
    property bool showAllRoles: false

    readonly property var overrides: root.detail?.overrides ?? ({})
    readonly property bool hasOverrides:
        Object.keys(root.overrides?.colors ?? {}).length > 0
        || Object.values(root.overrides?.render ?? {}).some(v => v !== null && v !== undefined)
        || Object.values(root.overrides?.adjust ?? {}).some(v => v !== null && v !== undefined)

    /** Rows for the swatch list: [{role, hex, base, changed, pinned, pin}].
     *
     *  `changed` and `pinned` are different facts and the UI shows them
     *  differently: a slider changes every role, but only a pin says "this
     *  exact colour, whatever else happens". */
    readonly property var colorRows: {
        const cols = root.detail?.colors;
        if (!cols) return [];
        const pins = root.overrides?.colors ?? ({});
        const names = root.showAllRoles ? Object.keys(cols).sort()
                                        : root.keyRoles.filter(r => cols[r] !== undefined);
        return names.map(r => ({
            role: r,
            hex: cols[r].hex,
            base: cols[r].base,
            changed: cols[r].changed === true,
            pinned: pins[r] !== undefined,
            pin: pins[r] ?? ""
        }));
    }

    /** The key roles only, whatever the detailed list happens to be showing.
     *
     *  Feeds the always-visible strip: the swatch table is long enough to sit
     *  below the fold no matter how tall the card is, and adjusting colours
     *  while unable to see any of them is the one thing this panel must not
     *  ask of you. */
    readonly property var keyRows: {
        const cols = root.detail?.colors;
        if (!cols) return [];
        const pins = root.overrides?.colors ?? ({});
        return root.keyRoles
            .filter(r => cols[r] !== undefined)
            .map(r => ({
                role: r,
                hex: cols[r].hex,
                changed: cols[r].changed === true,
                pinned: pins[r] !== undefined
            }));
    }

    /** A setting's current value: what's queued, else what's on disk. */
    function valueOf(section, key, fallback) {
        const p = root.pending[section + "." + key];
        if (p !== undefined) return p;
        const v = root.overrides?.[section]?.[key];
        return (v === null || v === undefined) ? fallback : v;
    }

    /** Sliders are numbers here but text in the file, where an unsigned value
     *  sets and a signed one nudges. These are absolute, so they go unsigned. */
    function numberOf(section, key, fallback) {
        const v = root.valueOf(section, key, undefined);
        if (v === undefined) return fallback;
        const n = Number(String(v).replace(/^\+/, ""));
        return isNaN(n) ? fallback : n;
    }

    function refresh() {
        if (!root.available || root.bin === "") return;
        listProc.running = true;
    }

    Process {
        id: whichProc
        running: true
        // The install location first, then the ones a distro package would
        // use, then whatever PATH happens to offer.
        command: ["sh", "-c",
            "for p in \"$HOME/.local/bin/tinct\" /usr/local/bin/tinct /usr/bin/tinct; do "
            + "[ -x \"$p\" ] && { printf %s \"$p\"; exit 0; }; done; command -v tinct || true"]
        stdout: StdioCollector {
            id: whichOut
            onStreamFinished: {
                root.bin = (whichOut.text || "").trim();
                if (root.bin === "") {
                    root.available = false;
                    root.error = Translation.tr("tinct is not installed");
                    return;
                }
                root.refresh();
                root.load();
            }
        }
    }

    function select(name) {
        if (name === root.selected) return;
        root.selected = name;
        root.pending = ({});
        root.error = "";
        root.load();
    }

    function load() {
        if (!root.selected || !root.available || root.bin === "") return;
        showProc.running = true;
    }

    /** Queue a `section.key = value` write. Repeated calls coalesce. */
    function queue(section, key, value) {
        const next = Object.assign({}, root.pending);
        next[section + "." + key] = value;
        root.pending = next;
        flushTimer.restart();
    }

    /** Write immediately — for switches and dropdowns, where there's no drag
     *  to wait out and the delay would just read as lag. */
    function set(section, key, value) {
        root.queue(section, key, value);
        flushTimer.stop();
        root.flush();
    }

    function clear(section, key) {
        root.set(section, key, "");
    }

    function pin(role, value) {
        root._run([root.bin, "app", "pin", root.selected, role, value]);
    }

    function unpin(role) {
        root._run([root.bin, "app", "unpin", root.selected, role]);
    }

    function resetAll() {
        root.pending = ({});
        root._run([root.bin, "app", "reset", root.selected]);
    }

    function flush() {
        const keys = Object.keys(root.pending);
        if (keys.length === 0 || !root.selected) return;
        const args = [root.bin, "app", "set", root.selected];
        for (const k of keys) args.push(k + "=" + root.pending[k]);
        root.pending = ({});
        root._run(args);
    }

    // set → render → show. Sequential rather than one `bash -c … && …` so the
    // arguments stay a real argv: a pinned colour is user input, and it should
    // never reach a shell.
    function _run(argv) {
        if (!root.selected || !root.available || root.bin === "") return;
        root.busy = true;
        root.error = "";
        writeProc.command = argv;
        writeProc.running = true;
    }

    Timer {
        id: flushTimer
        // Long enough to swallow a drag, short enough that letting go feels
        // immediate. tinct renders in about a millisecond; this is the only
        // part with any latency in it.
        interval: 160
        onTriggered: root.flush()
    }

    Process {
        id: listProc
        command: [root.bin, "app", "list", "--json"]
        stdout: StdioCollector {
            id: listOut
            onStreamFinished: {
                try {
                    root.apps = JSON.parse(listOut.text || "[]");
                } catch (e) {
                    root.apps = [];
                }
                // Land on something rather than an empty panel.
                if (!root.selected && root.apps.length > 0) root.select(root.apps[0].name);
            }
        }
        stderr: StdioCollector {
            id: listErr
            onStreamFinished: {
                const t = (listErr.text || "").trim();
                if (t.length > 0) root.error = t;
            }
        }
        onExited: exitCode => {
            if (exitCode === 0) return;
            // Two ways this fails before anything useful can happen, and both
            // want a sentence rather than the raw stderr: 127 is no tinct on
            // PATH at all, and clap's exit 2 here means a tinct that predates
            // `app`. Stop retrying either way — every open would repeat it.
            root.available = false;
            root.error = exitCode === 127
                ? Translation.tr("tinct is not installed")
                : Translation.tr("This tinct has no `app` command — install a newer build");
        }
    }

    Process {
        id: showProc
        command: [root.bin, "app", "show", root.selected, "--json"]
        stdout: StdioCollector {
            id: showOut
            onStreamFinished: {
                try {
                    root.detail = JSON.parse(showOut.text || "{}");
                } catch (e) {
                    root.detail = ({});
                }
            }
        }
        stderr: StdioCollector {
            id: showErr
            onStreamFinished: {
                const t = (showErr.text || "").trim();
                if (t.length > 0) root.error = t;
            }
        }
    }

    Process {
        id: writeProc
        stderr: StdioCollector {
            id: writeErr
            onStreamFinished: {
                const t = (writeErr.text || "").trim();
                // tinct writes refusals ("unknown scheme `vibrnat`") here and
                // changes nothing, so showing it verbatim is the whole report.
                if (t.length > 0) root.error = t.replace(/^Error:\s*/, "");
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.busy = false;
                root.load();       // resync: the file is unchanged
                return;
            }
            renderProc.running = true;
        }
    }

    Process {
        id: renderProc
        // Only this app: a slider on kitty shouldn't rewrite GTK and fire
        // every other post_hook on the machine.
        command: [root.bin, "render", "--only", root.selected, "--no-cmus"]
        onExited: {
            root.busy = false;
            root.load();
            listProc.running = true;   // the * marker in the list may have moved
        }
    }

    /** Called by the panel when it opens. Deliberately not a Connections on
     *  GlobalStates: that lives in `qs`, which imports `qs.services`, and a
     *  service reaching back for it would close the import loop. */
    function reload() {
        root.refresh();
        root.load();
    }
}
