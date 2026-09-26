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
 * host VST2, VST3 or LV2 - so "put a plugin on my output" is not something the
 * graph can do by itself, and an external host has to sit in the chain. That is
 * carla-host, which drives libcarla directly (no PyQt5, no JACK).
 *
 * WHAT A PROFILE IS
 * A named plugin chain that runs as its own sink. Starting one creates a null
 * sink "carla_<name>" and captures the chain's input from that sink's monitor,
 * so routing is not reinvented: the app-routing UI directly above already writes
 * target.object through pw-metadata, and a profile is simply something for it to
 * point at.
 *
 *     app --> sink "carla_<name>" --> monitor --> chain --> output
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
    // Where the helper binaries live. This was referenced as root.binDir but only
    // ever DECLARED in Devices.qml, so hostBin evaluated to the string
    // "undefined/carla-host" - which is why the host probe failed and why a chain
    // could never have started either.
    readonly property string binDir: root.home + "/.local/bin"
    readonly property var searchPaths: ({
        "vst2": [root.home + "/.vst", "/usr/lib/vst"],
        "vst3": [root.home + "/.vst3", "/usr/lib/vst3"],
        "clap": [root.home + "/.clap", "/usr/lib/clap"],
        "lv2":  [root.home + "/.lv2", "/usr/lib/lv2"]
    })

    readonly property string profilesPath:
        FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/audio-profiles.json`)

    // ---- Host ------------------------------------------------------------
    // carla-host drives libcarla_standalone2.so directly. That matters for two
    // reasons: it needs no PyQt5 (Carla's own frontends are Python and a broken
    // PyQt5 takes them all out), and it needs no JACK - Carla's Linux default
    // driver is PulseAudio, which PipeWire provides, so nothing has to be swapped
    // out from under a machine that does music work.
    readonly property string hostBin: root.binDir + "/carla-host"

    property bool hostChecked: false
    property bool hostAvailable: false
    property string hostError: ""

    // The command is assigned HERE rather than left as a binding on the Process.
    // As a binding it was evaluated whenever the engine felt like it, including
    // before Directories.home had resolved - which produced a probe for
    // "/.local/bin/carla-host", a failed test, and a permanent "not runnable"
    // warning for a binary that runs perfectly from a shell.
    function checkHost() {
        if (hostProbe.running) return
        const bin = root.hostBin
        hostProbe.command = ["bash", "-c",
            `test -x '${bin}' && '${bin}' --help >/dev/null 2>&1 && echo ok || echo missing`]
        hostProbe.running = true
    }

    Process {
        id: hostProbe
        // --help exits 0 only if the binary runs AND libcarla loaded.
        stdout: StdioCollector {
            onStreamFinished: {
                const ok = text.trim() === "ok"
                root.hostChecked = true
                root.hostAvailable = ok
                root.hostError = ok ? "" : `carla-host not runnable at ${root.hostBin}`
                if (!ok) console.log("[AudioPlugins] host probe failed:", root.hostBin, "->", text.trim())
            }
        }
    }

    // ---- Running profiles ------------------------------------------------
    // id -> true while its host process is up. Reassigned wholesale so bindings
    // notice; mutating a plain object in place does not.
    property var running: ({})

    function isRunning(id) { return root.running[id] === true }

    function _setRunning(id, on) {
        const next = Object.assign({}, root.running)
        if (on) next[id] = true; else delete next[id]
        root.running = next
    }

    /// Formats carla-host understands. CLAP is absent on purpose: this Carla
    /// build has no PLUGIN_CLAP, so a CLAP in a chain would fail to load and the
    /// whole profile with it. Filtered here rather than at the picker so the
    /// plugin list still shows what is installed.
    function hostableChain(profile) {
        return (profile?.chain ?? []).filter(p => p.format !== "clap")
    }

    function startProfile(id) {
        const p = root.profileById(id)
        if (!p || root.isRunning(id)) return
        const chain = root.hostableChain(p)
        if (chain.length === 0) return
        const args = [root.hostBin, "--name", p.name, "--sink"]
        for (const pl of chain) { args.push("--plugin"); args.push(pl.format + ":" + pl.path) }

        // Reap orphans, THEN launch - never both in the same breath. A host
        // started before the shell reloaded is still running but no longer
        // tracked, so isRunning says no and a second starts on top of it. The
        // first version fired pkill and created the host immediately after,
        // and since exec() does not wait, pkill ran a moment later and matched
        // the brand new process: the profile could not be started at all.
        //
        // Anchored on the full binary path. An unanchored pattern matches ANY
        // command line containing that text - including a shell that merely
        // mentions it - and pkill does not ask twice.
        root._pendingStart = { id: id, argv: args }
        reaper.running = false
        reaper.command = ["pkill", "-f", `^${root.hostBin} --name ${p.name} `]
        reaper.running = true
    }

    property var _pendingStart: null

    Process {
        id: reaper
        // pkill exits 1 when it matched nothing, which is the normal case.
        onExited: {
            const s = root._pendingStart
            root._pendingStart = null
            if (!s || root.isRunning(s.id)) return
            hosts.createObject(root, { profileId: s.id, argv: s.argv })
            root._setRunning(s.id, true)
        }
    }

    function stopProfile(id) {
        // The host unloads its null sink on SIGTERM, so stopping must go through
        // the signal rather than just dropping the object on the floor.
        for (const h of root._hosts) if (h.profileId === id) h.stop()
    }

    property var _hosts: []

    /// Show or hide a plugin's own editor. Goes through the running host
    /// because carla_show_custom_ui draws the window from the process that
    /// loaded the plugin; nothing outside can open it.
    ///
    /// `index` is the position in the HOSTABLE chain - what the host actually
    /// loaded - which differs from the stored chain once a format is filtered.
    function showPluginUi(profileId, index, on) {
        for (const h of root._hosts)
            if (h.profileId === profileId) { h.ui(index, on); return true }
        return false
    }

    /// The host's index for a plugin, or -1 when it never loaded it.
    function hostIndexOf(profile, chainIndex) {
        const chain = profile?.chain ?? []
        if (chainIndex < 0 || chainIndex >= chain.length) return -1
        if (chain[chainIndex].format === "clap") return -1
        let n = 0
        for (let i = 0; i < chainIndex; i++)
            if (chain[i].format !== "clap") n++
        return n
    }

    Component {
        id: hosts
        QtObject {
            id: hostObj
            property string profileId: ""
            property var argv: []
            function stop() { hostProc.signal(15) }
            function ui(index, on) {
                hostProc.write(`ui ${index} ${on ? "on" : "off"}\n`)
            }
            property Process hostProc: Process {
                command: hostObj.argv
                running: true
                // The control channel, open for the life of the chain.
                stdinEnabled: true
                stdout: SplitParser {
                    onRead: line => {
                        if (line.trim().length > 0)
                            console.log("[audio-profile]", hostObj.profileId, line.trim())
                    }
                }
                onExited: {
                    root._setRunning(hostObj.profileId, false)
                    root._hosts = root._hosts.filter(h => h !== hostObj)
                    hostObj.destroy()
                }
            }
            Component.onCompleted: root._hosts = root._hosts.concat([hostObj])
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
        //
        // -mindepth 1 is load-bearing: the search directory itself matches its
        // own pattern (~/.vst3 matches *.vst3), which listed a plugin whose
        // basename was ".vst3" and so displayed with no name at all.
        const parts = []
        for (const fmt of root.formatsInOrder) {
            const dirs = root.searchPaths[fmt].map(d => `'${d}'`).join(" ")
            if (fmt === "vst3")
                parts.push(`find ${dirs} -mindepth 1 -maxdepth 2 -name '*.vst3' -printf 'vst3\\t%f\\t%p\\n' 2>/dev/null`)
            else if (fmt === "lv2")
                parts.push(`find ${dirs} -mindepth 1 -maxdepth 1 -name '*.lv2' -printf 'lv2\\t%f\\t%p\\n' 2>/dev/null`)
            else if (fmt === "clap")
                parts.push(`find ${dirs} -mindepth 1 -maxdepth 2 -name '*.clap' -printf 'clap\\t%f\\t%p\\n' 2>/dev/null`)
            else
                parts.push(`find ${dirs} -mindepth 1 -maxdepth 3 -name '*.so' -printf 'vst2\\t%f\\t%p\\n' 2>/dev/null`)
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
                    // Carla's own bridges and internal racks live in the same
                    // directories but are the host's plumbing, not something to
                    // put in a chain.
                    if (/\/carla\//.test(f[2]) || /^(carla|Carla)/.test(f[1])) continue
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

    // ---- Routing ---------------------------------------------------------
    // A profile IS a sink, so "send this app through my plugins" is the same
    // act as "send this app to that output":
    //
    //     app --> sink "carla_<name>" --> monitor --> chain --> output

    /// Must match the host's own sanitising, or the UI hunts for a sink that
    /// exists under a different name.
    function sinkNameFor(profile) {
        return "carla_" + String(profile?.name ?? "").replace(/[^a-zA-Z0-9]/g, "_")
    }

    /// The profile behind a node, so the routing list can label a chain as a
    /// chain rather than showing "carla_my_profile" among the speakers.
    function profileForSink(nodeName) {
        const n = String(nodeName ?? "")
        if (n.indexOf("carla_") !== 0) return null
        return root.profiles.find(p => root.sinkNameFor(p) === n) ?? null
    }

    function isProfileSink(nodeName) { return root.profileForSink(nodeName) !== null }

    /// The apps currently playing through a chain. carla-host names the null
    /// sink's description after the profile, which is the same string
    /// Audio.sinkForStream reports, so the two line up without a second lookup.
    function appsRoutedTo(profile) {
        const name = String(profile?.name ?? "")
        if (name.length === 0) return []
        return Audio.outputAppNodes.filter(n =>
            n && String(n.name ?? "") !== name && Audio.sinkForStream(n.id) === name)
    }

    /// Send an app through a chain, starting the chain if it is not up yet.
    /// Lives here rather than in the panel because it is the whole point of a
    /// profile, and a caller should not have to know that "route into my
    /// plugins" is spelled `target.object` on a null sink.
    function routeInto(appNode, profile) {
        if (!appNode || !profile) return
        if (!root.isRunning(profile.id)) root.startProfile(profile.id)
        root._pendingRoute = { app: appNode, sink: root.sinkNameFor(profile) }
        routeWait.restart()
    }

    /// Back to automatic - the app follows the default output again.
    function unroute(appNode) {
        if (!appNode) return
        routeProc.exec(["pw-metadata", "-d", String(appNode.id), "target.object"])
        settle.restart()
    }

    property var _pendingRoute: null

    /// The app on its way into a chain, or null. Starting a host and waiting
    /// for its sink takes a second or two, and without this the UI showed
    /// nothing at all in between - the click looked like it had missed.
    function pendingAppFor(profile) {
        const p = root._pendingRoute
        return (p && p.sink === root.sinkNameFor(profile)) ? p.app : null
    }

    function isRoutePending(appNode) {
        return !!(root._pendingRoute && appNode
                  && root._pendingRoute.app?.id === appNode.id)
    }

    Process { id: routeProc }

    // A sink that does not exist yet cannot be targeted, so a freshly started
    // chain is waited for rather than raced.
    Timer {
        id: routeWait
        interval: 400
        repeat: true
        property int tries: 0
        onRunningChanged: if (running) tries = 0
        onTriggered: {
            tries++
            const p = root._pendingRoute
            if (!p) { stop(); return }
            const node = Audio.outputDevices.find(d => d?.name === p.sink)
            if (node) {
                const target = node.properties?.["object.serial"] ?? node.name
                routeProc.exec(["pw-metadata", String(p.app.id), "target.object", String(target)])
                root._pendingRoute = null
                stop()
                settle.restart()
            } else if (tries > 25) {      // ~10s; the host never came up
                root._pendingRoute = null
                stop()
            }
        }
    }

    // The graph needs a moment before it reports the move.
    Timer { id: settle; interval: 350; onTriggered: Audio.refreshStreamSinks() }

    /// Where a running chain plays OUT to - its own stream's destination.
    function outputOf(profile) {
        const name = String(profile?.name ?? "")
        const self = Audio.outputAppNodes.find(n =>
            Audio.appNodeDisplayName(n) === name)
        return self ? Audio.sinkForStream(self.id) : ""
    }

    function profileById(id) {
        return root.profiles.find(p => p.id === id) ?? null
    }

    /// Re-probe and re-scan. Called when the plugins UI opens: the probe used to
    /// run only at startup, so installing the host afterwards left the warning up
    /// for the rest of the session with no way to clear it.
    function refresh() {
        root.checkHost()
        root.scan()
    }

    Component.onCompleted: root.refresh()
}
