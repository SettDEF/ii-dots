pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * A permanent virtual microphone, "Mic + shared audio": your mic plus any apps
 * you pick, so the people in a call hear your music or video too.
 *
 *   apps you pick ──► "Share to mic" (null sink) ──┬──► mixer ──► "Mic + shared audio"  ◄── Discord (chosen once)
 *                                                  └──► your output (optional: hear it yourself)
 *   your mic (after Mic.qml's filters) ────────────────► mixer
 *
 * WHY PERMANENT, AND WHY NOTHING IS MOVED
 * The first version built the mixer on demand and moved Discord's capture onto
 * it. Discord's renderer crashed four times in a minute (SIGABRT/SIGSEGV) while
 * its input device appeared, vanished and was moved under it. So now:
 *   - the device is created once and `ensure()` only ever ADDS what is missing,
 *     also after a shell reload — it never rebuilds a device an app is using;
 *   - the user selects it in Discord once; no stream is ever moved onto it,
 *     and Mic.retargetApps() leaves streams on it alone;
 *   - sharing an app only moves that app's PLAYBACK into "Share to mic".
 * Turning the device off is the one moment it disappears; the panel says so.
 *
 * Everything is a runtime pipewire-pulse module named mic_share*, so nothing
 * restarts PipeWire, and teardown finds the modules by name even after a restart.
 */
Singleton {
    id: root

    readonly property string shareSink: "mic_share"
    readonly property string mixSource: "mic_share_mix"

    /// the virtual mic exists (persisted: it should survive reboots)
    property bool enabled: Persistent.states?.mic?.shareEnabled ?? false
    /// true while the mic panel is open: keeps `playingApps` fresh
    property bool polling: false
    property bool hearIt: Persistent.states?.mic?.shareHear ?? true
    property real level: Persistent.states?.mic?.shareLevel ?? 0.6
    /// process binaries whose playback goes into the mic (not persisted on
    /// purpose: nothing should start playing into a call by itself)
    property var sharedApps: []
    /// [{ binary, app }] — every app currently playing
    property var playingApps: []
    /// apps currently recording from "Mic + shared audio"
    property var listeners: []
    property string lastError: ""

    /// Call apps are never offered, in a call or not: their output IS the
    /// other people, so sharing it echoes them back to themselves.
    readonly property var _voiceApp: /discord|vesktop|webcord|armcord|teamspeak|ts3client|mumble|zoom|skype|signal|element|telegram|slack|teams/i

    function setEnabled(on) {
        root.enabled = on;
        Persistent.states.mic.shareEnabled = on;
        root.lastError = "";
        if (on) root.ensure();
        else {
            root.sharedApps = [];
            teardownProc.running = true;
        }
    }

    /// Create whatever part of the graph is missing; touch nothing that exists,
    /// except the mic feed when Mic.qml's chain now ends somewhere else.
    function ensure() {
        if (!root.enabled) return;
        const mic = Mic.processedSource;
        if (!mic || mic.startsWith("mic_share")) {
            root.lastError = Translation.tr("No microphone found to mix with");
            return;
        }
        if (ensureProc.running) { ensureAgain.restart(); return }
        ensureProc.command = ["bash", "-c", root._ensureScript, "sh", mic,
            root.hearIt ? "1" : "0", String(Math.round(root.level * 100))];
        ensureProc.running = true;
    }

    function setHearIt(on) {
        root.hearIt = on;
        Persistent.states.mic.shareHear = on;
        root.ensure();
    }

    /// 0..1: the volume of what you share, for you and for the others alike
    function setLevel(v) {
        root.level = Math.max(0, Math.min(1, v));
        Persistent.states.mic.shareLevel = root.level;
        if (!root.enabled) return;
        levelProc.command = ["pactl", "set-sink-volume", root.shareSink, Math.round(root.level * 100) + "%"];
        levelProc.running = true;
    }

    function isShared(binary) { return root.sharedApps.indexOf(binary) >= 0 }

    function setShared(binary, on) {
        if (!binary || !root.enabled) return;
        const rest = root.sharedApps.filter(b => b !== binary);
        root.sharedApps = on ? rest.concat([binary]) : rest;
        if (!on) {
            backProc.command = ["bash", "-c", root._listScript + "\n"
                + "printf '%s\\n' \"$rows\" | while IFS=$'\\t' read -r idx sink app bin node; do "
                + "[ \"$bin\" = \"$2\" ] && [ \"$sink\" = \"$1\" ] && pactl move-sink-input \"$idx\" @DEFAULT_SINK@; done; true",
                "sh", root.shareSink, binary];
            backProc.running = true;
        }
        root.sync();
    }

    function sync() {
        if (syncProc.running) return;
        syncProc.command = ["bash", "-c", root._listScript + "\n"
            + "share=\"$1\"; meter=\"$2\"; shift 2\n"
            + "printf '%s\\n' \"$rows\" | while IFS=$'\\t' read -r idx sink app bin node; do\n"
            + "  [ -n \"$idx\" ] || continue\n"
            + "  shared=0; for b in \"$@\"; do [ \"$b\" = \"$bin\" ] && shared=1; done\n"
            + "  if [ $shared = 1 ] && [ \"$sink\" != \"$share\" ]; then pactl move-sink-input \"$idx\" \"$share\"; fi\n"
            + "  printf 'P\\t%s\\t%s\\n' \"$bin\" \"$app\"\n"
            + "done\n"
            // who records the virtual mic, for the panel's hint
            // R: every app that records anything (never offered: sharing a
            // voice app's output into the mic echoes the call back to itself);
            // L: the ones recording "Mic + shared audio". The mic panel's own
            // level meter is skipped by its stream name.
            + "src=$(pactl list short sources | awk '$2==\"mic_share_mix\"{print $1}')\n"
            + "pactl list source-outputs | awk -v s=\"$src\" -v meter=\"$meter\" "
            + "'function out(){ if(b!=\"\" && a!=meter){ print \"R\\t\" b; if(o) print \"L\\t\" b } } "
            + "/^Source Output #/{out(); o=0; b=\"\"; a=\"\"} /^\\tSource: /{o=(s!=\"\" && $2==s)} "
            + "/application\\.name = /{a=$0; sub(/.*= \"/,\"\",a); sub(/\"$/,\"\",a)} "
            + "/application\\.process\\.binary = /{b=$0; sub(/.*= \"/,\"\",b); sub(/\"$/,\"\",b)} END{out()}'\n"
            + "true",
            "sh", root.shareSink, Mic.meterAppName].concat(root.enabled ? root.sharedApps : []);
        syncProc.running = true;
    }

    /// Sets `rows`: "index<TAB>sink name<TAB>app<TAB>binary<TAB>node" per stream
    /// that belongs to a real app (has a process binary). Every field is filled
    /// in: `read` with IFS=tab collapses empty fields and shifts the columns.
    /// Text, not `pactl -f json`: the JSON writer rejects any non-ASCII byte.
    readonly property string _listScript: "export LC_ALL=C\n"
        + "rows=$( { pactl list short sinks | awk '{print \"S\\t\" $1 \"\\t\" $2}'; "
        + "pactl list sink-inputs | awk '"
        + "/^Sink Input #/{ if(idx!=\"\") print \"I\\t\" idx \"\\t\" sink \"\\t\" app \"\\t\" bin \"\\t\" nn; idx=substr($3,2); sink=\"\"; app=\"\"; bin=\"\"; nn=\"\" } "
        + "/^\\tSink: /{ sink=$2 } "
        + "/application\\.name = /{ a=$0; sub(/.*application\\.name = \"/,\"\",a); sub(/\"$/,\"\",a); app=a } "
        + "/application\\.process\\.binary = /{ b=$0; sub(/.*binary = \"/,\"\",b); sub(/\"$/,\"\",b); bin=b } "
        + "/node\\.name = /{ n=$0; sub(/.*node\\.name = \"/,\"\",n); sub(/\"$/,\"\",n); nn=n } "
        + "END{ if(idx!=\"\") print \"I\\t\" idx \"\\t\" sink \"\\t\" app \"\\t\" bin \"\\t\" nn }'; } "
        + "| awk -F'\\t' '$1==\"S\"{name[$2]=$3; next} $1==\"I\" && $5!=\"\" {print $2 \"\\t\" name[$3] \"\\t\" ($4!=\"\"?$4:$5) \"\\t\" $5 \"\\t\" ($6!=\"\"?$6:\"-\")}' )"

    /// $1 mic source, $2 hear it (1/0), $3 level percent. Idempotent: every
    /// piece is created only if missing. The default sink is put back in case
    /// WirePlumber promoted a new null sink to default.
    readonly property string _ensureScript: "export LC_ALL=C\n"
        + "case \"$1\" in mic_share*|@*|'') echo \"refusing to mix '$1'\"; exit 1 ;; esac\n"
        // A loopback whose source is missing silently takes the DEFAULT source
        // instead — which fed the mix into itself once. Only ever a real node.
        + "pactl list short sources | awk -v m=\"$1\" '$2==m{f=1} END{exit !f}' || { echo \"mic '$1' not available\"; exit 1; }\n"
        + "mods() { pactl list short modules; }\n"
        + "has() { mods | grep -qE -- \"$1\"; }\n"
        + "unload() { mods | grep -E -- \"$1\" | cut -f1 | xargs -r -n1 pactl unload-module; }\n"
        + "def=$(pactl get-default-sink)\n"
        + "has 'sink_name=mic_share( |$)' || pactl load-module module-null-sink sink_name=mic_share "
        + "\"sink_properties='device.description=\\\"Share to mic\\\"'\" >/dev/null || exit 1\n"
        + "has 'sink_name=mic_share_mix_sink' || pactl load-module module-null-sink sink_name=mic_share_mix_sink channels=1 channel_map=mono "
        + "\"sink_properties='device.description=\\\"Mic share mixer\\\"'\" >/dev/null || exit 1\n"
        + "has 'source_name=mic_share_mix( |$)' || pactl load-module module-remap-source master=mic_share_mix_sink.monitor "
        + "source_name=mic_share_mix channels=1 channel_map=mono \"source_properties='device.description=\\\"Mic + shared audio\\\"'\" >/dev/null || exit 1\n"
        // the mic feed: swapped only when the chain now ends somewhere else
        + "if ! has \"source=$1 .*node.name=mic_share_from_mic\"; then unload 'node.name=mic_share_from_mic'; "
        + "pactl load-module module-loopback source=\"$1\" sink=mic_share_mix_sink latency_msec=20 "
        + "source_dont_move=true sink_dont_move=true "
        + "source_output_properties=node.name=mic_share_from_mic sink_input_properties=node.name=mic_share_mic_in >/dev/null || exit 1; fi\n"
        + "has 'node.name=mic_share_from_apps' || pactl load-module module-loopback source=mic_share.monitor "
        + "sink=mic_share_mix_sink latency_msec=20 source_dont_move=true sink_dont_move=true "
        + "source_output_properties=node.name=mic_share_from_apps sink_input_properties=node.name=mic_share_apps_in >/dev/null || exit 1\n"
        + "if [ \"$2\" = 1 ]; then has 'node.name=mic_share_hear' || pactl load-module module-loopback source=mic_share.monitor "
        + "sink=@DEFAULT_SINK@ latency_msec=30 source_dont_move=true "
        + "source_output_properties=node.name=mic_share_hear sink_input_properties=node.name=mic_share_hear_out >/dev/null; "
        + "else unload 'node.name=mic_share_hear'; fi\n"
        // PipeWire restores a remembered mute per device name; this one is
        // never meant to be muted (mute the real mic in the panel instead).
        + "pactl set-source-mute mic_share_mix 0; pactl set-sink-mute mic_share 0; pactl set-sink-mute mic_share_mix_sink 0\n"
        + "pactl set-sink-volume mic_share \"$3%\"\n"
        + "[ -n \"$def\" ] && [ \"$(pactl get-default-sink)\" != \"$def\" ] && pactl set-default-sink \"$def\"\n"
        + "echo ok"

    Process {
        id: ensureProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.lastError = text.trim() === "ok" ? "" : Translation.tr("Could not build the virtual mic");
                root.sync();
            }
        }
    }

    /// A second ensure() requested while one runs (e.g. a filter toggled):
    /// run it after, rather than racing two scripts over the same modules.
    Timer { id: ensureAgain; interval: 400; onTriggered: root.ensure() }

    Process {
        id: teardownProc
        command: ["bash", "-c",
            "pactl list short modules | awk '/mic_share/{print $1}' | sort -rn | xargs -r -n1 pactl unload-module; true"]
    }

    Process { id: levelProc }
    Process { id: backProc }

    Process {
        id: syncProc
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {};
                const rows = [];
                const listening = [];
                const recording = {};
                const lines = text.split("\n").map(l => l.split("\t"));
                for (const f of lines) {
                    if (f[0] === "R" && f[1]) recording[f[1]] = true;
                    if (f[0] === "L" && f[1] && listening.indexOf(f[1]) < 0) listening.push(f[1]);
                }
                for (const f of lines) {
                    if (f[0] !== "P" || !f[1] || seen[f[1]]) continue;   // one row per app, not per stream
                    seen[f[1]] = true;
                    // A call app is never offered: its output is the other
                    // people's voices. Still listed if already shared, so it
                    // can be switched off.
                    if ((recording[f[1]] || root._voiceApp.test(f[1])) && !root.isShared(f[1])) continue;
                    rows.push({ binary: f[1], app: f[2] || f[1] });
                }
                root.playingApps = rows;
                root.listeners = listening;
            }
        }
    }

    /// New streams of a shared app (the next song, a new tab) follow it in;
    /// the list refreshes while the panel shows it.
    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.polling || (root.enabled && root.sharedApps.length > 0)
        onTriggered: root.sync()
    }

    /// The mic chain now ends somewhere else (a filter toggled, another mic
    /// picked): only the mic feed inside the mixer is swapped.
    Connections {
        target: Mic
        function onProcessedSourceChanged() { root.ensure() }
    }

    IpcHandler {
        target: "micShare"
        function enable(): void { root.setEnabled(true) }
        function disable(): void { root.setEnabled(false) }
        /// play one app into the mic by its process binary, e.g. `share spotify`
        function share(binary: string): void { if (!root.enabled) root.setEnabled(true); root.setShared(binary, true) }
        function unshare(binary: string): void { root.setShared(binary, false) }
        function status(): string {
            return (root.enabled ? "on" : "off") + " shared=" + root.sharedApps.join(",")
                + " playing=" + root.playingApps.map(a => a.binary).join(",")
                + " listeners=" + root.listeners.join(",") + (root.lastError ? " error=" + root.lastError : "")
        }
    }

    /// Enabled: make sure the device exists (a no-op when it already does, so a
    /// shell reload never pulls it out from under Discord). Disabled: remove
    /// leftovers of an earlier run.
    Component.onCompleted: {
        if (root.enabled) ensureStart.start();
        else teardownProc.running = true;
    }
    /// Mic.processedSource needs PipeWire's node list first.
    Timer { id: ensureStart; interval: 1500; onTriggered: root.ensure() }
}
