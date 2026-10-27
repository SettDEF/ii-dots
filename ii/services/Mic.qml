pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

/**
 * Microphone control: what RØDE Central gives you on Windows and what Discord
 * gives you as four checkboxes, in one place.
 *
 * WHY A SERVICE
 * The bar, the OSD and the panel all want the same two facts — muted, and how
 * loud — and the hardware gain has to be re-applied from somewhere that outlives
 * any panel. One thing talks to amixer.
 *
 * THE HARDWARE GAIN PROBLEM, WHICH IS WHY THIS EXISTS
 * ALSA mixer values live in the driver, not on disk. Replug, USB reset, card
 * renumbering, or a profile switch between `mono-fallback` and `pro-audio`, and
 * the gain snaps back to the factory value — 60 dB, i.e. maximum, on the NT1.
 * Observed reverting three times in one session by three different routes, which
 * is why a one-shot `amixer sset` is useless and this re-applies instead.
 */
Singleton {
    id: root

    /* --- which microphone -------------------------------------------------- */

    /// The node name the user picked, persisted. Empty means "follow the system
    /// default", which is the old behaviour and a bad default for this panel:
    /// the default source is a system-wide setting other apps change, and it was
    /// observed pointing at a muted onboard input while the NT1 sat unused.
    property string preferredName: Persistent.states?.mic?.preferredSource ?? ""

    /// Reuse Audio.devices() rather than filtering by hand. The hand-rolled
    /// version tested `n.isSink === false`, which is false for any node whose
    /// isSink is undefined — so the list was wrong, and the picker then showed
    /// `sources[0]` while the service was still using a different device.
    readonly property list<var> sources: Audio.devices(false)

    readonly property PwNode source: {
        // A filter's own output is never "the microphone": it was saved here
        // once (preferredSource = mic_rnnoise), and with the filter not running
        // the panel reported the mic as disconnected.
        if (root.preferredName !== "" && !root._isOwn(root.preferredName)) {
            const pick = root.sources.find(n => n.name === root.preferredName)
                // the same device under another profile: an update left the RØDE with only
                // "pro-audio", so ….mono-fallback became ….pro-input-0 (2026-10-22)
                ?? root.sources.find(n => root._sameDevice(n.name, root.preferredName));
            if (pick) return pick;
        }
        const def = Pipewire.defaultAudioSource;
        if (def && !root._isOwn(def.name)) return def;
        // The default is one of OUR nodes: makeDefault() put the end of the
        // chain there on purpose. Treating it as "the microphone" made every
        // chain read its own output after a shell reload — the mic-share mixer
        // fed the mix back into itself. Use the last real default instead.
        return root.sources.find(n => n.name === root._lastRealDefault)
            ?? root.sources.find(n => !root._isOwn(n.name))
            ?? null;
    }

    /// Nodes this service and MicShare create are all named mic_*.
    function _isOwn(name) { return (name ?? "").startsWith("mic_") }
    function _exists(name) { return root.sources.some(n => n.name === name) }
    /// The ALSA device a source belongs to (its name without the profile part), "" for others.
    function _device(name) {
        const n = name ?? "";
        return n.startsWith("alsa_input.") ? n.slice(0, n.lastIndexOf(".")) : "";
    }
    function _sameDevice(a, b) { return root._device(a) !== "" && root._device(a) === root._device(b) }

    property string _lastRealDefault: ""
    readonly property string _defaultName: Pipewire.defaultAudioSource?.name ?? ""
    on_DefaultNameChanged: if (root._defaultName !== "" && !root._isOwn(root._defaultName)) root._lastRealDefault = root._defaultName

    /// True when the user asked for a device that is not currently present —
    /// worth saying out loud rather than silently metering something else.
    readonly property bool preferredMissing: root.preferredName !== "" && !root._isOwn(root.preferredName)
        && !root.sources.some(n => n.name === root.preferredName || root._sameDevice(n.name, root.preferredName))

    readonly property bool ready: source?.ready ?? false
    readonly property string deviceName: source?.description ?? source?.name ?? ""
    readonly property bool muted: source?.audio?.muted ?? false
    /// the node volume as pactl reads it (the node is untracked, so `audio.volume` stays 0 for a
    /// mic that appeared later: the panel said "input volume is 0%" at 100%, 2026-10-22)
    property real _pactlVolume: -1
    readonly property real volume: root._pactlVolume >= 0 ? root._pactlVolume : (source?.audio?.volume ?? 0)

    // NO PwObjectTracker, deliberately — services/Devices.qml documents that
    // tracking device nodes writes back into the PipeWire objects and re-runs
    // the very bindings that read them. The consequence, per Audio.qml, is that
    // `node.properties` stays EMPTY: measured `propsKeys: 0`, so `alsa.card` was
    // null and the panel reported "no hardware gain control" on a device that
    // has one. `node.name` is populated without tracking, so the card is
    // resolved from that instead — in the shell, which can read what QML cannot.

    function selectSource(name) {
        if (root._isOwn(name)) name = "";   // see `source`: never a filter output
        root.preferredName = name ?? "";
        Persistent.states.mic.preferredSource = root.preferredName;
    }

    function setMuted(on) { if (root.source?.audio) root.source.audio.muted = on }
    /**
     * Deliberately NOT a gain setter.
     *
     * An earlier version routed this into `setGainDb` by mapping 0..1 onto the
     * dB range, on the grounds that the two are the same ALSA control on this
     * device. They are — but the mapping meant a single "volume = 100%" became
     * "gain = 60 dB", i.e. the maximum, which is the precise fault this service
     * exists to prevent. It slammed the gain to 60 within minutes of shipping.
     *
     * The panel has one slider, in dB, and it calls setGainDb. This stays only
     * for callers that think in 0..1 and sets the node volume, nothing else.
     */
    function setVolume(v) {
        if (root.source?.audio)
            root.source.audio.volume = Math.max(0, Math.min(1, v));
        if (root._pactlVolume >= 0) root._pactlVolume = Math.max(0, Math.min(1, v));
    }

    /* --- hardware gain ----------------------------------------------------- */

    /**
     * The ALSA card index, taken STRAIGHT FROM THE NODE.
     *
     * The first version guessed it by matching a word from the device
     * description against the card ids under /proc/asound, which picked the second
     * alphanumeric token — `"5th"` out of "RØDE NT1 5th Gen Mono" — matched
     * nothing, and silently fell back to the first capture-capable card. The
     * panel then drove a completely different device's input level under the
     * NT1's name. PipeWire already publishes `alsa.card`; there was never
     * anything to guess.
     */
    /// Raw probe output, kept so a failure is inspectable over IPC instead of
    /// being inferred. Four wrong diagnoses in a row is what this costs.
    property string probeRaw: "(never ran)"

    /// Resolved by the probe below from the node NAME, not from
    /// `node.properties` — see the note above about why properties are empty.
    property int cardIndex: -1

    property real desiredGainDb: Persistent.states?.mic?.gainDb ?? 20
    property real actualGainDb: -1
    property real minGainDb: 0
    property real maxGainDb: 60
    property string gainControl: ""
    readonly property bool gainAvailable: root.cardIndex >= 0 && root.gainControl !== ""
    readonly property bool gainDrifted: root.gainAvailable
        && root.actualGainDb >= 0
        && Math.abs(root.actualGainDb - root.desiredGainDb) > 0.6

    /// How many times we have tried to push the gain back without it sticking.
    /// The first version had probe → apply → probe with no counter, so a write
    /// that could never satisfy the comparison (wrong card, clamped range,
    /// device gone) spun forever: `amixer` was measured running in every one of
    /// 50 samples over 10 s, with the panel closed.
    property int _restoreAttempts: 0
    readonly property int _maxRestoreAttempts: 3
    readonly property bool gainStuck: root._restoreAttempts >= root._maxRestoreAttempts

    Process {
        id: probeGain
        // Plain concatenation, never a template literal: QML reads ${...} inside
        // backticks as JavaScript, so a shell expansion there is a syntax error
        // that takes the whole services module down with it.
        // Kept deliberately small. The previous version embedded a python
        // program inside a bash string inside QML string concatenation to read
        // pw-dump; it was unreadable and it silently produced nothing. `pactl`
        // already prints alsa.card under each source, so one grep does it.
        command: ["bash", "-c",
            "name=\"$1\"\n" +
            "[ -n \"$name\" ] || { echo none; exit 0; }\n" +
            "vol=$(pactl get-source-volume \"$name\" 2>/dev/null | grep -m1 -oE '[0-9]+%' | tr -d %)\n" +
            "echo \"VOL=${vol:--1}\"\n" +
            "card=$(pactl list sources 2>/dev/null | grep -A40 \"Name: $name\" " +
                "| grep -m1 'alsa.card = ' | tr -d '\"' | awk '{print $3}')\n" +
            "[ -n \"$card\" ] || { echo none; exit 0; }\n" +
            "ctl=$(amixer -c \"$card\" scontrols 2>/dev/null | sed -n \"s/.*'\\(Mic\\|Capture\\|Input\\)'.*/\\1/p\" | head -1)\n" +
            "[ -n \"$ctl\" ] || { echo \"$card||\"; exit 0; }\n" +
            "info=$(amixer -c \"$card\" sget \"$ctl\" 2>/dev/null)\n" +
            "db=$(printf '%s' \"$info\" | grep -m1 -oE '\\[-?[0-9.]+dB\\]' | tr -d '[]dB')\n" +
            "lim=$(printf '%s' \"$info\" | grep -m1 -oE 'Limits: Capture -?[0-9]+ - -?[0-9]+')\n" +
            "echo \"$card|$ctl|$db|$lim\"\n",
            "sh", root.source?.name ?? ""]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const vl = lines.find(l => l.startsWith("VOL="));
                const v = vl ? parseInt(vl.slice(4)) : -1;
                root._pactlVolume = isNaN(v) || v < 0 ? -1 : v / 100;
                const out = lines.filter(l => !l.startsWith("VOL=")).join("\n").trim();
                root.probeRaw = out === "" ? "(empty)" : out;
                if (out === "none" || out === "") {
                    root.cardIndex = -1; root.gainControl = ""; root.actualGainDb = -1; return
                }
                const parts = out.split("|");
                const card = parseInt(parts[0] ?? "");
                root.cardIndex = isNaN(card) ? -1 : card;
                root.gainControl = parts[1] ?? "";
                const db = parseFloat(parts[2] ?? "");
                root.actualGainDb = isNaN(db) ? -1 : db;
                const lim = (parts[3] ?? "").match(/(-?[0-9]+) - (-?[0-9]+)/);
                if (lim) { root.minGainDb = parseInt(lim[1]); root.maxGainDb = parseInt(lim[2]) }

                // Re-assert, but BOUNDED. Giving up loudly beats spinning quietly.
                if (root.gainDrifted && !root.gainStuck) {
                    root._restoreAttempts += 1;
                    root.applyGain();
                } else if (!root.gainDrifted) {
                    root._restoreAttempts = 0;
                }
            }
        }
    }

    Process {
        id: setGain
        command: ["true"]
        // Deliberately does NOT re-trigger the probe. The old version did, which
        // closed the loop; the timer below is what re-checks, on its own clock.
    }

    function applyGain() {
        if (root.cardIndex < 0 || root.gainControl === "") return;
        setGain.command = ["amixer", "-c", String(root.cardIndex),
                           "sset", root.gainControl, Math.round(root.desiredGainDb) + "dB"];
        setGain.running = true;
    }

    function setGainDb(db) {
        root.desiredGainDb = Math.max(root.minGainDb, Math.min(root.maxGainDb, db));
        Persistent.states.mic.gainDb = root.desiredGainDb;
        root._restoreAttempts = 0;   // a deliberate change deserves a fresh budget
        root.applyGain();
    }

    /// Slow on purpose. The gain only changes behind our back on device events,
    /// and this spawns a process each time — the panel does not need to be open
    /// for it to run, so the interval is the idle cost of the whole feature.
    Timer {
        interval: 5000
        running: (root.source?.name ?? "") !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!probeGain.running) probeGain.running = true
    }

    /// A different device means a different card and a fresh driver at factory
    /// defaults, so re-probe at once and restore the attempt budget.
    onSourceChanged: {
        // found under its new name (a profile change): remembered so, after this change (at once
        // it re-ran this binding inside itself: a binding loop)
        if (root.source && root.source.name !== root.preferredName && root._sameDevice(root.source.name, root.preferredName)) {
            const now = root.source.name;
            Qt.callLater(() => root.selectSource(now));
        }
        // The remembered gain belongs to the PREVIOUS device. Carrying it over
        // is how 60 dB intended for one card ended up being forced onto another
        // whose range stops at 30.
        root.desiredGainDb = Math.max(root.minGainDb,
                                      Math.min(root.maxGainDb, root.desiredGainDb));
        root.cardIndex = -1;
        root.gainControl = "";
        root.actualGainDb = -1;
        root._restoreAttempts = 0;
        if (!probeGain.running) probeGain.running = true;
        chainRetarget.restart();
        liveOnArrival.restart();
    }

    /// A mic that appears (boot, replug, newly picked) starts live. WirePlumber
    /// restores the last saved mute per device, and a stale "muted" left the
    /// RØDE silent in Discord after every replug. Delayed past that restore.
    Timer {
        id: liveOnArrival
        interval: 2000
        // pactl, not `root.muted`: the source is untracked (see above), so its
        // mute flag here can be stale.
        onTriggered: {
            const dev = root.source?.name ?? "";
            if (!dev || root._isOwn(dev)) return;
            unmuteProc.command = ["bash", "-c",
                "pactl get-source-mute \"$1\" | grep -q yes && pactl set-source-mute \"$1\" 0; true",
                "sh", dev];
            unmuteProc.running = true;
        }
    }
    Process { id: unmuteProc; command: ["true"] }

    /// Running chains read the device they were STARTED on, so picking another
    /// mic left them on the old one (Discord heard the laptop mic, 2026-10-11).
    /// Moved live, never restarted: nodes appearing or vanishing crash Discord.
    Timer {
        id: chainRetarget
        interval: 300
        onTriggered: {
            const dev = root.source?.name ?? "";
            if (!dev || root._isOwn(dev)) return;
            chainMove.command = ["bash", "-c",
                "for n in \"$2\" mic_monitor_in; do "
                + "for i in $(pactl -f json list source-outputs | jq -r --arg n \"$n\" "
                + "'.[]|select(.properties.\"node.name\"==$n)|.index'); do "
                + "pactl move-source-output \"$i\" \"$1\"; done; done",
                "sh", dev, root.highPass ? "mic_hp_in" : "mic_rnnoise_in"];
            chainMove.running = true;
        }
    }
    Process { id: chainMove; command: ["true"] }

    /* --- switched-off microphones ----------------------------------------- */

    /// Sound cards that have an input but whose profile is "off", so PipeWire makes no source
    /// for them and they are missing from the picker. An update left the RØDE offering only
    /// "pro-audio", sitting at "off": the panel said "not connected" while it was plugged in
    /// (2026-10-22). Each is {card, description, profile}: the profile it would be turned on to.
    property var offCards: []
    /// The card a source belongs to (alsa_input.X.port → alsa_card.X).
    function _cardFor(name) {
        const d = root._device(name);
        return d ? "alsa_card." + d.slice("alsa_input.".length) : "";
    }
    /// The chosen mic is plugged in but switched off (not unplugged).
    readonly property bool preferredOff: root.preferredMissing
        && root.offCards.some(c => c.card === root._cardFor(root.preferredName))

    /// Turns a card on, to its best profile with an input (mono-fallback, then analog, then
    /// pro-audio). Only adds a source: no stream is moved (voice apps crash when moved).
    function wakeCard(card, profile) {
        if (!card || !profile) return;
        wakeProc.command = ["pactl", "set-card-profile", card, profile];
        wakeProc.running = true;
    }
    Process {
        id: wakeProc
        command: ["true"]
        onExited: cardsProbe.running = true
    }

    Process {
        id: cardsProbe
        // jq, as chainRetarget uses. Only ALSA cards whose profile is exactly "off": a headset
        // left on an output-only profile on purpose (the HDB 630's mic costs it its good audio)
        // is not "off" and is never touched.
        command: ["bash", "-c",
            "pactl -f json list cards 2>/dev/null | jq -r '.[] | select(.name|startswith(\"alsa_card.\")) "
            + "| select(.active_profile == \"off\") | . as $c "
            + "| [$c.profiles | to_entries[] | select(.value.sources > 0 and .value.available != false)] as $in "
            + "| select(($in|length) > 0) "
            + "| ($in | sort_by((if .key == \"mono-fallback\" then 0 elif (.key|test(\"analog|input\")) then 1 elif .key == \"pro-audio\" then 2 else 3 end), -.value.priority) | .[0].key) as $p "
            + "| [$c.name, ($c.properties[\"device.description\"] // $c.name), $p] | join(\"|\")'"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.offCards = text.split("\n").filter(l => l.includes("|")).map(l => {
                    const p = l.split("|");
                    return { card: p[0], description: p[1], profile: p[2] };
                });
                // the chosen mic, switched off: on again, a few tries at most
                const mine = root.offCards.find(c => c.card === root._cardFor(root.preferredName));
                if (mine && root._wakeTries < 3) {
                    root._wakeTries += 1;
                    root.wakeCard(mine.card, mine.profile);
                } else if (!mine) {
                    root._wakeTries = 0;
                }
            }
        }
    }
    property int _wakeTries: 0
    onSourcesChanged: if (!cardsProbe.running) cardsProbe.running = true
    Timer {
        // a card switched off by something else, with nothing in the source list changing
        interval: 15000
        running: root.preferredMissing
        repeat: true
        onTriggered: if (!cardsProbe.running) cardsProbe.running = true
    }
    Component.onCompleted: cardsProbe.running = true

    /* --- level ------------------------------------------------------------- */

    /**
     * The microphone's own level.
     *
     * NOT `AudioMeter`: that singleton is hard-bound to `Audio.sink + ".monitor"`
     * — the speakers — and is already used by the audio panel and the recorder.
     * Pointing it here would have shown playback level in a mic panel and broken
     * their meter at the same time. An input level and an output level are two
     * measurements that legitimately run at once.
     */
    property bool metering: false
    property real levelDb: -70
    readonly property bool silent: root.levelDb <= -60
    readonly property bool clipping: root.levelDb > -3

    /// The name this meter registers under, so the "apps recording" list can
    /// exclude it. Without it the panel listed its own level meter as a third
    /// party using your microphone — ffmpeg reports itself as "Lavf63.1.101".
    readonly property string meterAppName: "ii-mic-meter"

    Process {
        id: meterProc
        // `-name`, not PULSE_PROP: the env var did not reach the stream — it
        // still registered as ffmpeg's own "Lavf63.1.101" — while the demuxer's
        // own option does exactly this. Verified with `pactl list source-outputs`.
        command: ["ffmpeg", "-hide_banner", "-f", "pulse",
                  "-name", root.meterAppName,
                  "-i", root.source?.name ?? "",
                  "-af", "ebur128=peak=true", "-f", "null", "-"]
        running: root.metering && (root.source?.name ?? "") !== ""
        onRunningChanged: if (!running) root.levelDb = -70
        // ffmpeg writes filter output to stderr.
        stderr: SplitParser {
            onRead: line => {
                const m = line.match(/M:\s*(-?[0-9.]+)/);
                if (m) root.levelDb = parseFloat(m[1]);
            }
        }
    }

    /* --- which app is recording, and from where ----------------------------- */

    /**
     * The input twin of `Audio.streamSink`.
     *
     * Which device a stream actually reads from is a graph edge, not a property
     * of the node — PulseAudio's view answers it and PipeWire's node does not,
     * which is the same reason Audio.qml shells out for the output direction.
     * Kept here rather than in Audio.qml because the mic panel is the only
     * consumer; if a second one appears, this belongs next to its twin.
     *
     * Text output, not `pactl -f json`: Audio.qml records that the JSON writer
     * refuses any non-ASCII byte, so one app with an umlaut in its name takes
     * the whole listing out and the routing silently shows nothing.
     */
    property var recordingStreams: []

    Process {
        id: streamProc
        command: ["bash", "-c",
            "export LC_ALL=C; " +
            "pactl list sources | awk '/^Source #/{i=substr($2,2)} " +
            "/^\\tName: /{n=$2} " +
            "/^\\tDescription: /{d=$0; sub(/^\\tDescription: /,\"\",d); print \"S\\t\" i \"\\t\" n \"\\t\" d}'; " +
            "pactl list source-outputs | awk '" +
            "/^Source Output #/{ if(idx!=\"\") print \"O\\t\" idx \"\\t\" src \"\\t\" app \"\\t\" bin \"\\t\" nn \"\\t\" mn; " +
            "  idx=substr($3,2); src=\"\"; app=\"\"; bin=\"\"; nn=\"\"; mn=\"\" } " +
            "/^\\tSource: /{ src=$2 } " +
            "/application\\.name = /{ a=$0; sub(/.*application\\.name = \"/,\"\",a); sub(/\"$/,\"\",a); app=a } " +
            "/application\\.process\\.binary = /{ b=$0; sub(/.*binary = \"/,\"\",b); sub(/\"$/,\"\",b); bin=b } " +
            "/node\\.name = /{ n=$0; sub(/.*node\\.name = \"/,\"\",n); sub(/\"$/,\"\",n); nn=n } " +
            "/media\\.name = /{ m=$0; sub(/.*media\\.name = \"/,\"\",m); sub(/\"$/,\"\",m); mn=m } " +
            "END{ if(idx!=\"\") print \"O\\t\" idx \"\\t\" src \"\\t\" app \"\\t\" bin \"\\t\" nn \"\\t\" mn }'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const byIndex = {};
                const rows = [];
                for (const line of text.split("\n")) {
                    const f = line.split("\t");
                    if (f.length < 3) continue;
                    if (f[0] === "S") byIndex[f[1]] = { name: f[2], desc: f.slice(3).join("\t") };
                    else if (f[0] === "O") {
                        const dev = byIndex[f[2]] ?? { name: "", desc: "" };
                        const app = (f[3] ?? "").trim();
                        const bin = (f[4] ?? "").trim();
                        const node = (f[5] ?? "").trim();
                        const media = (f[6] ?? "").trim();

                        // Skip this panel's OWN plumbing. The meter and the
                        // filter chains genuinely capture from the microphone,
                        // but they are not "apps using your microphone" — they
                        // are this panel. Listing them showed the user two rows
                        // of "Unknown app" that were the noise suppression and
                        // high-pass they had just switched on here.
                        // Every stream this panel creates is named mic_* (filter
                        // chains, monitoring, MicShare's mixer). Retargeting one
                        // of those onto the mix would loop the mix into itself.
                        if (app === root.meterAppName) continue;
                        if (node.startsWith("mic_") || node.indexOf("mic_share") >= 0) continue;

                        // Name it from whatever the client actually provided,
                        // best first. "Unknown app" is the last resort, not the
                        // first thing a nameless stream falls back to.
                        rows.push({
                            index: f[1],
                            app: app || media || node || "Unknown app",
                            binary: bin || node,
                            sourceName: dev.name,
                            sourceDesc: dev.desc,
                        });
                    }
                }
                root.recordingStreams = rows;
            }
        }
    }

    /// Polled only while the panel is up. Audio.qml learned this the hard way:
    /// bound straight to a node-list change it fired seventeen times a second
    /// with audio playing, spawning bash and two pactl processes continuously.
    Timer {
        interval: 2000
        running: root.metering
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!streamProc.running) streamProc.running = true
    }

    Process { id: moveProc; command: ["true"] }

    /// Move one app's capture to another device, the way Windows lets you pick a
    /// microphone per app. Takes the source-output INDEX, not the node id —
    /// `pactl move-source-output` will not accept the latter.
    /**
     * Move every real app onto the current end of the chain.
     *
     * Without this, switching on "Noise suppression" built a denoised source and
     * left every app still recording the raw microphone — the filter ran and
     * nobody heard the difference, which is indistinguishable from it not
     * working. A switch that says "on" has to change what you hear.
     *
     * Our own meter and chain inputs are skipped: they must keep reading the
     * stage they were built to read.
     */
    /**
     * Make the end of the chain the SYSTEM DEFAULT source.
     *
     * Apps that offer no microphone picker — games especially, Bodycam among
     * them — record from whatever the system calls default. Moving existing
     * streams is not enough for those: they open the default at launch and
     * never ask again, so the default has to already be right before they start.
     *
     * This is the "handle it on the desktop" half of the problem; `retargetApps`
     * handles the apps that are already running.
     */
    function makeDefault() {
        const dest = root.effectiveSource;
        if (!dest) return;
        defaultProc.command = ["bash", "-c",
            "id=$(pactl list short sources 2>/dev/null | awk -v n=\"$1\" '$2==n{print $1; exit}'); "
            + "[ -n \"$id\" ] && pactl set-default-source \"$id\"",
            "sh", dest];
        defaultProc.running = true;
    }

    Process { id: defaultProc; command: ["true"] }

    function retargetApps() {
        const dest = root.effectiveSource;
        if (!dest) return;
        for (const row of root.recordingStreams) {
            if (row.sourceName === dest) continue;
            // Apps the user pointed at "Mic + shared audio" stay there: moving
            // a live voice stream is what crashed Discord's renderer.
            if (row.sourceName === MicShare.mixSource) continue;
            root.moveStream(row.index, dest);
        }
    }

    /// Chains take a moment to register their source; move once it exists.
    Timer {
        id: retargetDelay
        interval: 900
        repeat: false
        onTriggered: { streamProc.running = true; root.retargetApps(); root.makeDefault() }
    }

    function moveStream(index, sourceName) {
        if (!index || !sourceName) return;
        moveProc.command = ["pactl", "move-source-output", String(index), sourceName];
        moveProc.running = true;
        streamProc.running = true;
    }

    /* --- processing chain --------------------------------------------------- */

    property bool noiseSuppression: Persistent.states?.mic?.noiseSuppression ?? false
    /// VAD threshold in percent. The plugin's own default is 74; below ~50 it
    /// starts letting the noise through, above ~90 it chops word endings.
    property real vadThreshold: Persistent.states?.mic?.vadThreshold ?? 74
    property bool echoCancel: Persistent.states?.mic?.echoCancel ?? false
    property bool highPass: Persistent.states?.mic?.highPass ?? false
    property real highPassHz: Persistent.states?.mic?.highPassHz ?? 80
    property bool monitoring: false

    /// rnnoise the library is present, but the LADSPA wrapper PipeWire needs
    /// (`noise-suppression-for-voice`) is not, so the switch stays honest.
    property bool rnnoiseAvailable: false
    readonly property bool echoCancelAvailable: true

    Process {
        running: true
        command: ["bash", "-c",
            "ls /usr/lib/ladspa/librnnoise_ladspa.so /usr/lib/ladspa/rnnoise_ladspa.so 2>/dev/null | head -1"]
        stdout: StdioCollector { onStreamFinished: root.rnnoiseAvailable = text.trim() !== "" }
    }

    /**
     * Loaded module ids, so they can be unloaded individually.
     *
     * The first version unloaded by NAME — `pactl unload-module module-loopback`
     * — which removes EVERY instance. Turning "Hear myself" off would have taken
     * down an unrelated hand-made Bitwig loopback with it.
     */
    property var _moduleIds: ({})

    Process {
        id: loadModule
        command: ["true"]
        property string slot: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const id = parseInt(text.trim());
                if (!isNaN(id)) {
                    const next = Object.assign({}, root._moduleIds);
                    next[loadModule.slot] = id;
                    root._moduleIds = next;
                }
            }
        }
        // A failed load must not leave the switch asserting a filter that is not
        // running; the caller reads this back.
        onExited: code => { if (code !== 0) root.lastError = "Could not load " + loadModule.slot }
    }

    Process { id: unloadModule; command: ["true"] }

    property string lastError: ""

    function _load(slot, args) {
        loadModule.slot = slot;
        loadModule.command = ["pactl", "load-module"].concat(args);
        loadModule.running = true;
    }

    function _unload(slot) {
        const id = root._moduleIds[slot];
        if (id === undefined) return;
        unloadModule.command = ["pactl", "unload-module", String(id)];
        unloadModule.running = true;
        const next = Object.assign({}, root._moduleIds);
        delete next[slot];
        root._moduleIds = next;
    }

    /**
     * Filter chains run as their own small PipeWire instance, NOT via pactl.
     *
     * `pactl load-module module-filter-chain` fails with "No such entity" —
     * verified, and it fails for the plain builtin `bq_highpass` too, so it is
     * not about LADSPA. `pactl` speaks the PulseAudio protocol and can only load
     * PulseAudio-compatible modules (loopback, echo-cancel, null-sink);
     * filter-chain is a PipeWire module. An earlier version of this file used
     * pactl for both the high-pass and the denoiser, and neither could ever have
     * worked.
     *
     * A standalone instance also needs the protocol/client-node/adapter modules
     * listed explicitly, or it dies with "can't find protocol
     * PipeWire:Protocol:Native" before reaching the filter.
     */
    function _chainConf(desc, nodeName, graphNodes, input) {
        const src = input || (root.source?.name ?? "");
        return "context.properties = { log.level = 0 }\n"
            + "context.spa-libs = {\n"
            + "  audio.convert.* = audioconvert/libspa-audioconvert\n"
            + "  support.*       = support/libspa-support\n"
            + "}\n"
            + "context.modules = [\n"
            + "  { name = libpipewire-module-protocol-native }\n"
            + "  { name = libpipewire-module-client-node }\n"
            + "  { name = libpipewire-module-adapter }\n"
            + "  { name = libpipewire-module-filter-chain\n"
            + "    args = {\n"
            + "      node.description = \"" + desc + "\"\n"
            + "      media.name       = \"" + desc + "\"\n"
            + "      filter.graph = { nodes = [ " + graphNodes + " ] }\n"
            + "      capture.props  = { node.name = \"" + nodeName + "_in\" node.passive = true"
            + " target.object = \"" + src + "\" }\n"
            + "      playback.props = { node.name = \"" + nodeName + "\" media.class = Audio/Source }\n"
            + "    }\n  }\n]\n";
    }

    /// One `pipewire -c` child per chain, tracked by slot so it can be stopped.
    property var _chains: ({})

    Process { id: chainWriter; command: ["true"] }

    /**
     * What apps should actually be recording from.
     *
     * The chains are ordered: high-pass first, then the denoiser — cutting
     * rumble before the noise model sees it is both the conventional order and
     * the one that gives RNNoise less to chew on. Whichever is last is what
     * apps should use.
     */
    // A stage counts only once its node exists: the switch can be on while
    // the chain is still starting (or died), and naming a missing node made
    // PipeWire fall back to the default source.
    readonly property string processedSource: {
        if (root.noiseSuppression && root._exists("mic_rnnoise")) return "mic_rnnoise";
        if (root.highPass && root._exists("mic_hp")) return "mic_hp";
        return root.source?.name ?? "";
    }

    readonly property string effectiveSource: root.processedSource

    /// Each chain's input: the previous stage if there is one, else the device.
    function _inputFor(slot) {
        if (slot === "rnnoise" && root.highPass) return "mic_hp";
        return root.source?.name ?? "";
    }

    function _startChain(slot, desc, nodeName, graphNodes, adopt) {
        const dir = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ii-mic";
        const path = dir + "/" + slot + ".conf";
        // Written and launched in one shell: Quickshell has no file-write API,
        // and a temp file plus a detached child is exactly what this needs.
        chainWriter.command = ["bash", "-c",
            (adopt ? "pgrep -f \"pipewire -c $2\" >/dev/null && { echo adopted; exit 0; }\n" : "")
            + "mkdir -p \"$1\"; cat > \"$2\" <<'EOF'\n" + _chainConf(desc, nodeName, graphNodes, _inputFor(slot))
            + "EOF\n"
            + "pkill -f \"pipewire -c $2\" 2>/dev/null; "
            + "setsid pipewire -c \"$2\" >/dev/null 2>&1 < /dev/null & echo started",
            "sh", dir, path];
        chainWriter.running = true;
        const next = Object.assign({}, root._chains); next[slot] = path; root._chains = next;
    }

    function _stopChain(slot) {
        const path = root._chains[slot];
        if (!path) return;
        chainWriter.command = ["bash", "-c", "pkill -f \"pipewire -c $1\" 2>/dev/null; true", "sh", path];
        chainWriter.running = true;
        const next = Object.assign({}, root._chains); delete next[slot]; root._chains = next;
    }

    /**
     * RNNoise over the selected microphone, exposed as "Mic (denoised)".
     *
     * Control names come from `analyseplugin` on the shipped plugin, not from
     * memory: label `noise_suppressor_mono`, "VAD Threshold (%)" 0-99 default
     * 74.25, plus grace periods and a dry mix.
     */
    function setNoiseSuppression(on) {
        root.noiseSuppression = on;
        Persistent.states.mic.noiseSuppression = on;
        if (!on) { _stopChain("rnnoise"); retargetDelay.restart(); return }
        _startRnnoise();
        retargetDelay.restart();
    }

    function _startRnnoise(adopt) {
        _startChain("rnnoise", "Mic (denoised)", "mic_rnnoise",
            "{ type = ladspa name = rn plugin = /usr/lib/ladspa/librnnoise_ladspa.so "
            + "label = noise_suppressor_mono control = { \"VAD Threshold (%)\" = "
            + Math.round(root.vadThreshold) + " \"VAD Grace Period (ms)\" = 200 } }", adopt);
    }

    function _startHighPass(adopt) {
        _startChain("highpass", "Mic (high-pass)", "mic_hp",
            "{ type = builtin name = hp label = bq_highpass control = { Freq = "
            + Math.round(root.highPassHz) + " Q = 0.707 } }", adopt);
    }

    /**
     * Bring the saved filters back after a login or shell restart.
     *
     * The chains are child processes; nothing restarted them, so after a
     * reboot "Noise suppression" showed ON while no filter existed. This path
     * only starts them: unlike the switches it does NOT retarget apps, because
     * moving a live capture is what crashed Discord's voice engine. Apps keep
     * the device they chose.
     */
    Timer {
        interval: 1500
        running: true
        onTriggered: {
            // Adopt a chain that is still running: a shell reload restarting it
            // made mic_rnnoise vanish and reappear, which Discord does not survive.
            if (root.highPass) root._startHighPass(true);
            if (root.noiseSuppression && root.rnnoiseAvailable) root._startRnnoise(true);
        }
    }

    function setEchoCancel(on) {
        root.echoCancel = on;
        Persistent.states.mic.echoCancel = on;
        if (on) _load("echo", ["module-echo-cancel", "use_master_format=1",
                               "aec_method=webrtc", "source_name=mic_echocancel",
                               "sink_name=mic_echocancel_sink"]);
        else _unload("echo");
    }

    /// Direct monitoring, the way RØDE Central does it: a loopback that
    /// duplicates the capture to the output without altering it.
    function setMonitoring(on) {
        root.monitoring = on;
        if (on) _load("monitor", ["module-loopback", "latency_msec=30",
                                  "source=" + (root.source?.name ?? "@DEFAULT_SOURCE@"),
                                  "sink=@DEFAULT_SINK@",
                                  "source_output_properties=node.name=mic_monitor_in"]);
        else _unload("monitor");
    }

    /**
     * High-pass, as a filter chain over the same mechanism.
     *
     * `bq_highpass` is a builtin, so no plugin is needed — but it still cannot
     * be loaded through pactl; see `_chainConf` above.
     */
    function setHighPass(on) {
        root.highPass = on;
        Persistent.states.mic.highPass = on;
        if (!on) { _stopChain("highpass"); }
        else _startHighPass();
        // The denoiser sits downstream of this, so it has to be rebuilt to read
        // the new stage rather than the bare device.
        if (root.noiseSuppression) root.setNoiseSuppression(true);
        retargetDelay.restart();
    }
}
