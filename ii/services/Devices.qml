pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
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
            intervalMs: 240000
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
