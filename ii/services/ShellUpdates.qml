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
    /// Upstream's head, and the one last announced (kept on disk: the in-memory "changed since the
    /// last check" was lost on every restart, and each one stacked another notification)
    property string upstream: ""
    property string announced: ""
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quickshell/user"
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
             upstream=$(git rev-parse @{u} 2>/dev/null)
             announced=$(cat '${root.stateDir}/shell-update.announced' 2>/dev/null)
             printf '%s\\n%s\\n%s\\n%s\\n%s\\n' "$behind" "\${dirty:+1}" "$subject" "$upstream" "$announced"`]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                root.behind = parseInt(lines[0]) || 0;
                root.dirty = lines[1]?.trim() === "1";
                root.latest = (lines[2] ?? "").trim();
                root.upstream = (lines[3] ?? "").trim();
                root.announced = (lines[4] ?? "").trim();
                root.lastChecked = Date.now();
                // Only for an upstream head not announced before, across restarts too
                if (root.behind > 0 && root.upstream !== "" && root.upstream !== root.announced)
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
                notifyProc.offerUpdate = false;
                notifyProc.record = "";
            } else {
                root.error = qsTr("Update failed — pull by hand to see why");
                notifyProc.summary = qsTr("Shell update failed");
                notifyProc.body = root.error;
                notifyProc.offerUpdate = false;
                notifyProc.record = "";
            }
            if (root.opts?.notify ?? true) notifyProc.running = true;
        }
    }

    // One notification for the whole story: each one replaces the last (its id is kept on disk),
    // so new commits, "updated" and "failed" do not pile up. "Update" on it applies. Its icon is a
    // file of the shell's: system-software-update is not in every icon theme (Reversal: a
    // missing-icon checkerboard).
    Process {
        id: notifyProc
        property string summary: ""
        property string body: ""
        property bool offerUpdate: false
        /// the upstream head this one announces, recorded so it is not announced again
        property string record: ""
        command: ["bash", "-c",
            `d="$1"; mkdir -p "$d"; id=$(cat "$d/shell-update.notify-id" 2>/dev/null)
             [ -n "$4" ] && printf '%s' "$4" > "$d/shell-update.announced"
             args=(-a Shell -i '${Directories.assetsPath}/icons/shell-update.svg' -p)
             [ -n "$id" ] && args+=(-r "$id")
             [ "$5" = 1 ] && args+=(-A update="Update")
             notify-send "\${args[@]}" "$2" "$3" | { read -r nid && printf '%s' "$nid" > "$d/shell-update.notify-id"; cat; }`,
            "_", root.stateDir, notifyProc.summary, notifyProc.body,
            notifyProc.record, notifyProc.offerUpdate ? "1" : "0"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "update") root.apply();
            }
        }
    }

    onUpdateFound: (count, subject) => {
        notifyProc.record = root.upstream;
        if (root.opts?.autoApply ?? false) {
            if (root.canApply) { root.apply(); return; }
            // Dirty tree: say so rather than silently doing nothing.
            notifyProc.summary = qsTr("Shell update waiting");
            notifyProc.body = qsTr("%1 new commit(s), but you have uncommitted changes.").arg(count);
            notifyProc.offerUpdate = false;
        } else {
            // the count in the title, the latest change in the body: the body was cut off at "lates…"
            notifyProc.summary = count === 1 ? qsTr("Shell update available")
                : qsTr("Shell update: %1 new commits").arg(count);
            notifyProc.body = subject;
            notifyProc.offerUpdate = root.canApply;
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
