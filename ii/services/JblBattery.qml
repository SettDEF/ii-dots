pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import QtQuick

/**
 * Battery level for JBL speakers that report it over Harman's own protocol.
 *
 * WHY THIS EXISTS
 * BlueZ never publishes org.bluez.Battery1 for the Xtreme 5 — it has no GATT
 * Battery Service, no HFP, and its Fast Pair advert carries no battery field.
 * The number lives only behind a BLE control service speaking Harman
 * "Protocol 4", which ~/.local/bin/jbl-battery implements. So the standard
 * `batteryAvailable` path in BluetoothDevicesView is correct but will always be
 * false for this device; this fills that gap and nothing else.
 *
 * COST
 * Each poll opens a BLE connection, so it is deliberately infrequent and only
 * runs while a supported speaker is actually connected. A refresh is also
 * triggered on demand when a panel showing it becomes visible.
 */
Singleton {
    id: root

    readonly property string tool: FileUtils.trimFileProtocol(`${Directories.home}/.local/bin/jbl-battery`)

    // Models whose battery only exists behind the Harman protocol. Matched on
    // the BlueZ device name, which is what BluetoothStatus exposes.
    readonly property var supportedNames: ["JBL Xtreme 5"]

    property int  percent: -1
    property string firmware: ""
    property double lastUpdate: 0
    property bool busy: false
    property string lastError: ""

    readonly property bool available: percent >= 0

    function isSupported(name) {
        return root.supportedNames.indexOf(name ?? "") !== -1
    }

    // Don't poll a speaker that isn't there.
    readonly property bool deviceConnected:
        BluetoothStatus.connectedDevices.some(d => root.isSupported(d?.name))

    function refresh(force) {
        if (root.busy || !root.deviceConnected) return
        // A BLE round trip costs seconds; 4 minutes is frequent enough for a
        // battery readout and keeps the radio mostly idle.
        const age = Date.now() - root.lastUpdate
        if (!force && root.lastUpdate > 0 && age < 240000) return
        root.busy = true
        proc.running = true
    }

    Process {
        id: proc
        command: [root.tool, "once"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false
                let r = null
                try { r = JSON.parse(text.trim()) } catch (e) { r = null }
                if (!r) {
                    root.lastError = "unparseable output"
                    return
                }
                if (r.ok) {
                    root.percent = r.percent
                    root.firmware = r.firmware ?? ""
                    root.lastUpdate = Date.now()
                    root.lastError = ""
                } else {
                    // Expected whenever the speaker is mid-rotation or busy;
                    // keep the last good reading rather than blanking the UI.
                    root.lastError = r.error ?? "unknown error"
                }
            }
        }
        onExited: root.busy = false
    }

    // Drop a stale reading when the speaker goes away, so the panel doesn't
    // show a number for something that is no longer connected.
    onDeviceConnectedChanged: {
        if (!root.deviceConnected) {
            root.percent = -1
            root.lastUpdate = 0
        } else {
            root.refresh(true)
        }
    }

    Timer {
        interval: 240000
        repeat: true
        running: root.deviceConnected
        triggeredOnStart: true
        onTriggered: root.refresh(false)
    }
}
