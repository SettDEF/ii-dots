pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

/**
 * A nice wrapper for default Pipewire audio sink and source.
 */
Singleton {
    id: root

    // Misc props
    property bool ready: Pipewire.defaultAudioSink?.ready ?? false
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource
    readonly property real hardMaxValue: 2.00 // People keep joking about setting volume to 5172% so...
    property string audioTheme: Config.options.sounds.theme
    property real value: sink?.audio.volume ?? 0
    
    function friendlyDeviceName(node) {
        return (node.nickname || node.description || Translation.tr("Unknown"));
    }
    /// Null-safe: a sheet that is not showing still evaluates its title, and a
    /// bare property read there threw on every such frame.
    function appNodeDisplayName(node) {
        if (!node) return ""
        return (node.properties?.["application.name"] || node.description || node.name || "")
    }

    // Lists
    function correctType(node, isSink) {
        return (node.isSink === isSink) && node.audio
    }
    // A stream belongs to a real application only if the user launched it.
    // Filter-chain plumbing (the HUD equalizer's effect_output.*) and the
    // shell's own playback otherwise show up in every mixer as "HUD
    // Equalizer" / "Qml Runtime", where their volume means nothing.
    // Matched against node.name, which — unlike node.properties — is populated
    // without a PwObjectTracker. Filtering on properties here emptied every
    // mixer, because nothing tracks these nodes until a row is built for them.
    readonly property var _internalBinaries: ["qml", "quickshell", "qs"]
    function isApplicationStream(node) {
        const name = String(node?.name ?? "")
        // Filter-chain plumbing, e.g. the HUD equalizer's effect_output.hud-eq.
        if (/^effect_(input|output)\./.test(name))
            return false
        // The shell's own playback.
        if (name === "Qml Runtime")
            return false
        const binary = String(node?.properties?.["application.process.binary"] ?? "")
        if (binary.length > 0 && root._internalBinaries.includes(binary))
            return false
        // Anything else is a real app. Unknown/untracked nodes are KEPT — a
        // missing property must never blank the list.
        return true
    }
    function appNodes(isSink) {
        return Pipewire.nodes.values.filter((node) => { // Should be list<PwNode> but it breaks ScriptModel
            return root.correctType(node, isSink) && node.isStream
                && root.isApplicationStream(node)
        })
    }
    function devices(isSink) {
        return Pipewire.nodes.values.filter(node => {
            return root.correctType(node, isSink) && !node.isStream
        })
    }
    readonly property list<var> outputAppNodes: root.appNodes(true)

    // ---- Where each stream actually goes ---------------------------------
    // Not readable from the node: the link is a graph edge, and target.object
    // exists only for streams pinned by hand. PulseAudio's view answers it.

    /// PipeWire node id (as a string) -> the description of the sink it feeds.
    property var streamSink: ({})

    function sinkForStream(nodeId) {
        return root.streamSink[String(nodeId)] ?? ""
    }

    /// Panels that display routing hold a watcher while they exist. Nothing
    /// else consumes this, and polling the graph for an audience of nobody is
    /// what made it expensive.
    property int streamWatchers: 0

    function refreshStreamSinks() {
        if (!streamProc.running) streamProc.running = true
    }

    // Debounced, and only while something is watching. Bound straight to
    // outputAppNodesChanged this fired about seventeen times a SECOND with
    // audio playing - the list re-evaluates on any node change - so a bash and
    // two pactl processes were being spawned continuously in the background.
    Timer {
        id: streamDebounce
        interval: 600
        onTriggered: root.refreshStreamSinks()
    }

    Process {
        id: streamProc
        // Text, NOT `pactl -f json`. Its JSON writer refuses any non-ASCII
        // byte - "Invalid ASCII character: 0xff..." on stderr and nothing on
        // stdout - so a single browser tab with an umlaut in its title took the
        // whole listing out and the routing silently showed nothing. The plain
        // listing has no such problem. LC_ALL=C pins the field labels.
        command: ["bash", "-c",
            "export LC_ALL=C; " +
            "pactl list sinks | awk '/^Sink #/{i=substr($2,2)} " +
            "/^\\tDescription: /{d=$0; sub(/^\\tDescription: /,\"\",d); print \"S\\t\" i \"\\t\" d}'; " +
            "pactl list sink-inputs | awk '" +
            "/^Sink Input #/{ if(id!=\"\") print \"I\\t\" id \"\\t\" sink; id=\"\"; sink=\"\" } " +
            "/^\\tSink: /{ sink=$2 } " +
            "/object\\.id = /{ v=$3; gsub(/\"/,\"\",v); id=v } " +
            "END{ if(id!=\"\") print \"I\\t\" id \"\\t\" sink }'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const byIndex = {}
                const next = {}
                for (const line of text.split("\n")) {
                    const f = line.split("\t")
                    if (f.length < 3) continue
                    if (f[0] === "S") byIndex[f[1]] = f.slice(2).join("\t")
                    else if (f[0] === "I") next[f[1]] = byIndex[f[2]] ?? ""
                }
                root.streamSink = next
            }
        }
    }

    // A stream appearing or moving changes the answer.
    onOutputAppNodesChanged: if (root.streamWatchers > 0) streamDebounce.restart()
    onStreamWatchersChanged: if (root.streamWatchers > 0) root.refreshStreamSinks()
    readonly property list<var> inputAppNodes: root.appNodes(false)
    readonly property list<var> outputDevices: root.devices(true)
    readonly property list<var> inputDevices: root.devices(false)

    // Signals
    signal sinkProtectionTriggered(string reason);

    // Controls
    function toggleMute() {
        Audio.sink.audio.muted = !Audio.sink.audio.muted
    }

    function toggleMicMute() {
        Audio.source.audio.muted = !Audio.source.audio.muted
    }

    function incrementVolume() {
        const currentVolume = Audio.value;
        const step = currentVolume < 0.1 ? 0.01 : 0.02 || 0.2;
        Audio.sink.audio.volume = Math.min(1, Audio.sink.audio.volume + step);
    }
    
    function decrementVolume() {
        const currentVolume = Audio.value;
        const step = currentVolume < 0.1 ? 0.01 : 0.02 || 0.2;
        Audio.sink.audio.volume -= step;
    }

    function setDefaultSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }

    function setDefaultSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    // Internals
    PwObjectTracker {
        objects: [sink, source]
    }

    Connections { // Protection against sudden volume changes
        target: sink?.audio ?? null
        property bool lastReady: false
        property real lastVolume: 0
        function onVolumeChanged() {
            if (!Config.options.audio.protection.enable) return;
            const newVolume = sink.audio.volume;
            // when resuming from suspend, we should not write volume to avoid pipewire volume reset issues
            if (isNaN(newVolume) || newVolume === undefined || newVolume === null) {
                lastReady = false;
                lastVolume = 0;
                return;
            }
            if (!lastReady) {
                lastVolume = newVolume;
                lastReady = true;
                return;
            }
            const maxAllowedIncrease = Config.options.audio.protection.maxAllowedIncrease / 100; 
            const maxAllowed = Config.options.audio.protection.maxAllowed / 100;

            if (newVolume - lastVolume > maxAllowedIncrease) {
                sink.audio.volume = lastVolume;
                root.sinkProtectionTriggered(Translation.tr("Illegal increment"));
            } else if (newVolume > maxAllowed || newVolume > root.hardMaxValue) {
                root.sinkProtectionTriggered(Translation.tr("Exceeded max allowed"));
                sink.audio.volume = Math.min(lastVolume, maxAllowed);
            }
            lastVolume = sink.audio.volume;
        }
    }

    function playSystemSound(soundName) {
        const ogaPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.oga`;
        const oggPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.ogg`;

        // Try playing .oga first
        let command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            ogaPath
        ];
        Quickshell.execDetached(command);

        // Also try playing .ogg (ffplay will just fail silently if file doesn't exist)
        command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            oggPath
        ];
        Quickshell.execDetached(command);
    }
}
