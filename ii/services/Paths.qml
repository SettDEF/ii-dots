pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/// This machine's folders from ~/.config/paths.env (its paths.local.env sets them); under the home
/// until read. Read here, not from the environment: a running shell keeps the env it started with.
Singleton {
    id: root
    readonly property string home: Quickshell.env("HOME")
    property string storage: home
    property string projects: home + "/dev/projects"
    property string videos: home + "/Videos"
    property string downloads: home + "/Downloads"
    property string vault: home + "/vault"

    Process {
        running: true
        command: ["sh", "-c", '. "$HOME/.config/paths.env" 2>/dev/null; printf "%s\\n" "$STORAGE" "$PROJECTS_DIR" "$VIDEOS_DIR" "$DOWNLOADS_DIR" "$VAULT_DIR"']
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.split("\n");
                if (v.length < 5 || v[0] === "") return;
                root.storage = v[0]; root.projects = v[1]; root.videos = v[2]; root.downloads = v[3]; root.vault = v[4];
            }
        }
    }
}
