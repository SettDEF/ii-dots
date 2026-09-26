pragma Singleton
pragma ComponentBehavior: Bound

// Automations that fire when something about the machine changes.
//
// THE IDEA
//   Not "a switch per device". When the DJ-808 is plugged in you are not
//   toggling a preference — you are starting a session, and that session wants
//   several things at once, on several DIFFERENT devices: the controller takes
//   the output, the NT1's gain goes back to where it belongs, the headset's mic
//   stays off. One arrival, one named setup.
//
//   So the unit here is an automation that reads as a sentence:
//
//       When Roland DJ-808 connects
//         → make it the output
//         → hold RØDE NT1 gain at +20 dB
//         → turn the HDB 630 microphone off
//
//   which is why the panel shows sentences and a history of what actually
//   fired, rather than a grid of switches whose effect you have to imagine.
//
// WHAT IT DELIBERATELY DOES NOT DO
//   WirePlumber already restores a card's profile, volume and routes on replug.
//   Every action below is something it does NOT do, and each one is a thing
//   that actually went wrong on this machine: the default output jumping to
//   whatever else was plugged in, a default SOURCE landing on a muted node that
//   recorded nothing, ALSA mixer gain coming back at the driver default, and no
//   way to say "never send audio here" about a monitor you never listen to.
//
// SIGNALS
//   A trigger is a SIGNAL KEY — a short string naming a condition that is
//   either true right now or not:
//
//       audio:alsa_card.usb-Roland_DJ-808-01   that sound card is present
//       bt:WH-1000XM4                          that Bluetooth device connected
//       monitor:DP-1                           that display is attached
//       power:plugged                          running on mains
//       power:low                              battery below its low mark
//
//   Every kind is collected the same way, into one set, and an automation
//   fires when its key goes from absent to present. Adding a new kind of
//   trigger is adding one line to `signals` — nothing else changes.
//
// IDENTITY
//   Audio keys use the PipeWire CARD NAME (`alsa_card.usb-Roland_DJ-808-01`).
//   That survives a replug and a renumbering; the ALSA index does not — it is 5
//   today and was something else yesterday — so anything touching ALSA resolves
//   the index fresh at the moment it acts, never from storage.
//
// Import with `qs.services`.

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Hyprland

