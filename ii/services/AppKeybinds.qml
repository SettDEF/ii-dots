pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common.functions

/**
 * Keybinds of other apps (tmux, WezTerm, …) for the cheatsheet, as collected
 * by scripts/keybinds-sync — one Rust extractor per app, each asking the app
 * itself what is bound. keybinds-sync.path re-runs it when an app's config
 * changes, so this only has to watch its output file.
 *
 *   apps: [{ id, name, icon, note, sections: [{ name, keybinds: [{ mods, key, comment }] }] }]
 */
Singleton {
    id: root

    readonly property string file: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quickshell/keybinds/apps.json"
    property var apps: []
    readonly property string syncBinary: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/keybinds-sync/keybinds-sync"))

    /// Re-collect now (the cheatsheet's refresh button).
    function sync() { Quickshell.execDetached([root.syncBinary]); }

    FileView {
        path: root.file
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.apps = JSON.parse(text()).apps ?? []; }
            catch (e) { /* mid-write never happens (temp + rename); a bad file keeps the last list */ }
        }
    }
}
