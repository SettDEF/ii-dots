// KDE Connect device tracker — polls `kdeconnect-cli` every 5 s.
// Exposes the list of paired devices (with reachable/charging/battery) plus
// helper functions for the common phone actions (ring, ping, share).
pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common.functions

Singleton {
    id: root

    // Each entry: { id, name, type, reachable, trusted, charging, battery }
    property var devices: []
    readonly property var reachableDevices: devices.filter(d => d.reachable && d.trusted)
    readonly property var firstDevice: reachableDevices.length > 0 ? reachableDevices[0] : null
    readonly property bool anyConnected: reachableDevices.length > 0

    function refresh() { listProc.running = true }

    // ── Action helpers ────────────────────────────────────────────────────
    function ring(deviceId)        { run(["kdeconnect-cli", "--device", deviceId, "--ring"]) }
    function ping(deviceId, msg)   { run(["kdeconnect-cli", "--device", deviceId, "--ping-msg", msg || "ping"]) }
    function share(deviceId, path) { run(["kdeconnect-cli", "--device", deviceId, "--share", path]) }
    function shareText(deviceId, text) { run(["kdeconnect-cli", "--device", deviceId, "--share-text", text]) }
    function sendSms(deviceId, dest, text) {
        run(["kdeconnect-cli", "--device", deviceId, "--destination", dest, "--send-sms", text])
    }
    function pair(deviceId)   { run(["kdeconnect-cli", "--device", deviceId, "--pair"]) }
    function unpair(deviceId) { run(["kdeconnect-cli", "--device", deviceId, "--unpair"]) }
    function refreshDevices() { run(["kdeconnect-cli", "--refresh"]) }
    function openCli()        { run(["kdeconnect-app"]) }

    function run(cmd) { Quickshell.execDetached(cmd) }

    // ── Phone media (KDE Connect mprisremote plugin) ──────────────────
    // The phone's media isn't on the desktop's MPRIS bus; KDE Connect
    // exposes it via its own DBus path
    // /modules/kdeconnect/devices/<id>/mprisremote
    property string phoneMediaTitle:    ""
    property string phoneMediaArtist:   ""
    property string phoneMediaAlbum:    ""
    property string phoneMediaPlayer:   ""
    property string phoneMediaArtUrl:   ""
    property bool   phoneMediaIsPlaying: false
    property bool   phoneMediaAvailable: false

    function _mprisCall(method) {
        const id = firstDevice?.id ?? ""
        if (!id) return
        run(["qdbus", "org.kde.kdeconnect",
             "/modules/kdeconnect/devices/" + id + "/mprisremote",
             "org.kde.kdeconnect.device.mprisremote." + method])
    }
    function phoneMediaPlayPause() { _mprisCall("playPause") }
    function phoneMediaNext()      { _mprisCall("next") }
    function phoneMediaPrevious()  { _mprisCall("previous") }

    Process {
        id: mprisProc
        property string activeId: ""
        function fetch(id) {
            activeId = id
            const base = `qdbus org.kde.kdeconnect /modules/kdeconnect/devices/${id}/mprisremote `
                       + `org.kde.kdeconnect.device.mprisremote.`
            // Order matters — parsed by index below.
            command = ["bash", "-c",
                base + "title 2>/dev/null;     echo ___SEP___; " +
                base + "artist 2>/dev/null;    echo ___SEP___; " +
                base + "album 2>/dev/null;     echo ___SEP___; " +
                base + "player 2>/dev/null;    echo ___SEP___; " +
                base + "isPlaying 2>/dev/null"
            ]
            running = true
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("___SEP___").map(s => s.trim())
                const title  = parts[0] ?? ""
                const artist = parts[1] ?? ""
                const album  = parts[2] ?? ""
                const player = parts[3] ?? ""
                const playing = (parts[4] ?? "").trim() === "true"
                root.phoneMediaTitle    = title
                root.phoneMediaArtist   = artist
                root.phoneMediaAlbum    = album
                root.phoneMediaPlayer   = player
                root.phoneMediaIsPlaying = playing
                root.phoneMediaArtUrl   = ""
                root.phoneMediaAvailable = title.length > 0 || player.length > 0
            }
        }
    }
    Timer {
        // Phone-media polling is only useful while the user is looking
        // at the right sidebar (the only place phone media is shown).
        // Off-panel polling spawned 5 qdbus subprocesses every 3 s for
        // a UI nobody could see.
        interval: 3000
        repeat: true
        running: root.firstDevice !== null && GlobalStates.sidebarRightOpen
        triggeredOnStart: true
        onTriggered: {
            const id = root.firstDevice?.id ?? ""
            if (id) mprisProc.fetch(id)
            else {
                root.phoneMediaAvailable = false
                root.phoneMediaTitle = ""
                root.phoneMediaArtist = ""
            }
        }
    }

    // ── MPRIS bridge ─────────────────────────────────────────────────
    // Publishes the phone's media state as a real MPRIS player on the
    // session bus so it shows up in MprisController.players alongside
    // Spotify/Firefox/etc. — see scripts/kdeconnect/mpris_bridge.py.
    property string _bridgedDeviceId: ""
    Process {
        id: bridgeProc
        // Started/restarted by the watcher below. Keeping `running: false`
        // here lets us drive lifecycle imperatively.
        running: false
    }
    function _startBridge(id) {
        bridgeProc.running = false
        if (!id) return
        bridgeProc.command = ["python3",
            FileUtils.trimFileProtocol(Quickshell.shellPath("ii/scripts/kdeconnect/mpris_bridge.py")),
            id
        ]
        bridgeProc.running = true
    }
    function _ensureBridge() {
        const id = firstDevice?.id ?? ""
        // No change — leave the bridge alone (avoids the brief MPRIS
        // player removal/re-add that confuses other media apps).
        if (id === _bridgedDeviceId) {
            bridgeStopTimer.stop()
            return
        }
        // Device went away.  Don't kill the bridge yet — kdeconnect-cli
        // briefly reports no devices during reconnects, and a flapping
        // MPRIS player would pause / re-target the user's actual media.
        if (id === "" && _bridgedDeviceId !== "") {
            bridgeStopTimer.restart()
            return
        }
        // New device id — switch immediately.
        bridgeStopTimer.stop()
        _bridgedDeviceId = id
        _startBridge(id)
    }
    Timer {
        id: bridgeStopTimer
        // Grace period before killing the bridge after the device drops.
        // 12 s is long enough to cover a kdeconnect-cli flap but short
        // enough to release the MPRIS bus name when the phone is really gone.
        interval: 12000
        repeat: false
        onTriggered: {
            if ((root.firstDevice?.id ?? "") === "") {
                root._bridgedDeviceId = ""
                bridgeProc.running = false
            }
        }
    }
    onFirstDeviceChanged: _ensureBridge()
    Component.onCompleted: _ensureBridge()

    // ── Polling ───────────────────────────────────────────────────────────
    Process {
        id: listProc
        // Output one line per device: "id|name|type|reachable|trusted"
        // Then for reachable devices we also fetch battery + charging.
        // Device facts come from D-BUS, not from parsing `kdeconnect-cli
        // --list-devices` prose. That parse was wrong three ways at once and the
        // dialog rendered as an empty box because of it:
        //
        //   - Xperia 1 IV: 5277af5b470e43149beac7b60bb3fc1a on 192.168.178.50 via LAN (reachable)
        //
        //  * The id was read as everything between ": " and " (", i.e.
        //    "5277af5b… on 192.168.178.50 via LAN". Every downstream call passes
        //    this id back to kdeconnect-cli/qdbus, so they all addressed a device
        //    that does not exist.
        //  * trusted was `index(flags,"paired")>0`, but this build prints only
        //    "(reachable)". So trusted was always false, reachableDevices was
        //    always empty, firstDevice was null — while devices.length was 1, so
        //    the "no devices" state hid too. A titled, empty dialog.
        //  * "paired" is a SUBSTRING of "unpaired", so that test would also have
        //    called an explicitly unpaired device trusted.
        //
        // The text simply does not carry pairing state on this build: this phone
        // prints "(reachable)" while org.kde.kdeconnect.device.isPaired is FALSE.
        // Guessing from flags cannot be made correct, so ask the daemon. --id-only
        // gives clean ids with nothing to parse, and each property is read
        // straight off the device object.
        command: ["bash", "-c",
            `for id in $(kdeconnect-cli --list-devices --id-only 2>/dev/null); do ` +
            `  d=/modules/kdeconnect/devices/$id; ` +
            `  n=$(qdbus org.kde.kdeconnect $d org.kde.kdeconnect.device.name 2>/dev/null); ` +
            `  t=$(qdbus org.kde.kdeconnect $d org.kde.kdeconnect.device.type 2>/dev/null); ` +
            `  r=$(qdbus org.kde.kdeconnect $d org.kde.kdeconnect.device.isReachable 2>/dev/null); ` +
            `  p=$(qdbus org.kde.kdeconnect $d org.kde.kdeconnect.device.isPaired 2>/dev/null); ` +
            `  [ -z "$n" ] && continue; ` +
            `  printf '%s|%s|%s|%s|%s\\n' "$id" "$n" "\${t:-phone}" ` +
            `    "$([ "$r" = true ] && echo 1 || echo 0)" ` +
            `    "$([ "$p" = true ] && echo 1 || echo 0)"; ` +
            `done`
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                const lines = text.trim().split("\n").filter(l => l.trim())
                for (const line of lines) {
                    const [id, name, type, reach, trust] = line.split("|")
                    if (!id) continue
                    const dev = root.devices.find(d => d.id === id) || {}
                    out.push({
                        id, name, type,
                        reachable: reach === "1",
                        trusted:   trust === "1",
                        battery:   dev.battery ?? -1,
                        charging:  dev.charging ?? false
                    })
                }
                root.devices = out
                // Kick a battery/charging fetch for each reachable device.
                for (const d of out)
                    if (d.reachable && d.trusted) batteryProc.fetch(d.id)
            }
        }
    }
    Process {
        id: batteryProc
        property string activeId: ""
        function fetch(id) {
            activeId = id
            command = ["bash", "-c",
                `qdbus org.kde.kdeconnect /modules/kdeconnect/devices/${id}/battery org.kde.kdeconnect.device.battery.charge 2>/dev/null; ` +
                `qdbus org.kde.kdeconnect /modules/kdeconnect/devices/${id}/battery org.kde.kdeconnect.device.battery.isCharging 2>/dev/null`
            ]
            running = true
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l.trim())
                if (lines.length < 1) return
                const charge   = parseInt(lines[0])
                const charging = (lines[1] || "").trim() === "true"
                const arr = root.devices.slice()
                const i = arr.findIndex(d => d.id === batteryProc.activeId)
                if (i >= 0) {
                    arr[i] = Object.assign({}, arr[i], { battery: charge, charging })
                    root.devices = arr
                }
            }
        }
    }
    Timer {
        // 15 s — kept always-on so the bar's phone-connected indicator
        // is reasonably fresh.  Was 5 s, which spawned kdeconnect-cli
        // every five seconds for the entire session.
        interval: 15000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
