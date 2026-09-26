pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Bluetooth
import qs.modules.common
import qs.modules.common.functions
import QtQuick

/**
 * One list of the user's devices, whatever they are attached by, with a battery
 * for each where one can be got at all.
 *
 * WHY THIS EXISTS
 * The panels here were built around Bluetooth, so a speaker on a USB-C cable was
 * not a device as far as the UI was concerned - it drops its Bluetooth link when
 * plugged in and vanished from the list at the moment it was most in use.
 * Transport is a detail of how a device is reachable, not what it is, so it
 * belongs in a field rather than in which panel you have to go and look at.
 *
 * Rows are plain objects, not wrappers, so a delegate can still reach the
 * underlying BluetoothDevice (for connect/disconnect) or PwNode (for volume).
 *
 * BATTERY PROVIDERS
 * BlueZ publishes org.bluez.Battery1 only for devices that speak a profile
 * carrying one. Plenty do not: the JBL Xtreme 5 has no GATT Battery Service, no
 * HFP, and nothing in its Fast Pair advert, so BlueZ will never have a number
 * for it however long you wait - it exists only behind the vendor's own control
 * protocol. That is not special to one speaker, so `providers` below is a
 * registry rather than one device's special case. Adding a vendor means adding
 * an entry and a binary that prints {"ok":true,"percent":N}; nothing else here
 * changes.
 */
