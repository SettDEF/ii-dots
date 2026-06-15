pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * API keys, read from ~/.secure/apikeys — the single file where every key
 * lives (one KEY=value per line, # comments, chmod 600). Quickshell is
 * launched by the compositor and does NOT inherit the shell's exported env
 * vars, so the file is parsed directly here instead of read from $ENV.
 *
 * Usage:  ApiKeys.get("WALLHAVEN_API_KEY")
 */
Singleton {
    id: root

    // Parsed KEY -> value map. Empty until the file loads.
    property var keys: ({})
    // True once the file has been read at least once (whether found or not).
    property bool ready: false

    function get(name) {
        return root.keys[name] ?? ""
    }

    function _parse(content) {
        const map = ({})
        for (const raw of content.split("\n")) {
            const line = raw.trim()
            if (line === "" || line.startsWith("#")) continue
            const eq = line.indexOf("=")
            if (eq <= 0) continue
            const k = line.slice(0, eq).trim()
            let v = line.slice(eq + 1).trim()
            // Strip one layer of surrounding quotes, matching load-keys.sh.
            if (v.length >= 2 &&
                ((v[0] === '"' && v[v.length - 1] === '"') ||
                 (v[0] === "'" && v[v.length - 1] === "'")))
                v = v.slice(1, -1)
            if (v !== "") map[k] = v
        }
        return map
    }

    FileView {
        id: file
        path: `${Quickshell.env("HOME")}/.secure/apikeys`
        watchChanges: true
        onFileChanged: reload()
        onLoaded:     { root.keys = root._parse(file.text()); root.ready = true }
        onLoadFailed: { root.keys = ({});                     root.ready = true }
    }
}
