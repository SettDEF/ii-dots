pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    property var paths: []

    readonly property string _file: (Directories.home) + "/.local/share/qs-shelf-paths.json"

    Process { id: loadProc; stdout: StdioCollector { onStreamFinished: {
        try {
            const parsed = JSON.parse(text.trim())
            if (Array.isArray(parsed) && parsed.length > 0) root.paths = parsed
            else { root.paths = root._defaults(); root._save() }
        } catch(e) {
            root.paths = root._defaults()
            root._save()
        }
    }}}

    Process { id: saveProc }
    Process { id: ensureDirProc }

    function _defaults() {
        const home = Directories.home ?? "/home/caesar"
        return [
            { label: "Downloads",   path: home + "/Downloads",                          icon: "download",   filter: "zip",          mode: "zip",   extractTo: "/mnt/storage/usr/mooon/vault/beatbattle.net" },
            { label: "BeatBattle",  path: "/mnt/storage/usr/mooon/vault/beatbattle.net", icon: "piano",       filter: "wav,mp3,flac", mode: "audio", extractTo: "" },
            { label: "Mixes",       path: "/mnt/sdcard/lib/mixes",                       icon: "music_note",  filter: "wav,mp3,flac", mode: "audio", extractTo: "" },
        ]
    }

    function _save() {
        const json = JSON.stringify(root.paths, null, 2)
        saveProc.exec({ command: ["bash", "-c", `cat > ~/.local/share/qs-shelf-paths.json << 'EOFQS'\n${json}\nEOFQS`] })
    }

    function add(entry) {
        const arr = root.paths.slice()
        arr.push(entry)
        root.paths = arr
        _save()
    }

    function remove(index) {
        const arr = root.paths.slice()
        arr.splice(index, 1)
        root.paths = arr
        _save()
    }

    function update(index, entry) {
        const arr = root.paths.slice()
        arr[index] = entry
        root.paths = arr
        _save()
    }

    Component.onCompleted: {
        ensureDirProc.exec({ command: ["bash", "-c", "mkdir -p ~/.local/share"] })
        loadProc.exec({ command: ["bash", "-c", "cat ~/.local/share/qs-shelf-paths.json 2>/dev/null || echo '[]'"] })
    }
}
