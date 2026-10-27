pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Which AI chats are working, waiting for you, or finished.
 *
 * Claude Code reports each session's state through hooks
 * (scripts/ai-activity: one JSON file per session in
 * $XDG_RUNTIME_DIR/ai-activity, written by a hook that prints nothing, so it
 * costs no tokens). This service watches that folder with inotify and keeps
 * the list; the bar chip, notifications and Dotos' Agents space read it.
 *
 * Other sources (the ii AI sidebar, ComfyUI, …) become more files in the
 * same folder, written by their own adapters — the service does not care who
 * wrote a file, only what state it says.
 */
Singleton {
    id: root

    readonly property string bin: Quickshell.shellPath("scripts/ai-activity/ai-activity").replace(/^file:\/\//, "")
    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ai-activity"

    /// Every session the hooks know, newest first.
    property var sessions: []
    /// Finished sessions you have looked at (id → their `updated` then), so a
    /// "done" stops counting once seen, until the session does something new.
    property var seen: ({})

    readonly property var live: root.sessions.filter(s => s.state !== "ended")
    readonly property var needsYou: root.live.filter(s => s.state === "needs_you")
    readonly property var working: root.live.filter(s => s.state === "working")
    readonly property var finished: root.live.filter(s => s.state === "finished" && root.seen[s.id] !== s.updated)
    readonly property int count: root.live.length

    /// A prompt or message as words: tool markup (<task-notification>…) removed.
    /// Everything that shows a chat's text goes through this.
    function clean(t) {
        return String(t ?? "").replace(/<([a-z-]+)>[^<]*<\/\1>/g, " ").replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
    }

    /// Notify when a chat finishes or needs you. Quiet while a game runs.
    property bool notifyFinished: true
    property bool notifyNeedsYou: true

    property var _prev: ({})
    property bool _primed: false

    function stateIcon(s) {
        return s.state === "needs_you" ? "pending"
             : s.state === "working" ? "progress_activity"
             : s.state === "finished" ? "task_alt"
             : s.state === "ready" ? "radio_button_unchecked"
             : "stop_circle";
    }
    function stateLabel(s) {
        return s.state === "needs_you" ? Translation.tr("needs you")
             : s.state === "working" ? Translation.tr("working")
             : s.state === "finished" ? Translation.tr("finished")
             : s.state === "ready" ? Translation.tr("ready")
             : Translation.tr("ended");
    }
    function elapsed(s) {
        const from = s.state === "working" ? (s.turn_started ?? s.started) : s.updated;
        const d = Math.max(0, Math.floor(Date.now() / 1000) - (from ?? 0));
        return d < 60 ? `${d}s` : d < 3600 ? `${Math.floor(d / 60)} min` : `${Math.floor(d / 3600)} h ${Math.floor(d % 3600 / 60)} m`;
    }

    function markSeen(s) {
        const n = Object.assign({}, root.seen);
        n[s.id] = s.updated;
        root.seen = n;
    }
    function markAllSeen() {
        const n = Object.assign({}, root.seen);
        for (const s of root.finished) n[s.id] = s.updated;
        root.seen = n;
    }

    /// Bring the chat's terminal to the front: the tmux pane, then WezTerm.
    function jump(s) {
        if (!s) return;
        root.markSeen(s);
        const sock = String(s.tmux ?? "").split(",")[0];
        const pane = String(s.tmux_pane ?? "");
        let cmd = "";
        if (sock && pane)
            cmd += `tmux -S '${sock}' switch-client -t '${pane}' 2>/dev/null; tmux -S '${sock}' select-window -t '${pane}' 2>/dev/null; tmux -S '${sock}' select-pane -t '${pane}' 2>/dev/null; `;
        if (s.wezterm_pane)
            cmd += `wezterm cli activate-pane --pane-id '${s.wezterm_pane}' 2>/dev/null; `;
        cmd += "hyprctl dispatch 'hl.dsp.focus({ window = \"class:^(zash|org.wezfurlong.wezterm)$\" })' >/dev/null 2>&1";
        Quickshell.execDetached(["sh", "-c", cmd]);
    }

    /// The most urgent chat: one that needs you, else the latest finished.
    readonly property var urgent: root.needsYou[0] ?? root.finished[0] ?? null

    function notify(s, title, body, urgency) {
        if (GameMode.active) return;
        // not for the chat you are looking at: the terminal (zash or WezTerm) focused AND its tmux
        // pane is the active one
        const sock = String(s.tmux ?? "").split(",")[0];
        const pane = String(s.tmux_pane ?? "");
        const looking = sock && pane
            ? `hyprctl activewindow -j 2>/dev/null | grep -o '"class": *"[^"]*"' | cut -d'"' -f4 | grep -qxE 'zash|org.wezfurlong.wezterm' && [ "$(tmux -S '${sock}' display -p -t '${pane}' '#{window_active}#{pane_active}' 2>/dev/null)" = 11 ]`
            : "false";
        notifyProc.command = ["sh", "-c", `${looking} && exit 0; notify-send -a "AI activity" -i dialog-information -u ${urgency} "$1" "$2"`, "notify", title, body];
        notifyProc.running = false;
        notifyProc.running = true;
    }

    function apply(list) {
        const prev = root._prev, next = ({});
        for (const s of list) {
            next[s.id] = s.state;
            if (!root._primed || prev[s.id] === s.state) continue;
            const who = (s.source === "claude-code" ? "Claude" : s.source) + " · " + (s.project ?? "");
            if (s.state === "needs_you" && root.notifyNeedsYou)
                root.notify(s, Translation.tr("%1 needs you").arg(who), root.clean(s.message), "normal");
            else if (s.state === "finished" && prev[s.id] === "working" && root.notifyFinished)
                root.notify(s, Translation.tr("%1 finished").arg(who), root.clean(s.prompt), "low");
        }
        root._prev = next;
        root._primed = true;
        root.sessions = list;
    }

    Process { id: notifyProc }

    Process {
        id: lister
        command: [root.bin, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const v = JSON.parse(text);
                    if (Array.isArray(v)) root.apply(v);
                } catch (e) {}
            }
        }
    }
    // several hook events arrive in a burst per tool call: read once after
    Timer { id: debounce; interval: 150; onTriggered: { lister.running = false; lister.running = true; } }

    Process {
        id: watcher
        running: true
        command: ["sh", "-c", `mkdir -p '${root.dir}' && exec setpriv --pdeathsig TERM inotifywait -m -q -e moved_to,create,delete --format %f '${root.dir}'`]
        stdout: SplitParser { onRead: _ => debounce.restart() }
        onExited: restartWatcher.start()
    }
    Timer { id: restartWatcher; interval: 5000; onTriggered: watcher.running = true }

    // elapsed times, and sessions whose process died without a hook
    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: debounce.restart() }
    Timer {
        interval: 3600 * 1000; running: true; repeat: true
        onTriggered: Quickshell.execDetached([root.bin, "prune"])
    }
}
