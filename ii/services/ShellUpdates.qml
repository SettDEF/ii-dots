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

    /// The git checkout the install was COPIED FROM. install.sh copies rather
    /// than checking out, so the installed config knows nothing about upstream;
    /// the marker it leaves behind is what points back at the source.
    property string dir: ""
    /// install.sh from that source, re-run to copy an update into place.
    property string installArgs: ""
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

    /// Finds the source checkout, then hands off to the version and upstream
    /// probes. Falls back to the config directory itself, which is the case
    /// when the config IS the repo (a developer, not an install).
    Process {
        id: locateProc
        running: true
        command: ["bash", "-c",
            `marker="\${XDG_DATA_HOME:-$HOME/.local/share}/ii-dots/install-source"
             if [ -r "$marker" ]; then
                 . "$marker"
                 printf '%s\\n%s\\n' "$source" "-n \${name:-ii} -p \${profile:-recommended}"
             else
                 printf '%s\\n\\n' "$HOME/.config/quickshell"
             fi`]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = String(text).split("\n");
                root.dir = (lines[0] ?? "").trim();
                root.installArgs = (lines[1] ?? "").trim();
                if (root.dir.length > 0) {
                    versionProc.running = true;
                    probeProc.running = true;
                }
            }
        }
    }

    Process {
        id: versionProc
        command: ["bash", "-c",
            `cd '${root.dir}' 2>/dev/null || exit 0
             printf '%s · %s · %s' "$(git rev-list --count HEAD)" \
                 "$(git rev-parse --short HEAD)" "$(git log -1 --format=%cs)"`]
        stdout: StdioCollector { onStreamFinished: root.version = text.trim() }
    }

    Process {
        id: probeProc
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
        // Pull, then re-run install.sh: the running config is a copy of this
        // checkout, so a pull alone updates nothing the shell actually loads.
        // Skipped when the config IS the checkout, where the pull is enough.
        command: ["bash", "-c",
            `cd '${root.dir}' && git pull --ff-only --quiet || exit 1
             [ -n '${root.installArgs}' ] || exit 0
             ./install.sh --yes --no-deps ${root.installArgs}`]
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
