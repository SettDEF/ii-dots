pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Updates to the shell itself, from the git checkout it runs out of.
 *
 * Pulls are --ff-only and skipped over a dirty tree: this config is meant to be
 * edited by the person running it. A dirty tree still reports; it just waits.
 */
Singleton {
    id: root

    readonly property string dir: `${Quickshell.env("HOME")}/.config/quickshell`
    readonly property var opts: Config.options?.updates?.shell

    /// A git checkout with an upstream branch — otherwise there is nothing to check.
    property bool available: false
    property bool checking: false
    property bool applying: false
    /// Commits the checkout is behind its upstream.
    property int behind: 0
    /// Uncommitted local changes; blocks applying.
    property bool dirty: false
    property string latest: ""
    property string error: ""
    property double lastChecked: 0
    /// "142 · 7b929f8 · 2026-09-27", or "" outside a checkout.
    property string version: ""

    readonly property bool updateAvailable: root.available && root.behind > 0
    readonly property bool canApply: root.updateAvailable && !root.dirty && !root.applying

    signal updateFound(int count, string subject)

    function check() {
        if (!root.available || root.checking || !(root.opts?.enable ?? true)) return;
        root.checking = true;
        root.error = "";
        checkProc.running = true;
    }

    function apply() {
        if (!root.canApply) return;
        root.applying = true;
        applyProc.running = true;
    }

    Process {
        id: versionProc
        running: true
        command: ["bash", "-c",
            `cd '${root.dir}' 2>/dev/null || exit 0
             printf '%s · %s · %s' "$(git rev-list --count HEAD)" \
                 "$(git rev-parse --short HEAD)" "$(git log -1 --format=%cs)"`]
        stdout: StdioCollector { onStreamFinished: root.version = text.trim() }
    }

    Process {
        id: probeProc
        running: true
        command: ["git", "-C", root.dir, "rev-parse", "--abbrev-ref", "@{upstream}"]
        onExited: exitCode => {
            root.available = (exitCode === 0);
            if (root.available) root.check();
        }
    }

    Process {
        id: checkProc
        command: ["bash", "-c",
            `cd '${root.dir}' || exit 1
             git fetch --quiet --no-tags origin 2>/dev/null || exit 2
             behind=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
             dirty=$(git status --porcelain --untracked-files=no | head -c1)
             subject=$(git log -1 --pretty=%s @{u} 2>/dev/null)
             printf '%s\\n%s\\n%s\\n' "$behind" "\${dirty:+1}" "$subject"`]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                const was = root.behind;
                root.behind = parseInt(lines[0]) || 0;
                root.dirty = lines[1]?.trim() === "1";
                root.latest = (lines[2] ?? "").trim();
                root.lastChecked = Date.now();
                // Only on a change, so a six-hourly check does not re-announce
                // the same commit all day.
                if (root.behind > 0 && root.behind !== was)
                    root.updateFound(root.behind, root.latest);
            }
        }
        onExited: exitCode => {
            root.checking = false;
            if (exitCode === 2) root.error = qsTr("Could not reach the remote");
            else if (exitCode !== 0) root.error = qsTr("Update check failed");
        }
    }

    Process {
        id: applyProc
        command: ["bash", "-c", `cd '${root.dir}' && git pull --ff-only --quiet`]
        onExited: exitCode => {
            root.applying = false;
            if (exitCode === 0) {
                root.behind = 0;
                // No reload call here: quickshell watches these files, so the
                // pull is the reload.
                notifyProc.summary = qsTr("Shell updated");
                notifyProc.body = root.latest;
            } else {
                root.error = qsTr("Update failed — pull by hand to see why");
                notifyProc.summary = qsTr("Shell update failed");
                notifyProc.body = root.error;
            }
            if (root.opts?.notify ?? true) notifyProc.running = true;
        }
    }

    Process {
        id: notifyProc
        property string summary: ""
        property string body: ""
        command: ["notify-send", "-a", "Shell", "-i", "system-software-update",
                  notifyProc.summary, notifyProc.body]
    }

    onUpdateFound: (count, subject) => {
        if (root.opts?.autoApply ?? false) {
            if (root.canApply) { root.apply(); return; }
            // Dirty tree: say so rather than silently doing nothing.
            notifyProc.summary = qsTr("Shell update waiting");
            notifyProc.body = qsTr("%1 new commit(s), but you have uncommitted changes.").arg(count);
        } else {
            notifyProc.summary = qsTr("Shell update available");
            notifyProc.body = count === 1 ? subject
                : qsTr("%1 new commits — latest: %2").arg(count).arg(subject);
        }
        if (root.opts?.notify ?? true) notifyProc.running = true;
    }

    Timer {
        running: Config.ready && (root.opts?.enable ?? true) && root.available
        interval: Math.max(1, root.opts?.checkIntervalHours ?? 6) * 3600 * 1000
        repeat: true
        onTriggered: root.check()
    }

    IpcHandler {
        target: "shellUpdate"
        function check(): void { root.check() }
        function apply(): void { root.apply() }
        function status(): string {
            return JSON.stringify({
                available: root.available, behind: root.behind,
                dirty: root.dirty, latest: root.latest, error: root.error
            });
        }
    }
}
