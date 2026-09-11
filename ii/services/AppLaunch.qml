pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

/**
 * Launches apps via Hyprland's exec dispatcher so their windows land on the
 * workspace they were launched from.
 *
 * misc:initial_workspace_tracking can't do this: single-shot is spent by an
 * app's splash, persistent never expires and drags VST plugin windows too. So
 * windows are claimed for claimWindowMs after a launch, then never again.
 */
Singleton {
    id: root

    /// Claim window. Long enough for a splash → main handoff, short enough
    /// that windows you open by hand later are never moved.
    property int claimWindowMs: 25000

    /// Pending launches: { ws: int, at: ms, cls: string }.
    property var pending: []

    function shQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    /// Quote for embedding in the Lua expression sent to Hyprland's dispatcher.
    function luaQuote(s) {
        return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
    }

    /// Loose class match: Hyprland's reported class and the desktop entry's
    /// StartupWMClass/id often differ by a suffix (Bitwig reports
    /// "com.bitwig.BitwigStudi" for entry id "com.bitwig.BitwigStudio"), so
    /// accept either being a prefix of the other rather than demanding equality.
    function classMatches(a, b) {
        if (!a || !b)
            return false;
        const x = String(a).toLowerCase();
        const y = String(b).toLowerCase();
        return x.startsWith(y) || y.startsWith(x);
    }

    function prune() {
        const now = Date.now();
        root.pending = root.pending.filter(p => (now - p.at) < root.claimWindowMs);
    }

    /// Record where a launch happened so windows from it can be claimed.
    function remember(entry) {
        const ws = HyprlandData.activeWorkspace?.id ?? -1;
        if (ws < 0)
            return;
        root.prune();
        const cls = String(entry?.startupClass ?? "") || String(entry?.id ?? "");
        // A claim with no class can never match a window, and recording one
        // used to be actively harmful: it was what armed the untargeted
        // fallback in the openwindow handler. The exec dispatcher in launch()
        // already places this app's first window via its `workspace` rule, so
        // nothing is lost by not queueing a claim we cannot check.
        if (cls.length === 0)
            return;
        root.pending = root.pending.concat([
            {
                ws: ws,
                at: Date.now(),
                cls: cls
            }
        ]);
    }

    /**
     * Launch a DesktopEntry through Hyprland.
     *
     * Falls back to entry.execute() for terminal entries: reimplementing
     * TryExec/terminal selection risks the app not starting at all.
     */
    function launch(entry) {
        if (!entry)
            return;
        // Count the launch here rather than in the launcher, so starts from the
        // dock, taskbar and start menu feed the same ranking. recordLaunch()
        // ignores empty ids — this function is also handed desktop-ACTION
        // objects (SearchItem.qml's action buttons), whose id is "".
        LauncherRanking.recordLaunch(entry.id ?? "");
        const argv = (entry.command ?? []).filter(a => a !== undefined && a !== null);
        if (entry.runInTerminal || argv.length === 0) {
            entry.execute();
            return;
        }
        // Strip any Exec field codes the parser left behind (%u %U %f %F %i %c
        // %k); passing them through hands the app a literal "%U".
        const cleaned = argv.map(a => String(a)).filter(a => !/^%[a-zA-Z]$/.test(a));
        if (cleaned.length === 0) {
            entry.execute();
            return;
        }
        const cwd = String(entry.workingDirectory ?? "");
        const cmd = (cwd.length > 0 ? `cd ${root.shQuote(cwd)} && ` : "") + cleaned.map(root.shQuote).join(" ");
        const ws = HyprlandData.activeWorkspace?.id ?? -1;
        root.remember(entry);
        if (ws < 0) {
            HyprDispatch.run(`exec ${cmd}`);
            return;
        }
        // The rule is applied at map time, so the window is never drawn on the
        // workspace you switched to. It is single-shot, so the openwindow
        // claimer below still covers an app's later windows.
        Hyprland.dispatch(`hl.dsp.exec_cmd(${root.luaQuote(cmd)}, { workspace = "${ws} silent" })`);
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name !== "openwindow")
                return;
            if (root.pending.length === 0)
                return;
            root.prune();
            // openwindow payload: ADDRESS,WORKSPACENAME,CLASS,TITLE — the title
            // may itself contain commas, so never split past index 2.
            const data = String(event.data ?? "");
            const parts = data.split(",");
            if (parts.length < 3)
                return;
            const address = parts[0];
            const wsName = parts[1];
            const cls = parts[2];
            const openedWs = parseInt(wsName);
            // Named/special workspaces have no numeric id to compare against.
            if (isNaN(openedWs))
                return;

            // Prefer a launch whose class matches; otherwise the most recent
            // launch still inside its claim window. Searching newest-first
            // keeps rapid successive launches attributed in the right order.
            let claim = null;
            for (let i = root.pending.length - 1; i >= 0; --i) {
                if (root.classMatches(cls, root.pending[i].cls)) {
                    claim = root.pending[i];
                    break;
                }
            }
            // No untargeted fallback. This used to claim the most recent
            // launch whenever THAT launch had no class to match on, which is
            // not a weaker version of matching — it is no matching at all:
            // the first window to open in the next 25s got dragged off,
            // whoever opened it. A terminal-launched app would be yanked to
            // the workspace of some unrelated launcher click. An unclaimed
            // window is left exactly where it opened, which is the right
            // answer whenever we cannot prove where it came from.
            if (!claim || claim.ws === openedWs)
                return;

            console.log("[AppLaunch] claiming", cls, address, "→ ws" + claim.ws, "(opened on ws" + openedWs + ")");
            // Direct dispatch: HyprDispatch maps single-argument verbs, this
            // needs a window selector too. The event address has no 0x prefix.
            Hyprland.dispatch(`hl.dsp.window.move({ window = "address:0x${address}", workspace = ${claim.ws}, follow = false })`);
        }
    }
}