Singleton {
    id: root

    // ---- Battery providers ----------------------------------------------

    // Where the helper binaries live. Plain constant on purpose - easy to point
    // somewhere else without going hunting through the code.
    readonly property string home: FileUtils.trimFileProtocol(Directories.home)
    readonly property string binDir:
        FileUtils.trimFileProtocol(`${Directories.home}/.local/bin`)

    /**
     *   id           stable key for results
     *   names        BlueZ device names this provider can answer for
     *   nodeMatches  substrings of a PipeWire node.name identifying the same
     *                device on USB. node.name is populated without a
     *                PwObjectTracker, which node.properties is not, so the match
     *                is deliberately on the name.
     *   command      argv printing {"ok":bool,"percent":int,...} on stdout
     *   intervalMs   background poll period while the device is present
     */
    readonly property var providers: [
        {
            id: "harman-jbl",
            label: "JBL / Harman",
            names: ["JBL Xtreme 5"],
            nodeMatches: ["Harman_JBL_Xtreme"],
            command: [root.binDir + "/jbl-battery", "once"],
            intervalMs: 240000,
            // Optional: helpers for the device's own settings, one per group.
            // Each prints {"ok":..,"<group>":{..}} and takes `set key=value`
            // arguments. A provider with no entry for a group simply offers no
            // controls for it.
            featureCommands: {
                "lights": [root.binDir + "/jbl-battery", "lights"],
                "eq":     [root.binDir + "/jbl-battery", "eq"]
            }
        }
    ]

    // id -> { percent, firmware, error }. Reassigned wholesale on every change:
    // mutating a plain object in place does not notify bindings.
    property var batteryResults: ({})
    property int busyCount: 0

    /// True while some provider is mid-query, so a panel can show that a number
    /// is being fetched rather than looking stuck.
    readonly property bool busy: root.busyCount > 0

    function providerForName(name) {
        const n = String(name ?? "")
        if (n.length === 0) return null
        return root.providers.find(p => p.names.indexOf(n) !== -1) ?? null
    }

    function hasProvider(name) { return root.providerForName(name) !== null }

    function providerPercent(name) {
        const p = root.providerForName(name)
        if (!p) return -1
        const r = root.batteryResults[p.id]
        return (r && typeof r.percent === "number") ? r.percent : -1
    }

    function firmwareFor(name) {
        const p = root.providerForName(name)
        return (p ? root.batteryResults[p.id]?.firmware : "") ?? ""
    }

    /// Attached over USB. Keeps a device polled whose Bluetooth link dropped
    /// precisely because the cable went in.
    function _usbAttached(provider) {
        return Pipewire.nodes.values.some(n => {
            const name = String(n?.name ?? "")
            return provider.nodeMatches.some(m => name.indexOf(m) !== -1)
        })
    }
    function _btAttached(provider) {
        return BluetoothStatus.connectedDevices.some(d =>
            provider.names.indexOf(d?.name ?? "") !== -1)
    }
    function _present(provider) {
        return root._btAttached(provider) || root._usbAttached(provider)
    }

    /// Ask every provider whose device is present to refresh. A reading costs a
    /// radio round trip, so panels call this when they become visible, which is
    /// when a fresh number is actually worth paying for.
    function refresh(force) {
        for (let i = 0; i < pollers.count; i++)
            pollers.objectAt(i)?.poll(force === true)
    }

    function _store(id, obj) {
        const next = Object.assign({}, root.batteryResults)
        next[id] = obj
        root.batteryResults = next
    }

    // Seed from the last reading on disk.
    //
    // Every consumer of this service lives in a lazily-loaded panel, so the
    // service is not even constructed until one is opened - and the first poll is
    // a radio round trip away. Without this a panel showed no battery at all for
    // several seconds, which reads as "it does not work" rather than "it is
    // fetching". The helper writes this file on every successful reading.
    FileView {
        id: lastReading
        // ~/.cache/jbl-battery, where the helper writes it. NOT Directories.cache -
        // that is CacheLocation, which on Linux is ~/.cache/<app> (i.e.
        // ~/.cache/quickshell), and the helper is not a quickshell component.
        path: Qt.resolvedUrl(`file://${root.home}/.cache/jbl-battery/last.json`)
        onLoaded: {
            try {
                const r = JSON.parse(lastReading.text() || "{}")
                if (r && r.ok && typeof r.percent === "number" && root.providers.length > 0) {
                    // Only seeds the provider it belongs to; a name mismatch means
                    // a stale file from another device and is ignored.
                    const p = root.providerForName(r.name)
                    if (p) root._store(p.id, { percent: r.percent, firmware: r.firmware ?? "", error: "" })
                }
            } catch (e) {
                // A corrupt cache is not worth taking the shell down for.
            }
        }
        Component.onCompleted: reload()
    }

    Instantiator {
        id: pollers
        model: root.providers
        delegate: QtObject {
            id: poller
            required property var modelData
            readonly property var provider: modelData
            readonly property bool present: root._present(poller.provider)
            property double lastUpdate: 0
            property bool running: false

            function poll(force) {
                if (poller.running || !poller.present) return
                const age = Date.now() - poller.lastUpdate
                if (!force && poller.lastUpdate > 0 && age < poller.provider.intervalMs) return
                poller.running = true
                root.busyCount++
                poller.proc.running = true
            }

            // Drop a stale reading when the device goes away, so a panel does not
            // show a number for something no longer attached.
            onPresentChanged: {
                if (poller.present) {
                    poller.poll(true)
                } else {
                    poller.lastUpdate = 0
                    root._store(poller.provider.id, { percent: -1, firmware: "", error: "" })
                }
            }

            property Process proc: Process {
                command: poller.provider.command
                stdout: StdioCollector {
                    onStreamFinished: {
                        let r = null
                        try { r = JSON.parse(text.trim()) } catch (e) { r = null }
                        if (r && r.ok) {
                            poller.lastUpdate = Date.now()
                            root._store(poller.provider.id, {
                                percent: r.percent, firmware: r.firmware ?? "", error: ""
                            })
                        } else {
                            // Keep the last good value. Failures are routine: a
                            // rotating BLE address means a query can simply miss.
                            const prev = root.batteryResults[poller.provider.id] ?? {}
                            root._store(poller.provider.id, Object.assign({}, prev, {
                                error: (r && r.error) ? r.error : "unparseable output"
                            }))
                        }
                    }
                }
                onExited: {
                    poller.running = false
                    root.busyCount = Math.max(0, root.busyCount - 1)
                }
            }

            property Timer timer: Timer {
                interval: poller.provider.intervalMs
                repeat: true
                running: poller.present
                triggeredOnStart: true
                onTriggered: poller.poll(false)
            }
        }
    }

    // ---- Classification --------------------------------------------------
    function kindOf(iconHint) {
        const i = String(iconHint ?? "").toLowerCase()
        if (i.includes("mouse"))    return "mouse"
        if (i.includes("keyboard")) return "keyboard"
        if (i.includes("phone"))    return "phone"
        if (i.includes("audio") || i.includes("headset")
            || i.includes("headphone") || i.includes("speaker")) return "audio"
        return "generic"
    }
    function iconFor(kind, transport) {
        switch (kind) {
            case "mouse":    return "mouse"
            case "keyboard": return "keyboard"
            case "phone":    return "phone_iphone"
            case "audio":    return "headphones"
        }
        return transport === "usb" ? "usb" : "bluetooth"
    }

    /// What a device physically IS: "speaker" | "headphones" | "headset" |
    /// "earbuds" | "". From BlueZ rather than PipeWire, which publishes the bus
    /// and not the form factor. BlueZ derives its icon from the Class of
    /// Device - minor 1/2 headset, 6 headphones, 5 and 7 both "audio-card" -
    /// so the answer is about the device, not about today's cable.
    function audioFormFactorFor(name) {
        const d = root.btDeviceByName(name)
        if (!d) return ""
        const i = String(d.icon ?? "").toLowerCase()
        if (i.includes("headset")) return "headset"
        if (i.includes("headphone")) return "headphones"
        if (i.includes("earbud") || i.includes("earphone")) return "earbuds"
        if (i.includes("speaker") || i.includes("audio-card")) return "speaker"
        return ""
    }

    // ---- Bluetooth -------------------------------------------------------
    readonly property var btRows: BluetoothStatus.connectedDevices.map(d => {
        const name = d?.name ?? "?"
        const bat = (d?.batteryAvailable ?? false)
            ? Math.round((d?.battery ?? 0) * 100)
            : root.providerPercent(name)
        return {
            key: "bt:" + (d?.address ?? name),
            name: name,
            kind: root.kindOf(d?.icon),
            transport: "bluetooth",
            battery: bat,
            batteryFromProvider: !(d?.batteryAvailable ?? false) && bat >= 0,
            device: d,
            node: null
        }
    })

    // ---- USB audio -------------------------------------------------------
    // A card shows up as separate output and input nodes; both carry the same
    // "usb-<vendor>_<model>_<serial>" segment, which identifies the physical
    // device. Group on that so one speaker is one row.
    function _usbKey(nodeName) {
        const m = String(nodeName ?? "").match(/^alsa_(?:output|input)\.(usb-[^.]+)\./)
        return m ? m[1] : ""
    }

    readonly property var usbNodes: Pipewire.nodes.values.filter(n => root._usbKey(n?.name) !== "")

    // NO PwObjectTracker here, deliberately.
    //
    // Tracking these nodes populates node.description - but it also writes back
    // into the PipeWire objects, which changes Pipewire.nodes, which re-runs the
    // usbNodes filter, which hands the tracker a NEW array to track. Each half is
    // cheap alone (measured: 11.3s startup either way) and together they cost 7
    // seconds of startup and kept re-running afterwards (18.5s).
    //
    // The name is derived from node.name instead, which is populated without any
    // tracker. Slightly less pretty than the description, and it costs nothing.

    readonly property var usbRows: {
        const byKey = ({})
        for (const n of root.usbNodes) {
            const k = root._usbKey(n.name)
            if (!k || byKey[k]) continue
            // node.name is populated without a tracker; node.description is not.
            const desc = ""
            // Fallback for an untracked node: turn the sysfs-ish id back into
            // something readable, e.g. "usb-Harman_JBL_Xtreme_5_GG1533-01".
            const fallback = k.replace(/^usb-/, "").replace(/_/g, " ").replace(/-\d+$/, "")
            const name = desc.length > 0 ? desc : fallback
            const bat = root.providerPercent(name)
            byKey[k] = {
                key: "usb:" + k,
                name: name,
                kind: root.kindOf(name + " audio"),
                transport: "usb",
                battery: bat,
                batteryFromProvider: bat >= 0,
                device: null,
                node: n
            }
        }
        return Object.keys(byKey).map(k => byKey[k])
    }

    // ---- Combined --------------------------------------------------------
    // A speaker that is paired but currently on its cable still belongs here;
    // it is the same device, just reachable a different way. Matched by name so
    // one physical thing never appears twice.
    readonly property var pairedOnUsb: BluetoothStatus.pairedButNotConnectedDevices.filter(d =>
        root.usbRows.some(u => u.name.indexOf(d?.name ?? " ") !== -1
                            || (d?.name ?? "").indexOf(u.name) !== -1))

    readonly property var rows: {
        const out = root.btRows.slice()
        for (const u of root.usbRows) {
            if (out.some(r => r.name === u.name)) continue
            // Prefer the paired BluetoothDevice when we have one, so the row
            // keeps its real name and its per-type controls still work.
            const paired = root.pairedOnUsb.find(d =>
                u.name.indexOf(d?.name ?? " ") !== -1 || (d?.name ?? "").indexOf(u.name) !== -1)
            out.push(paired
                ? Object.assign({}, u, { name: paired.name, device: paired,
                                         kind: root.kindOf(paired.icon) })
                : u)
        }
        return out
    }

    readonly property int count: root.rows.length

    /// Short line for a tile: the first device, plus how many more.
    readonly property string summary: {
        const n = root.rows.length
        if (n === 0) return Translation.tr("No devices")
        const first = root.rows[0].name
        return n === 1 ? first : Translation.tr("%1 +%2").arg(first).arg(n - 1)
    }

    /// The most interesting battery for a compact tile: the lowest known.
    readonly property int lowestBattery: {
        let best = -1
        for (const r of root.rows)
            if (r.battery >= 0 && (best < 0 || r.battery < best)) best = r.battery
        return best
    }

    // ---- Capabilities ----------------------------------------------------
    //
    // What extra controls a given device actually has, as DATA. The alternative
    // is a chain of `if (name === ...)` in the UI, which is how you end up with a
    // panel that works for one speaker and shows an empty box for everything
    // else.
    //
    // A group is { id, label, icon }. The UI shows a control button when this is
    // non-empty and renders one section per group, so adding support for a new
    // device is a new entry here plus one section - no UI surgery.
    //
    // Every device gets at least "info", so the button is never a dead end.

    /// Vendor-specific control groups, keyed by BlueZ device name. Battery is not
    /// listed: it is shown inline on the row itself, not as a control.
    readonly property var vendorControls: ({
        "JBL Xtreme 5": [
            { id: "lights", label: "Lights", icon: "lightbulb" },
            { id: "eq",     label: "Equaliser", icon: "graphic_eq" }
        ]
    })

    function capabilitiesFor(name) {
        const out = []
        const r = root.rows.find(x => x.name === name)
        const kind = r ? r.kind : ""
        const bt = root.btDeviceByName(name)

        // Anything PipeWire can see has a volume worth exposing.
        // r.node, not "it is an audio device": a paired speaker with no live
        // PipeWire node has no volume to set, and a slider that moves nothing
        // is worse than no slider.
        if (r && r.node !== null)
            out.push({ id: "volume", label: Translation.tr("Volume"), icon: "volume_up" })

        // The card profile is where the A2DP-vs-headset tradeoff lives, and it
        // is the one control EVERY Bluetooth audio device has. Offered whenever
        // PulseAudio actually has a card for it, so it never shows an empty box.
        if (bt && root.cardFor(bt.address))
            out.push({ id: "profile", label: Translation.tr("Audio profile"), icon: "hearing" })

        // Pointer settings come from solaar/LogiTune, so only offer them when
        // something can actually answer.
        if (kind === "mouse")
            out.push({ id: "pointer", label: Translation.tr("Pointer"), icon: "mouse" })

        for (const g of (root.vendorControls[name] ?? []))
            out.push({ id: g.id, label: Translation.tr(g.label), icon: g.icon })

        // Connect / trust / forget. Universal, which is the point: a paired
        // keyboard with no battery provider and no audio card still opens a
        // dialog that can do something.
        if (bt)
            out.push({ id: "connection", label: Translation.tr("Connection"), icon: "bluetooth" })

        out.push({ id: "info", label: Translation.tr("Info"), icon: "info" })
        return out
    }

    /// Groups that exist for every device and so prove nothing about whether
    /// this one is worth a button: info is always there, and connect/forget is
    /// already on the row itself.
    readonly property var passiveGroups: ["info", "connection"]

    /// True only when the device has a control that actually does something -
    /// a volume, a card profile, pointer settings, or a vendor feature. A row
    /// with nothing to offer gets no button rather than a dialog of apologies.
    function hasControls(name) {
        return root.capabilitiesFor(name).some(g => root.passiveGroups.indexOf(g.id) < 0)
    }

    /// The BluetoothDevice behind a row name, connected or merely paired.
    function btDeviceByName(name) {
        if (!name) return null
        return Bluetooth.devices.values.find(d => d.name === name) ?? null
    }

    // ---- Vendor feature channel ------------------------------------------
    // These settings live behind the speaker's BLE control service, and it
    // refuses an LE link while a classic one is up (verified on hardware; the
    // classic channel speaks Fast Pair, not this protocol). So they are live
    // exactly when the speaker is OFF Bluetooth - on USB-C, or idle.
    //
    // One channel, not one per feature: it is one radio link that accepts one
    // occupant, so requests queue and go out in turn.

    /// "<providerId>:<group>" -> whatever the helper printed.
    property var featureResults: ({})

    function _featureKey(providerId, group) { return providerId + ":" + group }

    function featureCommand(name, group) {
        const p = root.providerForName(name)
        const c = p?.featureCommands?.[group]
        return c ? { provider: p, command: c } : null
    }

    /// True when this device has a helper for that group at all - which is what
    /// decides whether a panel offers the section.
    function hasFeature(name, group) {
        return root.featureCommand(name, group) !== null
    }

    /// The last reply, or null if nothing has been read yet.
    function featureData(name, group) {
        const f = root.featureCommand(name, group)
        if (!f) return null
        return root.featureResults[root._featureKey(f.provider.id, group)] ?? null
    }

    /// The group's payload, or null when the last read did not succeed. Panels
    /// use this to decide between showing controls and explaining why not.
    function featureValues(name, group) {
        const d = root.featureData(name, group)
        return (d && d.ok) ? (d[group] ?? null) : null
    }

    /// Derived from the queue and the process, never a flag kept beside them:
    /// kept by hand it deadlocked, because a flag left set made every later
    /// call return early, so nothing ever arrived to clear it.
    function featureBusy(name, group) {
        const f = root.featureCommand(name, group)
        if (!f) return false
        const key = root._featureKey(f.provider.id, group)
        if (featureProc.running && featureProc.key === key) return true
        return root._queue.some(q => q.key === key)
    }

    property var _queue: []

    /// Read a group. `extra` is how a write happens: ["set", "brightness=60"].
    /// Both paths end in the same reread, so a panel never guesses.
    function refreshFeature(name, group, extra) {
        const f = root.featureCommand(name, group)
        if (!f) return
        const key = root._featureKey(f.provider.id, group)
        const args = extra ?? []
        // A queued reread is the same request twice; a write is not.
        if (args.length === 0 && root.featureBusy(name, group)) return
        root._queue = root._queue.concat([{ key: key, command: f.command.concat(args) }])
        root._pump()
    }

    function setFeature(name, group, key, value) {
        root.refreshFeature(name, group, ["set", key + "=" + value])
    }

    function _pump() {
        if (featureProc.running || root._queue.length === 0) return
        const next = root._queue[0]
        root._queue = root._queue.slice(1)
        featureProc.key = next.key
        featureProc.command = next.command
        featureProc.running = true
    }

    Process {
        id: featureProc
        property string key: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const next = Object.assign({}, root.featureResults)
                try {
                    next[featureProc.key] = JSON.parse(text.trim() || "{}")
                } catch (e) {
                    next[featureProc.key] = { ok: false, error: "unreadable reply" }
                }
                root.featureResults = next
            }
        }
        onRunningChanged: if (!running) root._pump()
    }

    // ---- PulseAudio card profiles ----------------------------------------
    // Here, not in Audio.qml: a card is a property of the DEVICE, deciding
    // whether it is a high-fidelity sink or a telephone. Keyed by address with
    // colons as underscores - how PulseAudio names it: bluez_card.78_66_F3_...
    property var cards: ({})

    function _cardKey(address) {
        return (address ?? "").toUpperCase().replace(/:/g, "_")
    }

    /// { active, profiles: [{ name, description }] } or null when PulseAudio
    /// has no card for this device (unpaired, off, or not an audio device).
    function cardFor(address) {
        return root.cards[root._cardKey(address)] ?? null
    }

    function setCardProfile(address, profile) {
        const key = root._cardKey(address)
        if (!root.cards[key]) return
        profileProc.command = ["pactl", "set-card-profile", "bluez_card." + key, profile]
        profileProc.running = true
        // Optimistic, so the chip does not snap back while pactl runs.
        const next = Object.assign({}, root.cards)
        next[key] = Object.assign({}, next[key], { active: profile })
        root.cards = next
    }

    Process {
        id: profileProc
        onExited: cardsProc.running = true
    }

    /// Re-read the cards. Only called when something asks.
    function refreshCards() {
        if (!cardsProc.running) cardsProc.running = true
    }

    Process {
        id: cardsProc
        // Text, not `pactl -f json`: that writer refuses non-ASCII bytes and
        // emits nothing at all when any card or port name carries one.
        command: ["bash", "-c",
            "export LC_ALL=C; pactl list cards | awk '" +
            "/^Card #/{ name=\"\"; active=\"\" } " +
            "/^\\tName: /{ name=$2 } " +
            "/^\\tActive Profile: /{ a=$0; sub(/^\\tActive Profile: /,\"\",a); " +
            "  print \"A\\t\" name \"\\t\" a } " +
            "/^\\t\\t[a-z0-9_+-]+: .*\\(sinks:/{ " +
            "  p=$1; sub(/:$/,\"\",p); d=$0; sub(/^\\t\\t[^:]+: /,\"\",d); " +
            "  avail=(index(d,\"not available\")>0)?0:1; " +
            "  sub(/ \\(sinks:.*/,\"\",d); " +
            "  if (avail) print \"P\\t\" name \"\\t\" p \"\\t\" d }'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const next = {}
                for (const line of text.split("\n")) {
                    const f = line.split("\t")
                    if (f.length < 3) continue
                    if (f[1].indexOf("bluez_card.") !== 0) continue
                    const key = f[1].substring("bluez_card.".length)
                    if (!next[key]) next[key] = { active: "", profiles: [] }
                    if (f[0] === "A") next[key].active = f[2]
                    else if (f[0] === "P" && f.length >= 4)
                        next[key].profiles.push({ name: f[2], description: f.slice(3).join("\t") })
                }
                root.cards = next
            }
        }
    }

    // A device connecting or dropping changes what cards exist.
    Connections {
        target: BluetoothStatus
        function onConnectedDevicesChanged() { root.refreshCards() }
    }

    // ---- Lookups for panels that only have a device, not a row -----------
    //
    // The Bluetooth-shaped panels are handed a BluetoothDevice and never see a
    // row. Before these existed each one re-derived the same answer its own way.

    /// Battery percent for a device by name, or -1 when nothing reports one.
    function batteryFor(name) {
        const r = root.rows.find(x => x.name === name)
        if (r) return r.battery
        // Not currently in rows (e.g. paired but idle) - a provider may still
        // answer, so ask rather than reporting "no battery".
        return root.providerPercent(name)
    }

    /// True when the number came from a vendor provider rather than BlueZ, so a
    /// panel can say so instead of implying BlueZ grew support it does not have.
    function batteryIsFromProvider(name) {
        const r = root.rows.find(x => x.name === name)
        if (r) return r.batteryFromProvider
        return root.providerPercent(name) >= 0
    }

    /// True when this device is currently attached by cable rather than radio.
    function isOnUsb(name) {
        const r = root.rows.find(x => x.name === name)
        return r ? r.transport === "usb" : false
    }
}
