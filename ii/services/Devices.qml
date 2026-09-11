pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Services.Pipewire
import qs.modules.common
import QtQuick

/**
 * One list of the user's devices, whatever they are attached by.
 *
 * WHY THIS EXISTS
 * The panels here were built around Bluetooth, so a speaker on a USB-C cable
 * simply was not a device as far as the UI was concerned - it vanished from the
 * list at the moment it was most in use. Transport is a detail of how a device
 * is reachable, not what it is, so it belongs in a field rather than in which
 * panel you have to go and look at.
 *
 * Rows are plain objects, not wrappers, so a delegate can still reach the
 * underlying BluetoothDevice (for connect/disconnect) or PwNode (for volume)
 * when it needs to.
 */
Singleton {
    id: root

    // -- Classification ----------------------------------------------------
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

    // -- Bluetooth ---------------------------------------------------------
    readonly property var btRows: BluetoothStatus.connectedDevices.map(d => {
        const name = d?.name ?? "?"
        // BlueZ publishes battery for some devices and never for others; the
        // Harman speakers are the "never" case and are filled in separately.
        const bat = (d?.batteryAvailable ?? false)
            ? Math.round((d?.battery ?? 0) * 100)
            : (JblBattery.isSupported(name) ? JblBattery.percent : -1)
        return {
            key: "bt:" + (d?.address ?? name),
            name: name,
            kind: root.kindOf(d?.icon),
            transport: "bluetooth",
            battery: bat,
            batteryFromHarman: !(d?.batteryAvailable ?? false) && bat >= 0,
            device: d,
            node: null
        }
    })

    // -- USB audio ---------------------------------------------------------
    // A card shows up as separate output and input nodes; both carry the same
    // "usb-<vendor>_<model>_<serial>" segment, which is what identifies the
    // physical device. Group on that so one speaker is one row.
    function _usbKey(nodeName) {
        const m = String(nodeName ?? "").match(/^alsa_(?:output|input)\.(usb-[^.]+)\./)
        return m ? m[1] : ""
    }

    readonly property var usbNodes: Pipewire.nodes.values.filter(n => root._usbKey(n?.name) !== "")

    // description is only populated for tracked objects.
    PwObjectTracker { objects: root.usbNodes }

    readonly property var usbRows: {
        const byKey = ({})
        for (const n of root.usbNodes) {
            const k = root._usbKey(n.name)
            if (!k || byKey[k]) continue
            const desc = String(n.description ?? "").trim()
            // Fallback for an untracked node: turn the sysfs-ish id back into
            // something readable, e.g. "usb-Harman_JBL_Xtreme_5_GG1533-01".
            const fallback = k.replace(/^usb-/, "").replace(/_/g, " ").replace(/-\d+$/, "")
            const name = desc.length > 0 ? desc : fallback
            byKey[k] = {
                key: "usb:" + k,
                name: name,
                kind: root.kindOf(name + " audio"),
                transport: "usb",
                battery: JblBattery.isSupported(name) ? JblBattery.percent : -1,
                batteryFromHarman: JblBattery.isSupported(name) && JblBattery.percent >= 0,
                device: null,
                node: n
            }
        }
        return Object.keys(byKey).map(k => byKey[k])
    }

    // -- Combined ----------------------------------------------------------
    // A speaker that is paired but currently on its cable still belongs here;
    // it is the same device, just reachable a different way. Matched by name so
    // one physical thing never appears twice.
    readonly property var pairedOnUsb: BluetoothStatus.pairedButNotConnectedDevices.filter(d =>
        root.usbRows.some(u => u.name.indexOf(d?.name ?? " ") !== -1
                            || (d?.name ?? "").indexOf(u.name) !== -1))

    readonly property var rows: {
        const out = root.btRows.slice()
        for (const u of root.usbRows) {
            // Skip anything already listed over Bluetooth - same device.
            if (out.some(r => r.name === u.name)) continue
            // Prefer the paired BluetoothDevice object when we have one, so the
            // row keeps its real name and its per-type controls still work.
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

    // -- Lookups for panels that only have a device, not a row ------------
    //
    // The Bluetooth-shaped panels are handed a BluetoothDevice and never see a
    // row. Before these existed each one reached into JblBattery itself and
    // re-derived the same answer four different ways; this keeps that knowledge
    // in one place, and keeps JblBattery an implementation detail of the
    // service rather than something every delegate has to know about.

    /// Battery percent for a device by name, or -1 when nothing reports one.
    function batteryFor(name) {
        const r = root.rows.find(x => x.name === name)
        if (r) return r.battery
        // Not currently in rows (e.g. paired but idle) - the Harman speakers can
        // still answer, so ask anyway rather than reporting "no battery".
        return JblBattery.isSupported(name) ? JblBattery.percent : -1
    }

    /// True when the battery for this device came from Harman's control service
    /// rather than BlueZ, so a panel can say so instead of implying BlueZ grew
    /// support it does not have.
    function batteryIsFromHarman(name) {
        const r = root.rows.find(x => x.name === name)
        if (r) return r.batteryFromHarman
        return JblBattery.isSupported(name) && JblBattery.percent >= 0
    }

    /// True when this device is currently attached by cable rather than radio.
    function isOnUsb(name) {
        const r = root.rows.find(x => x.name === name)
        return r ? r.transport === "usb" : false
    }

    /// Ask any transport-specific client to refresh. Cheap to call on panel open.
    function refresh() { JblBattery.refresh(false) }

    /// True while some transport-specific client is mid-query, so a panel
    /// can show that a number is being fetched rather than looking stuck.
    readonly property bool busy: JblBattery.busy

    /// The most interesting battery to show on a compact tile: lowest known.
    readonly property int lowestBattery: {
        let best = -1
        for (const r of root.rows)
            if (r.battery >= 0 && (best < 0 || r.battery < best)) best = r.battery
        return best
    }
}