Singleton {
    id: root

    /// Touch this from a Scope that exists at startup.
    ///
    /// QML singletons are created on FIRST REFERENCE, and every reference here
    /// was inside the panel — so nothing watched for a device arriving until
    /// you had opened the menu at least once, which is the one moment you do
    /// not need it. The whole service is a background watcher; it has to be
    /// alive without its UI.
    readonly property bool ready: true

    // ── action vocabulary ───────────────────────────────────────────────
    readonly property var actionKinds: ({
        "claimDefault": { verb: "make it the output",        icon: "speaker",  needs: "output" },
        "micOff":       { verb: "turn its microphone off",   icon: "mic_off",  needs: "mic" },
        "neverDefault": { verb: "never send audio to it",    icon: "block",    needs: "output" },
        "gainLock":     { verb: "hold its input gain",       icon: "tune",     needs: "input" },
        "run":          { verb: "run a command",             icon: "terminal", needs: "any" },
        "displayProfile": { verb: "apply a display profile",  icon: "monitor",  needs: "none" },
        "notify":       { verb: "send a notification",        icon: "notifications", needs: "none" },
        "gameMode":     { verb: "turn game mode on",          icon: "sports_esports", needs: "none" },
        "dnd":          { verb: "silence notifications",      icon: "do_not_disturb_on", needs: "none" },
        "wallpaper":    { verb: "shuffle the wallpaper",      icon: "wallpaper", needs: "none" },
        "routeApp":     { verb: "send an app to it",          icon: "alt_route", needs: "output" },
        "midiConnect":  { verb: "connect its MIDI",           icon: "piano",   needs: "none" },
    })

    // ── the store ───────────────────────────────────────────────────────
    readonly property var _doc: {
        try {
            const d = JSON.parse(Persistent.states.devices.rules)
            return (d && typeof d === "object") ? d : ({})
        } catch (e) {
            console.log("[DeviceRules] store is not valid JSON:", e)
            return ({})
        }
    }
    readonly property var scenes: Array.isArray(root._doc.scenes) ? root._doc.scenes : []

    function _save(scenes) {
        Persistent.states.devices.rules = JSON.stringify({ scenes: scenes })
    }

    function sceneById(id) { return root.scenes.find(s => s?.id === id) ?? null }

    function addScene(scene) {
        const next = root.scenes.slice()
        next.push(scene)
        root._save(next)
    }
    function removeScene(id) { root._save(root.scenes.filter(s => s?.id !== id)) }
    function setSceneEnabled(id, on) {
        root._save(root.scenes.map(s => s?.id === id ? Object.assign({}, s, { enabled: on }) : s))
    }
    function removeAction(id, index) {
        root._save(root.scenes.map(s => {
            if (s?.id !== id) return s
            const acts = (s.actions ?? []).filter((a, i) => i !== index)
            return Object.assign({}, s, { actions: acts })
        }))
    }

    // ── what is here right now ──────────────────────────────────────────
    readonly property var present: {
        AudioProfiles.revision;
        const out = ({})
        for (const k in AudioProfiles.devices) {
            const d = AudioProfiles.devices[k]
            if (d?.name) out[d.name] = d
        }
        return out
    }
    function isHere(cardName) { return root.present[cardName] !== undefined }

    function displayName(cardName) {
        const d = root.present[cardName]
        if (d?.description) return d.description
        // Recover something readable for a device that is not plugged in:
        // `alsa_card.usb-Roland_DJ-808-01` -> `Roland DJ-808`.
        const m = String(cardName).match(/^alsa_card\.usb-(.+?)(-\d+)?$/)
        if (m) return m[1].replace(/_/g, " ").replace(/\s+/g, " ").trim()
        return String(cardName).replace(/^alsa_card\./, "")
    }

    function _internal(dev) { return String(dev?.name ?? "").startsWith("alsa_card.pci") }
    function sinkOf(dev) {
        if (!dev) return null
        const sinks = Audio.outputDevices ?? []
        const byId = sinks.find(n => String(n?.properties?.["device.id"] ?? "") === String(dev.id))
        if (byId) return byId
        // Node properties are empty without a tracker, so `device.id` alone only
        // ever resolved the tracked default. Description needs no tracker.
        const desc = String(dev.description ?? "")
        if (!desc) return null
        return sinks.find(n => {
            const nd = String(n?.description ?? "")
            return nd === desc || nd.startsWith(desc + " ")
        }) ?? null
    }

    function can(cardName, needs) {
        const dev = root.present[cardName]
        if (!dev) return true
        switch (needs) {
            case "output": return dev.canOutput === true
            case "input":  return dev.canInput === true && dev.alsaCard !== null
                                                        && dev.alsaCard !== undefined
            case "mic":    return AudioProfiles.canToggleMic(root.sinkOf(dev))
            default:       return true
        }
    }

    function artFor(cardName) {
        const dev = root.present[cardName]
        if (!dev || (dev.canInput && !dev.canOutput)) return ""
        const sink = root.sinkOf(dev)
        if (!sink) return ""
        const s = AudioLayout.iconFor(sink)
        if ((s === "tablet-audio-symbolic.svg" || s === "laptop-audio-symbolic.svg")
            && !root._internal(dev)) return ""
        return s
    }
    function symbolFor(cardName) {
        const dev = root.present[cardName]
        if (!dev) return "usb_off"
        if (dev.canInput && !dev.canOutput) return "mic"
        const sink = root.sinkOf(dev)
        return sink ? AudioLayout.materialSymbolFor(sink) : "speaker"
    }

    /// One action as a fragment of the sentence its automation reads as.
    ///
    /// `trigger` is the device the automation waits for. An action aimed at
    /// that same device becomes "it"/"its", because otherwise every line
    /// repeats the name already in the heading: "When HDB 630 connects / make
    /// HDB 630 the output, turn the HDB 630 microphone off".
    function phraseFor(action, trigger) {
        const kind = root.actionKinds[action?.type]
        if (!kind) return ""
        const same = trigger !== undefined && action.card === trigger
        const who = action.card ? root.displayName(action.card) : ""
        const db = action.db ?? 20
        switch (action.type) {
            case "gainLock":
                return same ? `hold its gain at ${db} dB` : `hold ${who} gain at ${db} dB`
            case "run":
                return `run ${String(action.command ?? "").slice(0, 40)}`
            case "claimDefault":
                return same ? "make it the output" : `make ${who} the output`
            case "micOff":
                return same ? "turn its microphone off" : `turn the ${who} microphone off`
            case "neverDefault":
                return same ? "never send audio to it" : `never send audio to ${who}`
            case "displayProfile":
                return `apply the ${action.profile} display profile`
            case "routeApp":
                return same ? `send ${action.app} to it` : `send ${action.app} to ${who}`
            case "midiConnect":
                return `connect MIDI ${action.from} → ${action.to}`
            case "notify":
                return `say "${String(action.message ?? "").slice(0, 32)}"`
        }
        return kind.verb
    }

    // ── signals: every condition that can trigger something ─────────────
    /// The set of signal keys true RIGHT NOW. One place, every kind, so the
    /// firing logic below never has to know what a Bluetooth device is.
    readonly property var signals: {
        AudioProfiles.revision;
        const out = ({})
        for (const name in root.present) out["audio:" + name] = true
        for (const d of (BluetoothStatus.connectedDevices ?? []))
            if (d?.name) out["bt:" + d.name] = true
        for (const m of (Hyprland.monitors?.values ?? []))
            if (m?.name) out["monitor:" + m.name] = true
        if (Battery.available) {
            if (Battery.isPluggedIn) out["power:plugged"] = true
            if (Battery.isLow) out["power:low"] = true
        }
        // The desktop is context too, and the useful kind: what you are DOING
        // is a better trigger than what you have plugged in. A game starting is
        // the clearest example — it is the moment you want the headset taken
        // over, notifications silenced and the wallpaper left alone.
        if (GameMode.gameRunning) out["desktop:game"] = true
        if (Notifications.silent) out["desktop:dnd"] = true
        // A dock is ONE event, not eight. When the Dell dock dropped it took
        // four audio devices and the ethernet with it, and as per-device
        // signals that is eight history lines and eight rules racing each
        // other. The enclosure itself is the honest unit.
        for (const d of root._docks) out["dock:" + d] = true
        return out
    }

    /// Thunderbolt enclosures currently attached, by their own name.
    property var _docks: []
    Process {
        id: dockProbe
        command: ["sh", "-c",
            "cat /sys/bus/thunderbolt/devices/*/device_name 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = text.split("\n").map(l => l.trim()).filter(l => l.length > 0)
                // Assign only on a real change: `signals` depends on this, and
                // reassigning an equal array would re-run the whole sweep every
                // few seconds.
                if (JSON.stringify(found) !== JSON.stringify(root._docks))
                    root._docks = found
            }
        }
    }
    Timer {
        // Cheap: a cat of a few sysfs files. The kernel gives no signal we can
        // watch from here without a udev listener, and a dock arriving is not
        // something that needs sub-second latency.
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!dockProbe.running) dockProbe.running = true
    }

    function signalKind(key) { return String(key).split(":")[0] }
    function signalArg(key)  { return String(key).slice(String(key).indexOf(":") + 1) }
    function isLive(key) { return root.signals[key] === true }

    /// What a trigger is CALLED, and how it reads as the opening of a sentence.
    function signalLabel(key) {
        const arg = root.signalArg(key)
        switch (root.signalKind(key)) {
            case "audio":   return root.displayName(arg)
            case "bt":      return arg
            case "monitor": return arg
            case "power":   return arg === "plugged" ? Translation.tr("power is plugged in")
                                                     : Translation.tr("the battery gets low")
            case "desktop": return arg === "game" ? Translation.tr("a game is running")
                                                  : Translation.tr("notifications are silenced")
            case "dock":    return arg
        }
        return key
    }
    /// The heading verb for a rule, which depends on which edge it watches.
    function edgeVerb(key, edge) {
        const k = root.signalKind(key)
        if (k === "power" || k === "desktop") return edge === "leave" ? Translation.tr("stops") : ""
        return edge === "leave" ? Translation.tr("disconnects") : Translation.tr("connects")
    }

    function signalVerb(key) {
        // Power reads as a state, everything else as an arrival.
        // Only a device ARRIVES; a state simply becomes true.
        const k = root.signalKind(key)
        return (k === "power" || k === "desktop") ? "" : Translation.tr("connects")
    }
    /// The same event written as history rather than as a condition.
    function signalPast(key, arrived) {
        const k = root.signalKind(key)
        if (k === "power" || k === "desktop")
            return root.signalLabel(key) + (arrived ? "" : Translation.tr(" — no longer"))
        return root.signalLabel(key) + " "
             + (arrived ? Translation.tr("connected") : Translation.tr("disconnected"))
    }
    function signalIcon(key) {
        switch (root.signalKind(key)) {
            case "audio":   return root.symbolFor(root.signalArg(key))
            case "bt":      return "bluetooth"
            case "monitor": return "monitor"
            case "power":   return root.signalArg(key) === "low" ? "battery_alert" : "power"
            case "desktop": return root.signalArg(key) === "game" ? "sports_esports" : "do_not_disturb_on"
            case "dock":    return "dock"
        }
        return "bolt"
    }
    /// Only audio cards have bespoke artwork; the rest use a symbol.
    function signalArt(key) {
        return root.signalKind(key) === "audio" ? root.artFor(root.signalArg(key)) : ""
    }

    // ── suggestions, so the panel is never an empty form ────────────────
    /// Built from what is ACTUALLY true of this machine right now, so every
    /// suggestion is one the hardware can carry out today.
    readonly property var suggestions: {
        const out = []
        const taken = ({})
        for (const s of root.scenes) if (s?.when) taken[s.when] = true

        for (const key in root.signals) {
            if (taken[key]) continue
            const kind = root.signalKind(key)
            const arg = root.signalArg(key)
            const actions = []

            if (kind === "audio") {
                const dev = root.present[arg]
                if (!dev || root._internal(dev)) continue
                if (dev.canOutput) actions.push({ type: "claimDefault", card: arg })
                if (root.can(arg, "mic")) actions.push({ type: "micOff", card: arg })
                if (root.can(arg, "input") && !dev.canOutput)
                    actions.push({ type: "gainLock", card: arg, control: "Mic", db: 20 })
            } else if (kind === "monitor") {
                // Only worth offering when there is a profile to apply.
                const names = Object.keys(DisplayProfiles.profiles ?? ({}))
                if (names.length === 0) continue
                actions.push({ type: "displayProfile", profile: names[0] })
            } else if (kind === "bt") {
                actions.push({ type: "notify", message: `${arg} connected` })
            } else if (kind === "desktop" && arg === "game") {
                actions.push({ type: "dnd" })
            } else {
                continue   // power states are useful, but not worth guessing at
            }

            if (actions.length === 0) continue
            out.push({ when: key, name: root.signalLabel(key), actions: actions })
        }
        return out
    }

    function acceptSuggestion(s) {
        root.addScene({
            id: "s" + String(Object.keys(root.signals).length) + String(root.scenes.length),
            name: s.name,
            when: s.when,
            enabled: true,
            actions: s.actions,
        })
    }

    // ── history: what actually fired ────────────────────────────────────
    /// Session-only, newest first. The panel's whole claim is "this happens on
    /// its own", and a claim like that is worth nothing without a receipt —
    /// the dock dropped twice today and from the desktop's side devices simply
    /// vanished with no explanation anywhere.
    property var history: []
    function _note(text) {
        const next = root.history.slice()
        next.unshift({ at: Date.now(), text: text })
        root.history = next.slice(0, 12)
    }

    // ── drift: where the machine has wandered off ───────────────────────
    //
    // Applying on connect is not enough, and the NT1 proved it: nothing was
    // unplugged and its gain had still drifted from the 20 dB it was set to up
    // to 32 dB. A rule that only runs on arrival cannot notice that, so this
    // compares what each live rule ASKED FOR against what is actually true now.
    //
    // Only checks things that are cheap and unambiguous to read back. An action
    // whose result cannot be observed (running a command) is not drift-checked,
    // because "did it work?" has no answer we could honestly give.

    /// `card|control` -> dB actually set, from amixer.
    property var gainActual: ({})

    readonly property var drift: {
        root.gainActual;
        AudioProfiles.revision;
        const out = []
        for (const sc of root.scenes) {
            if (sc?.enabled === false) continue
            if ((sc.edge ?? "arrive") !== "arrive") continue
            if (!root.isLive(sc.when)) continue
            for (const a of (sc.actions ?? [])) {
                const dev = a?.card ? root.present[a.card] : null
                // NOTE: `claimDefault` is deliberately NOT drift-checked. It
                // says "make it the output WHEN IT CONNECTS" — a claim made
                // once at arrival, not a promise to stay there. Treating it as
                // an invariant made the panel nag permanently the moment you
                // picked a different output by hand, contradicting the wording
                // of the action itself. Only actions phrased as "keep"/"hold"
                // are invariants, and only those are checked.
                if (a?.type === "micOff") {
                    const sink = root.sinkOf(dev)
                    if (sink && AudioProfiles.micEnabled(sink))
                        out.push({ scene: sc.id, action: a,
                                   what: Translation.tr("%1 microphone is on").arg(root.displayName(a.card)) })
                } else if (a?.type === "gainLock") {
                    const got = root.gainActual[a.card + "|" + (a.control ?? "Mic")]
                    if (got !== undefined && Math.abs(got - Number(a.db ?? 20)) > 0.6)
                        out.push({ scene: sc.id, action: a,
                                   what: Translation.tr("%1 gain is %2 dB, not %3")
                                            .arg(root.displayName(a.card)).arg(got).arg(a.db ?? 20) })
                }
            }
        }
        return out
    }

    function fixDrift() { for (const d of root.drift) root._act(d.action) }

    /// Read back every gain a live rule cares about. Driven by a timer rather
    /// than a watcher because ALSA mixer state has no change notification we
    /// can subscribe to from here.
    property var _gainQueue: []
    function checkGains() {
        const want = []
        for (const sc of root.scenes) {
            if (sc?.enabled === false) continue
            for (const a of (sc.actions ?? [])) {
                if (a?.type !== "gainLock") continue
                const dev = root.present[a.card]
                if (!dev || dev.alsaCard === null || dev.alsaCard === undefined) continue
                want.push({ card: a.card, alsa: dev.alsaCard, control: String(a.control ?? "Mic") })
            }
        }
        if (want.length === 0) return
        root._gainQueue = want
        root._nextGain()
    }
    function _nextGain() {
        if (root._gainQueue.length === 0) return
        const j = root._gainQueue[0]
        gainRead.command = ["amixer", "-c", String(j.alsa), "sget", j.control]
        gainRead.running = true
    }
    Process {
        id: gainRead
        stdout: StdioCollector {
            onStreamFinished: {
                const j = root._gainQueue[0]
                root._gainQueue = root._gainQueue.slice(1)
                if (j) {
                    const m = text.match(/\[(-?[0-9.]+)dB\]/)
                    if (m) {
                        const next = Object.assign({}, root.gainActual)
                        next[j.card + "|" + j.control] = parseFloat(m[1])
                        root.gainActual = next
                    }
                }
                root._nextGain()
            }
        }
    }
    Timer {
        interval: 20000
        running: root.scenes.length > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.checkGains()
    }

    // ── firing ──────────────────────────────────────────────────────────
    property var _seen: ({})
    property bool _armed: false

    onSignalsChanged: root._sweep()

    /// Arms only once the world is actually loaded, then waits a moment more.
    ///
    /// The first version armed on the first `signals` change, which looked
    /// equivalent and was not: `AudioProfiles` fills in asynchronously from
    /// `pw-dump`, so on a reload the first sweep could run against a world with
    /// NO sound cards in it. It armed on that empty set, every card then looked
    /// like it had just been plugged in, and any rule with `claimDefault` stole
    /// the default output. It is a race, so it only bit on some reloads — which
    /// is worse than always, because it looks like the desktop moving on its
    /// own. The extra delay covers Bluetooth and monitors, which populate a
    /// beat later than audio and would otherwise look like fresh arrivals too.
    Timer {
        id: _armTimer
        interval: 2500
        running: AudioProfiles.loaded && !root._armed
        repeat: false
        onTriggered: {
            root._seen = Object.assign({}, root.signals)
            root._armed = true
        }
    }

    function _sweep() {
        // Arming is the timer's job, not this function's — see _armTimer. Until
        // it has run, nothing counts as an arrival and nothing fires.
        if (!root._armed) return
        const now = root.signals
        for (const key in now) {
            if (root._seen[key]) continue
            root._note(root.signalPast(key, true))
            root.runFor(key, "arrive")
        }
        for (const old in root._seen) {
            if (now[old]) continue
            const k = root.signalKind(old)
            if (k !== "power" && k !== "desktop") root._note(root.signalPast(old, false))
            // The other half of the story. Something LEAVING is what actually
            // hurt here: the dock dropped, the output fell back to whatever was
            // left, and the default source landed on a muted node. A rule that
            // can only react to arrival cannot put that right.
            root.runFor(old, "leave")
        }
        root._seen = Object.assign({}, now)
    }

    /// Every enabled automation waiting on this signal, at this edge.
    function runFor(key, edge) {
        for (const s of root.scenes)
            if (s?.when === key && s?.enabled !== false
                && (s.edge ?? "arrive") === edge) root.run(s.id)
    }

    function setEdge(id, edge) {
        root._save(root.scenes.map(s =>
            s?.id === id ? Object.assign({}, s, { edge: edge }) : s))
    }

    function run(id) {
        const s = root.sceneById(id)
        if (!s) return
        // A rule that claims the default output is a blunt instrument without
        // this — you end up switching the whole thing off rather than working
        // out why it fired during a game.
        const blocked = (s.unless ?? []).find(k => root.isLive(k))
        if (blocked) {
            root._note(`${s.name}: held back — ${root.signalLabel(blocked)}`)
            return
        }
        let done = 0
        for (const a of (s.actions ?? [])) if (root._act(a)) done++
        // Logged as well as noted: when an automation moves something the user
        // did not expect, the in-memory history is invisible from outside and
        // there was no way to tell whether a rule had fired at all.
        console.log("[DeviceRules] ran", s.name, "->", done, "of",
                    (s.actions ?? []).length, "actions")
        root._note(`${s.name}: ${done} of ${(s.actions ?? []).length} applied`)
    }

    function setUnless(id, keys) {
        root._save(root.scenes.map(s =>
            s?.id === id ? Object.assign({}, s, { unless: keys }) : s))
    }

    /// Conditions worth offering: states, not arrivals — "unless a game is
    /// running" is meaningful, "unless the DJ-808 is plugged in" rarely is.
    readonly property var conditionKeys: {
        const out = []
        for (const key in root.signals) {
            const k = root.signalKind(key)
            if (k === "desktop" || k === "power") out.push(key)
        }
        return out
    }

    function _act(a) {
        const dev = a?.card ? root.present[a.card] : null
        switch (a?.type) {
            case "run":
                if (!a.command) return false
                runner.exec(["sh", "-c", String(a.command)])
                return true
            case "claimDefault": {
                const sink = root.sinkOf(dev)
                if (!sink) return false
                Audio.setDefaultSink(sink); return true
            }
            case "micOff": {
                const sink = root.sinkOf(dev)
                if (!sink) return false
                if (AudioProfiles.micEnabled(sink)) AudioProfiles.setMicEnabled(sink, false)
                return true
            }
            case "neverDefault": {
                const sink = root.sinkOf(dev)
                if (!sink || Audio.sink !== sink) return false
                const other = (Audio.outputDevices ?? []).find(n =>
                    n !== sink && AudioProfiles.isHardware(n))
                if (other) { Audio.setDefaultSink(other); return true }
                return false
            }
            case "routeApp": {
                // Same mechanism the audio panel's route sheet uses: a stream
                // follows `target.object`, so routing is metadata on the node
                // rather than anything moved in the graph.
                const sink = root.sinkOf(dev)
                if (!sink || !a.app) return false
                const want = String(a.app).toLowerCase()
                const node = (Audio.outputAppNodes ?? []).find(n =>
                    String(Audio.appNodeDisplayName(n) ?? "").toLowerCase().includes(want))
                if (!node) return false
                runner.exec(["pw-metadata", String(node.id), "target.object", String(sink.name)])
                return true
            }
            case "midiConnect": {
                // ALSA sequencer links do not survive a replug — the client
                // number changes every time — which is why this is worth
                // automating for a controller at all. aconnect takes the client
                // NAME, so it re-resolves on its own.
                if (!a.from || !a.to) return false
                midiProc.exec(["aconnect", String(a.from), String(a.to)])
                return true
            }
            case "gameMode":
                if (!GameMode.active) GameMode.toggle()
                return true
            case "dnd":
                Notifications.silent = true
                return true
            case "wallpaper":
                Wallpapers.randomFromCurrentFolder()
                return true
            case "displayProfile":
                if (!a.profile) return false
                DisplayProfiles.apply(String(a.profile))
                return true
            case "notify":
                if (!a.message) return false
                runner.exec(["notify-send", "-a", "Automations", String(a.message)])
                return true
            case "gainLock": {
                // Index read LIVE every time. Storing it is the bug this whole
                // service exists to avoid: card 5 today, card 2 after the next
                // dock reset, and `amixer -c 5` would then be setting somebody
                // else's hardware.
                const card = dev?.alsaCard
                if (card === null || card === undefined) return false
                const db = Number(a.db)
                if (!isFinite(db)) return false
                // ONE OWNER. The Mic service runs its own watchdog over the
                // capture gain and re-applies whatever it has stored, so
                // writing the mixer directly behind its back means the two
                // fight: this sets 20, the watchdog notices a 12 dB difference
                // and puts 32 back, forever. When the target IS its card, go
                // through it and let it enforce the new number instead.
                if (Mic.cardIndex === card) { Mic.setGainDb(db); return true }
                gainProc.exec(["amixer", "-c", String(card), "sset",
                               String(a.control ?? "Mic"), `${db}dB`])
                return true
            }
        }
        return false
    }

    Process { id: runner }
    Process { id: midiProc }
    Process { id: gainProc }
}
