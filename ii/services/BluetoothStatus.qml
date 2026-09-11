pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property bool available: Bluetooth.adapters.values.length > 0
    readonly property bool enabled: Bluetooth.defaultAdapter?.enabled ?? false
    readonly property BluetoothDevice firstActiveDevice: Bluetooth.defaultAdapter?.devices.values.find(device => device.connected) ?? null
    readonly property int activeDeviceCount: Bluetooth.defaultAdapter?.devices.values.filter(device => device.connected).length ?? 0
    readonly property bool connected: Bluetooth.devices.values.some(d => d.connected)

    function sortFunction(a, b) {
        // Ones with meaningful names before MAC addresses
        const macRegex = /^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$/;
        const aIsMac = macRegex.test(a.name);
        const bIsMac = macRegex.test(b.name);
        if (aIsMac !== bIsMac)
            return aIsMac ? 1 : -1;

        // Alphabetical by name
        return a.name.localeCompare(b.name);
    }
    property list<var> connectedDevices: Bluetooth.devices.values.filter(d => d.connected).sort(sortFunction)
    property list<var> pairedButNotConnectedDevices: Bluetooth.devices.values.filter(d => d.paired && !d.connected).sort(sortFunction)
    property list<var> unpairedDevices: Bluetooth.devices.values.filter(d => !d.paired && !d.connected).sort(sortFunction)
    property list<var> friendlyDeviceList: [
        ...connectedDevices,
        ...pairedButNotConnectedDevices,
        ...unpairedDevices
    ]

    // ── Safety: never let BT discovery run indefinitely ────────────────────
    // The WiFi+BT combo chip (MT7925) shares the 2.4GHz radio, so an open
    // discovery scan wrecks WiFi latency (jitter 1→130ms). Several panels
    // start a scan but don't reliably stop it on close, leaving discovery on
    // for good. Cap every scan at 30s so a forgotten scan can't tank the
    // network — plenty of time to pair, and re-scanning is one tap away.
    readonly property bool discoveryActive: Bluetooth.defaultAdapter?.discovering ?? false
    onDiscoveryActiveChanged: {
        if (root.discoveryActive)
            scanGuard.restart();
        else
            scanGuard.stop();
    }
    Timer {
        id: scanGuard
        interval: 30000
        repeat: false
        onTriggered: {
            if (Bluetooth.defaultAdapter?.discovering)
                Bluetooth.defaultAdapter.discovering = false;
        }
    }
}
