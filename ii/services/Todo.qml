pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * The shell's to-do list, backed by Dotos — so the sidebar, the desktop
 * widget, the clock popup, the bar and the Dotos window are one list, not
 * two. Reads `dotos snapshot --no-git` (a few ms), stays fresh through
 * inotify on the store, and every change goes through the `dotos` CLI.
 *
 * `list` keeps the old item shape ({ title, content, done }) plus the Dotos
 * fields, so the existing widgets work unchanged; their index-based calls
 * are mapped to the task's uid here.
 *
 * The old JSON list (Directories.todoPath) is moved into Dotos once, then
 * renamed to todo.json.migrated.
 */
Singleton {
    id: root
    readonly property string bin: Quickshell.env("HOME") + "/.local/bin/dotos"
    property var snap: null
    property bool loaded: false
    property string error: ""

    /// open tasks (most urgent first), then what was finished this week
    property var list: []
    readonly property var open: root.list.filter(t => !t.done)
    readonly property int overdue: root.open.filter(t => t.overdue).length
    readonly property int dueToday: root.open.filter(t => t.bucket === "today").length
    readonly property var doing: root.open.filter(t => t.state === "doing")
    /// the one thing to show when there is room for one: doing, overdue, today, then the rest
    readonly property var next: root.open.length > 0 ? root.open[0] : null
    /// timewarrior: { uid, title, since } while a task is tracked
    readonly property var active: root.snap?.time?.active ?? null

    /// the list a task is shown under: doing, overdue, then its bucket
    function group(t) { return t.done ? "done" : t.state === "doing" ? "doing" : t.overdue ? "overdue" : (t.bucket || "inbox"); }
    function groupLabel(g) {
        return ({ doing: Translation.tr("Doing"), overdue: Translation.tr("Overdue"), today: Translation.tr("Today"),
                  tomorrow: Translation.tr("Tomorrow"), week: Translation.tr("This week"), later: Translation.tr("Later"),
                  someday: Translation.tr("Someday"), inbox: Translation.tr("Inbox"), done: Translation.tr("Done this week") })[g] ?? g;
    }
    /// "today 14:00", "tomorrow", "Fri", "3 days late", "12 Nov" — the same words as Dotos
    function dueLabel(t) {
        if (!t?.due) return "";
        const d = new Date(t.due);
        const now = new Date();
        const days = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(now.getFullYear(), now.getMonth(), now.getDate())) / 86400000);
        const time = t.due_time ? " " + Qt.formatDateTime(d, "HH:mm") : "";
        if (days === 0) return Translation.tr("today") + time;
        if (days === 1) return Translation.tr("tomorrow") + time;
        if (days === -1) return Translation.tr("yesterday");
        if (days < 0) return Translation.tr("%1 days late").arg(-days);
        if (days < 7) return Qt.formatDateTime(d, "ddd") + time;
        return Qt.formatDateTime(d, "d MMM") + time;
    }

    /// a project's colour: the same hash-on-the-accent-hue as Dotos, so +knurl
    /// is the same colour in the sidebar and in the window
    function colorOf(name) {
        const key = String(name ?? "");
        if (!key) return Appearance.colors.colSubtext;
        let h = 0;
        for (let i = 0; i < key.length; i++) h = (h * 31 + key.charCodeAt(i)) >>> 0;
        const p = Appearance.colors.colPrimary;
        const base = p.hslHue < 0 ? 0.8 : p.hslHue;
        return Qt.hsla((base + (h % 12) * 0.083) % 1, Math.max(0.45, p.hslSaturation), Math.min(0.78, Math.max(0.62, p.hslLightness)), 1);
    }

    readonly property var _rank: ({ doing: 0, overdue: 1, today: 2, tomorrow: 3, week: 4, later: 5, someday: 6, inbox: 7 })
    function _sort(a, b) {
        const ra = a.state === "doing" ? 0 : (a.overdue ? 1 : (root._rank[a.bucket] ?? 6));
        const rb = b.state === "doing" ? 0 : (b.overdue ? 1 : (root._rank[b.bucket] ?? 6));
        if (ra !== rb) return ra - rb;
        const pa = a.priority === "high" ? 0 : a.priority === "low" ? 2 : 1;
        const pb = b.priority === "high" ? 0 : b.priority === "low" ? 2 : 1;
        if (pa !== pb) return pa - pb;
        return String(a.due ?? "9999").localeCompare(String(b.due ?? "9999")) || String(a.created).localeCompare(String(b.created));
    }
    function _apply(s) {
        const weekAgo = new Date(Date.now() - 7 * 86400000).toISOString().slice(0, 10);
        const all = (s.tasks ?? []).filter(t => !t.parent && t.state !== "cancelled");
        const open = all.filter(t => t.state !== "done").sort(root._sort);
        const done = all.filter(t => t.state === "done" && String(t.completed ?? "") >= weekAgo)
            .sort((a, b) => String(b.completed).localeCompare(String(a.completed)));
        root.list = open.concat(done).map(t => Object.assign({}, t, { content: t.notes, done: t.state === "done" }));
        root.snap = s;
        root.loaded = true;
        root.error = "";
        // here, not in onExited: the process can exit before its output is parsed
        if (!watcher.running) watcher.running = true;
        if (!root._migrated) root._migrate();
    }

    function _run(args, after) {
        const p = runner.createObject(root, { command: [root.bin].concat(args) });
        p.after = after ?? null;
        p.running = true;
    }
    Component {
        id: runner
        Process {
            id: proc
            property var after: null
            stderr: StdioCollector { id: err }
            onExited: code => {
                if (code !== 0) root.error = err.text.trim() || ("dotos exited " + code);
                if (proc.after) proc.after(code);
                root.reload();
                proc.destroy();
            }
        }
    }
    function _uid(index) { return root.list[index]?.uid ?? ""; }
    function _patch(index, fields) {
        if (index < 0 || index >= root.list.length) return;
        const next = root.list.slice(0);
        next[index] = Object.assign({}, next[index], fields);
        root.list = next;
    }

    // ── the old API, kept for the widgets ──
    function addItem(item) { root.addTask(item.title ?? item.content ?? "", item.title ? item.content : ""); }
    /// title takes the capture syntax: "call mum @fri 18:00 !high #family ~15m"
    function addTask(title, desc) {
        if (!String(title).trim()) return;
        root.capture(title, desc);
    }
    function markDone(index) { const u = root._uid(index); if (!u) return; root._patch(index, { done: true, state: "done" }); root._run(["done", u]); }
    function markUnfinished(index) { const u = root._uid(index); if (!u) return; root._patch(index, { done: false, state: "todo" }); root._run(["undone", u]); }
    function deleteItem(index) {
        const u = root._uid(index);
        if (!u) return;
        const next = root.list.slice(0);
        next.splice(index, 1);
        root.list = next;
        root._run(["rm", u]);
    }
    function refresh() { root.reload(); }

    // ── Dotos verbs ──
    function capture(line, note, after) {
        const args = ["capture", String(line).trim()];
        if (note && String(note).trim()) args.push("--note", String(note).trim());
        root._run(args, after);
    }
    function setState(uid, state) { root._run(["state", uid, state]); }
    function track(uid) { root._run(["track", uid]); }
    function stop() { root._run(["stop"]); }
    function undo() { root._run(["undo"]); }
    /// the Dotos window, optionally on a page (home, inbox, tasks, board, …)
    function openApp(page) { Quickshell.execDetached(["dotos-gui"].concat(page ? [page] : [])); }

    // ── reading ──
    property bool _again: false
    function reload() {
        if (snapProc.running) { root._again = true; return; }
        snapProc.running = true;
    }
    Process {
        id: snapProc
        command: [root.bin, "snapshot", "--no-git"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root._apply(JSON.parse(text)); }
                catch (e) { root.error = "dotos snapshot: " + e; }
            }
        }
        onExited: code => {
            if (code !== 0 && !root.loaded) root.error = "dotos is not installed or failed (" + code + ")";
            if (root._again) { root._again = false; root.reload(); }
        }
    }
    // changes from the window, the terminal, Neovim, extensions, phone sync
    Process {
        id: watcher
        command: ["sh", "-c", 'mkdir -p "$1" && exec setpriv --pdeathsig TERM inotifywait -m -q -e close_write,moved_to,delete --format %f "$1" 2>/dev/null',
            "watch", root.snap?.store ?? (Quickshell.env("HOME") + "/.local/share/dotos/lists")]
        stdout: SplitParser {
            onRead: line => { if (!/\.tmp~?$|~$/.test(line)) debounce.restart(); }
        }
        onExited: restartWatch.start()
    }
    Timer { id: debounce; interval: 150; onTriggered: root.reload() }
    Timer { id: restartWatch; interval: 5000; onTriggered: watcher.running = true }
    // buckets move at midnight, the timer counts up
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.reload() }

    // ── one-time move of the old JSON list ──
    property bool _migrated: false
    function _migrate() {
        root._migrated = true;
        legacy.running = true;
    }
    Process {
        id: legacy
        command: ["cat", Directories.todoPath]
        stdout: StdioCollector {
            onStreamFinished: {
                let items = [];
                try { items = JSON.parse(text); } catch (e) { return; }
                if (!Array.isArray(items) || items.length === 0) return;
                // finished items stay behind in the .migrated file
                for (const it of items.filter(i => !i.done)) {
                    const title = String(it.title || it.content || "").trim();
                    if (title) root.capture(title, it.title ? String(it.content ?? "") : "");
                }
                Quickshell.execDetached(["mv", "-n", Directories.todoPath, Directories.todoPath + ".migrated"]);
                console.log("[To Do] moved", items.length, "items into Dotos");
            }
        }
    }

    Component.onCompleted: root.reload()
}
