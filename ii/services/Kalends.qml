pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Events from kalends, the desktop's calendar store.
 *
 * Shells out to the CLI rather than reading the .ics files directly: the CLI
 * is the one place that knows the format, and the house rule is that the UI
 * and the terminal go through the same door.
 */
Singleton {
    id: root

    /// false once the binary is known to be missing — the calendar then just
    /// renders without events instead of erroring on every month change.
    property bool available: true
    property string lastError: ""
    property var events: []
    /// "YYYY-MM-DD" -> [event]. Built once per load, so a day cell is a lookup.
    property var byDay: ({})

    property string rangeFrom: ""
    property string rangeTo: ""

    /// Resolved once. quickshell inherits the compositor's PATH, which does
    /// not include ~/.local/bin, so a bare "kalends" fails to start.
    property string binary: ""
    property var pendingRange: null

    // ── Noticing a sync ─────────────────────────────────────────────────
    // The sync timer pulls events in every 5 minutes behind the shell's back.
    // Without this the calendar showed whatever was there when the month was
    // last drawn, so a synced event simply never appeared.
    //
    // Watching the bounds index rather than polling the CLI: it is one file,
    // the kernel reports the change, and the CLI rewrites it only when the
    // store actually changed — so a plain `kalends list` cannot make this
    // loop back on itself.
    FileView {
        path: `${Quickshell.env("HOME")}/.local/share/kalends/.index.json`
        watchChanges: true
        onFileChanged: root.reload()
    }


    // ── Next event ──────────────────────────────────────────────────────
    // Fetched on demand rather than polled. The bar's clock popup is the only
    // caller and it is built on hover, so asking then costs nothing while the
    // popup is closed — which is almost always.
    property var nextEvent: null

    function refreshNext() {
        if (!root.available || root.binary.length === 0) return;
        nextProc.command = [root.binary, "next", "--json"];
        nextProc.running = false;
        nextProc.running = true;
    }

    /// "in 25 min", "in 3 h", "tomorrow 09:00" — relative while that is
    /// useful, absolute once it is not.
    function nextLabel() {
        const e = root.nextEvent;
        if (!e?.start) return "";
        const start = new Date(e.start);
        if (isNaN(start.getTime())) return "";
        const mins = Math.round((start - new Date()) / 60000);
        if (e.all_day) return Qt.formatDateTime(start, "ddd d MMM");
        if (mins < 0) return Translation.tr("now");
        if (mins < 60) return Translation.tr("in %1 min").arg(mins);
        if (mins < 60 * 12) return Translation.tr("in %1 h").arg(Math.round(mins / 60));
        return Qt.formatDateTime(start, "ddd HH:mm");
    }

    Process {
        id: nextProc
        running: false
        stdout: StdioCollector {
            id: nextOut
            onStreamFinished: {
                const t = String(nextOut.text ?? "").trim();
                if (t.length === 0 || t === "null") { root.nextEvent = null; return; }
                try { root.nextEvent = JSON.parse(t); }
                catch (e) { root.nextEvent = null; }
            }
        }
    }
    Process {
        id: resolver
        running: true
        command: ["sh", "-c",
            "command -v kalends || command -v \"$HOME/.local/bin/kalends\" || true"]
        stdout: StdioCollector {
            id: resolved
            onStreamFinished: {
                root.binary = String(resolved.text ?? "").trim();
                if (root.binary.length === 0) {
                    root.available = false;
                    root.lastError = "kalends is not installed";
                    return;
                }
                if (root.pendingRange) {
                    const p = root.pendingRange;
                    root.pendingRange = null;
                    root.loadRange(p.from, p.to, true);
                }
            }
        }
    }

    function iso(d) {
        if (!d) return "";
        if (typeof d === "string") return d;   // already YYYY-MM-DD from the grid
        const p = n => String(n).padStart(2, "0");
        return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
    }

    function eventsOn(isoDate) { return root.byDay[isoDate] ?? []; }
    function countOn(isoDate) { return (root.byDay[isoDate] ?? []).length; }

    /// Loads [from, to] inclusive. A repeat call for the same range is ignored,
    /// so scrolling back to a month already shown costs nothing.
    function loadRange(from, to, force) {
        if (!root.available) return;
        const f = root.iso(from), t = root.iso(to);
        if (!force && f === root.rangeFrom && t === root.rangeTo) return;
        root.rangeFrom = f;
        root.rangeTo = t;
        if (root.binary.length === 0) { root.pendingRange = ({ from: f, to: t }); return; }
        proc.command = [root.binary, "list", "--from", f, "--to", t, "--json"];
        proc.running = false;
        proc.running = true;
    }

    function reload() { root.loadRange(root.rangeFrom, root.rangeTo, true); }

    function _index(list) {
        const map = ({});
        for (const ev of list) {
            if (!ev?.start) continue;
            const start = new Date(ev.start);
            const end = new Date(ev.end ?? ev.start);
            if (isNaN(start.getTime())) continue;
            // An all-day DTEND is exclusive per RFC 5545, so a 1st-to-4th trip
            // covers the 1st, 2nd and 3rd. A timed event's last day counts.
            let last = new Date(end.getTime());
            if (ev.all_day) last.setDate(last.getDate() - 1);
            if (last < start) last = new Date(start.getTime());

            let cur = new Date(start.getFullYear(), start.getMonth(), start.getDate());
            const stop = new Date(last.getFullYear(), last.getMonth(), last.getDate());
            let guard = 0;
            while (cur <= stop && guard++ < 400) {   // guard: a bad DTEND can't hang the shell
                const key = root.iso(cur);
                (map[key] = map[key] ?? []).push(ev);
                cur.setDate(cur.getDate() + 1);
            }
        }
        for (const k in map)
            map[k].sort((a, b) => (a.all_day === b.all_day)
                ? String(a.start).localeCompare(String(b.start))
                : (a.all_day ? -1 : 1));
        return map;
    }

    Process {
        id: proc
        running: false
        stdout: StdioCollector {
            id: out
            onStreamFinished: {
                const text = String(out.text ?? "").trim();
                if (text.length === 0) { root.events = []; root.byDay = ({}); return; }
                try {
                    const list = JSON.parse(text) ?? [];
                    root.events = list;
                    root.byDay = root._index(list);
                    root.lastError = "";
                } catch (e) {
                    root.lastError = "unreadable output";
                    root.events = [];
                    root.byDay = ({});
                }
            }
        }
        onExited: (code, status) => {
            // 127 / launch failure means no binary; stop trying every month.
            if (code === 127) {
                root.available = false;
                root.lastError = "kalends is not installed";
            }
        }
    }
}
