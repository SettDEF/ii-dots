pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import QtQuick

/**
 * Audio plugins, and profiles that apply a chain of them to a stream.
 *
 * WHY A HOST IS NEEDED AT ALL
 * PipeWire's own filter-chain only loads `builtin` and `bq` filters. It cannot
 * host VST2, VST3 or CLAP - so "put a plugin on my output" is not something the
 * graph can do by itself, and an external host has to sit in the chain. Carla is
 * the one installed here; it speaks all four formats and appears as an ordinary
 * PipeWire client, which is what makes per-stream routing work.
 *
 * WHAT A PROFILE IS
 * A named plugin chain plus which stream it belongs to. Routing itself is not
 * reinvented: the app-routing UI already writes `target.object` through
 * pw-metadata, so a profile just needs to expose a sink for that to point at.
 *
 * SCANNING
 * Deliberately a single `find` per format rather than a directory watcher. A
 * plugin folder changes when the user installs something, which is rare, and a
 * scan is cheap enough to redo on demand.
 */
Singleton {
    id: root

    // ---- Paths -----------------------------------------------------------
    // Plain constants: change them here, no discovery machinery to fight.
    // These are the real locations on this machine - note ~/vst does not exist;
    // VST2 lives in ~/.vst (with the yabridge-generated .so files under it).
    readonly property string home: FileUtils.trimFileProtocol(Directories.home)
    readonly property var searchPaths: ({
        "vst2": [root.home + "/.vst", "/usr/lib/vst"],
        "vst3": [root.home + "/.vst3", "/usr/lib/vst3"],
        "clap": [root.home + "/.clap", "/usr/lib/clap"],
        "lv2":  [root.home + "/.lv2", "/usr/lib/lv2"]
    })

    readonly property string profilesPath:
        FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/audio-profiles.json`)

    // ---- Host ------------------------------------------------------------
    // Carla's frontends are Python and import PyQt5. A broken PyQt5 therefore
    // takes the host out entirely, and the failure is an ImportError on stderr
    // rather than a missing binary - so "is carla on PATH" is not the question
    // worth asking. Run it and see.
    property bool hostChecked: false
    property bool hostAvailable: false
    property string hostError: ""

    function checkHost() {
        hostProbe.running = true
    }

    Process {
        id: hostProbe
        command: ["bash", "-c", "carla-single --help >/dev/null 2>&1; echo $?; "
                              + "python3 -c 'import PyQt5.QtCore' 2>&1 | tail -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                const pyErr = lines.length > 1 ? lines.slice(1).join(" ").trim() : ""
                root.hostChecked = true
                root.hostAvailable = pyErr.length === 0
                root.hostError = pyErr
            }
        }
    }

    // ---- Plugin inventory ------------------------------------------------
    // { name, format, path }
    property var plugins: []
    property bool scanning: false

    readonly property var formatsInOrder: ["vst3", "clap", "vst2", "lv2"]

    function scan() {
        if (root.scanning) return
        root.scanning = true
        // One find per format, tagged so a single stdout can carry them all.
        // VST3 and LV2 are bundle DIRECTORIES; CLAP and VST2 are plain files.
        const parts = []
        for (const fmt of root.formatsInOrder) {
            const dirs = root.searchPaths[fmt].map(d => `'${d}'`).join(" ")
            if (fmt === "vst3")
                parts.push(`find ${dirs} -maxdepth 2 -name '*.vst3' -printf 'vst3\\t%f\\t%p\\n' 2>/dev/null`)
            else if (fmt === "lv2")
                parts.push(`find ${dirs} -maxdepth 1 -name '*.lv2' -printf 'lv2\\t%f\\t%p\\n' 2>/dev/null`)
            else if (fmt === "clap")
                parts.push(`find ${dirs} -maxdepth 2 -name '*.clap' -printf 'clap\\t%f\\t%p\\n' 2>/dev/null`)
            else
                parts.push(`find ${dirs} -maxdepth 3 -name '*.so' -printf 'vst2\\t%f\\t%p\\n' 2>/dev/null`)
        }
        scanProc.command = ["bash", "-c", parts.join("; ")]
        scanProc.running = true
    }

    Process {
        id: scanProc
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of text.split("\n")) {
                    if (line.length === 0) continue
                    const f = line.split("\t")
                    if (f.length < 3) continue
                    out.push({
                        format: f[0],
                        // Strip the extension for display; the path keeps the truth.
                        name: f[1].replace(/\.(vst3|clap|lv2|so)$/, ""),
                        path: f[2]
                    })
                }
                out.sort((a, b) => a.name.localeCompare(b.name))
                root.plugins = out
                root.scanning = false
            }
        }
        onExited: root.scanning = false
    }

    function pluginsOfFormat(fmt) {
        return root.plugins.filter(p => p.format === fmt)
    }
    readonly property int pluginCount: root.plugins.length

    // ---- Profiles --------------------------------------------------------
    // Shape: [{ id, name, target, chain: [{format, name, path}] }]
    //
    // A standalone FileView with a plain `var`, NOT a JsonAdapter: profiles are
    // user-named and therefore dynamically keyed, which is exactly the case
    // Quickshell's JsonAdapter segfaults on (same reason LauncherRanking keeps
    // its own store).
    property var profiles: []
    property int revision: 0

    FileView {
        id: store
        path: Qt.resolvedUrl(`file://${root.profilesPath}`)
        onLoaded: {
            try {
                const d = JSON.parse(store.text() || "{}")
                if (d && Array.isArray(d.profiles)) {
                    root.profiles = d.profiles
                    root.revision++
                }
            } catch (e) {
                // Corrupt file - start clean rather than taking the shell down.
            }
        }
        onLoadFailed: root.profiles = []
        Component.onCompleted: reload()
    }

    function save() {
        store.setText(JSON.stringify({ version: 1, profiles: root.profiles }, null, 2))
    }

    function addProfile(name) {
        const p = {
            id: "p" + Date.now(),
            name: name && name.length > 0 ? name : Translation.tr("New profile"),
            target: "",
            chain: []
        }
        root.profiles = root.profiles.concat([p])
        root.revision++
        root.save()
        return p.id
    }

    function removeProfile(id) {
        root.profiles = root.profiles.filter(p => p.id !== id)
        root.revision++
        root.save()
    }

    function renameProfile(id, name) {
        root.profiles = root.profiles.map(p =>
            p.id === id ? Object.assign({}, p, { name: name }) : p)
        root.revision++
        root.save()
    }

    function addToChain(id, plugin) {
        root.profiles = root.profiles.map(p =>
            p.id === id ? Object.assign({}, p, { chain: p.chain.concat([plugin]) }) : p)
        root.revision++
        root.save()
    }

    function removeFromChain(id, index) {
        root.profiles = root.profiles.map(p => {
            if (p.id !== id) return p
            const c = p.chain.slice()
            c.splice(index, 1)
            return Object.assign({}, p, { chain: c })
        })
        root.revision++
        root.save()
    }

    function profileById(id) {
        return root.profiles.find(p => p.id === id) ?? null
    }

    Component.onCompleted: {
        root.checkHost()
        root.scan()
    }
}
