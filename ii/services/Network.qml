pragma Singleton
pragma ComponentBehavior: Bound

// Took many bits from https://github.com/caelestia-dots/shell (GPLv3)

import Quickshell
import Quickshell.Io
import QtQuick
import qs.services.network

/**
 * Network service with nmcli.
 */
Singleton {
    id: root

    property bool wifi: true
    property bool ethernet: false

    property bool wifiEnabled: false
    property bool wifiScanning: false
    property bool wifiConnecting: connectProc.running
    property WifiAccessPoint wifiConnectTarget
    readonly property list<WifiAccessPoint> wifiNetworks: []
    readonly property WifiAccessPoint active: wifiNetworks.find(n => n.active) ?? null
    // ── Saved profiles & preference ─────────────────────────────────────
    // NetworkManager already has the concept we want: connection.autoconnect-
    // priority. Higher wins when several known networks are in range, so
    // "prefer this one" is a real setting the daemon acts on, not something
    // this shell has to re-implement or enforce itself.
    //
    // Keyed by SSID, but the VALUE carries the profile name, because the two
    // are not the same thing: a profile may be named anything ("WLAN-246200-5G"
    // for a band-locked one). Modifying by SSID would edit the wrong profile or
    // none at all, so every write goes through the stored name.
    property var savedProfiles: ({})    // ssid -> {name, priority, autoconnect}

    readonly property int preferredPriority: 20

    function profileFor(ssid) {
        return root.savedProfiles[ssid] ?? null;
    }
    function isSaved(ssid) {
        return root.savedProfiles[ssid] !== undefined;
    }
    function priorityOf(ssid) {
        return root.savedProfiles[ssid]?.priority ?? 0;
    }
    function isPreferred(ssid) {
        return root.priorityOf(ssid) > 0;
    }
    function autoconnectOf(ssid) {
        return root.savedProfiles[ssid]?.autoconnect ?? false;
    }
    function bandLockOf(ssid) {
        return root.savedProfiles[ssid]?.band ?? "";
    }

    // ── Frequency → human terms ─────────────────────────────────────────
    // nmcli reports a frequency in MHz; nobody thinks in MHz. The channel and
    // band are what let you spot the actual problems — a repeater sharing its
    // backhaul channel, or a 2.4GHz association you did not intend.
    function bandFor(freq) {
        if (freq >= 5925) return "6 GHz";
        if (freq >= 4900) return "5 GHz";
        return "2.4 GHz";
    }
    function channelFor(freq) {
        if (freq === 2484) return 14;                 // the one that breaks the formula
        if (freq >= 5925) return Math.round((freq - 5950) / 5);
        if (freq >= 4900) return Math.round((freq - 5000) / 5);
        return Math.round((freq - 2407) / 5);
    }
    // nmcli's SIGNAL is a percentage, not dBm. The conversion NetworkManager
    // itself uses is linear over -100..-50, so this is a faithful inverse
    // rather than a guess — but it is still a derived figure, and the live
    // link below reports the real thing for the connected network.
    function approxDbm(pct) {
        return Math.round(pct / 2 - 100);
    }

    function setAutoconnect(ssid, on) {
        const p = root.profileFor(ssid);
        if (!p) return;
        profileEditProc.exec(["nmcli", "connection", "modify", p.name,
                              "connection.autoconnect", on ? "yes" : "no"]);
    }
    function setPriority(ssid, n) {
        const p = root.profileFor(ssid);
        if (!p) return;
        profileEditProc.exec(["nmcli", "connection", "modify", p.name,
                              "connection.autoconnect-priority", String(n)]);
    }
    // Pinning a profile to one band is the direct fix for the case where a
    // 5GHz AP and a 2.4GHz AP share an SSID and the adapter keeps choosing the
    // slower one. "" clears the lock.
    function setBandLock(ssid, band) {
        const p = root.profileFor(ssid);
        if (!p) return;
        profileEditProc.exec(["nmcli", "connection", "modify", p.name,
                              "802-11-wireless.band", band]);
    }

    Process {
        id: profileEditProc
        onExited: savedProfilesProc.running = true
    }

    // ── Live link detail for the connected network ──────────────────────
    // nmcli's scan list cannot tell you any of this: it reports what the AP
    // advertises, not what your adapter negotiated. The real dBm, the rate
    // actually in use and the retry count are the numbers that distinguish "a
    // strong link" from "a link that works" — a -49 dBm association through a
    // repeater reads perfect here and still stutters, which is exactly why
    // retries and the channel are worth surfacing.
    property var linkInfo: ({})

    Process {
        id: linkInfoProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["bash", "-c",
            "d=$(nmcli -t -f DEVICE,TYPE,STATE d status | awk -F: '$2==\"wifi\" && $3==\"connected\"{print $1; exit}'); "
            + "[ -n \"$d\" ] || exit 0; "
            + "l=$(iw dev \"$d\" link 2>/dev/null); s=$(iw dev \"$d\" station dump 2>/dev/null); "
            + "echo \"dev=$d\"; "
            + "echo \"$l\" | sed -n 's/.*freq: *\\([0-9]*\\).*/freq=\\1/p'; "
            + "echo \"$l\" | sed -n 's/.*signal: *\\(-[0-9]*\\).*/dbm=\\1/p'; "
            + "echo \"$l\" | sed -n 's/.*tx bitrate: *\\([0-9.]*\\).*/tx=\\1/p'; "
            + "echo \"$l\" | sed -n 's/.*rx bitrate: *\\([0-9.]*\\).*/rx=\\1/p'; "
            // station dump separates label from value with a TAB, not a space —
            // matching only on spaces silently produced empty values.
            + "echo \"$s\" | sed -n 's/.*tx retries:[[:space:]]*\\([0-9]*\\).*/retries=\\1/p'; "
            + "echo \"$s\" | sed -n 's/.*tx failed:[[:space:]]*\\([0-9]*\\).*/failed=\\1/p'; "
            + "echo \"$s\" | sed -n 's/.*connected time:[[:space:]]*\\([0-9]*\\).*/uptime=\\1/p'; "
            + "ip -4 -o addr show dev \"$d\" 2>/dev/null | awk '{print \"ip=\"$4; exit}'; "
            + "ip route | awk -v d=\"$d\" '$1==\"default\" && $5==d {print \"gw=\"$3; exit}'; "
            + "sed 's/^/mac=/' /sys/class/net/\"$d\"/address 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {};
                for (const line of String(text).trim().split("\n")) {
                    const i = line.indexOf("=");
                    if (i > 0) o[line.slice(0, i)] = line.slice(i + 1);
                }
                root.linkInfo = o;
            }
        }
    }

    // Flat views of linkInfo, for readouts that just want the value.
    // Empty until something sets detailsVisible — nothing polls otherwise.
    readonly property string networkInterface: linkInfo.dev ?? ""
    readonly property string ipAddress: (linkInfo.ip ?? "").split("/")[0]
    readonly property string gateway: linkInfo.gw ?? ""
    readonly property string macAddress: linkInfo.mac ?? ""

    // Only while something is actually looking at it — this shells out to iw
    // and ip, and polling that in the background forever would be waste.
    property bool detailsVisible: false
    Timer {
        interval: 3000
        repeat: true
        running: root.detailsVisible
        triggeredOnStart: true
        onTriggered: if (!linkInfoProc.running) linkInfoProc.running = true
    }

    // Only a SAVED network can carry a preference — there is nothing to attach
    // it to otherwise, so the UI hides the control rather than offering
    // something that would silently do nothing.
    function setPreferred(ssid, preferred) {
        const p = root.profileFor(ssid);
        if (!p) return;
        setPriorityProc.exec(["nmcli", "connection", "modify", p.name,
                              "connection.autoconnect-priority",
                              String(preferred ? root.preferredPriority : 0),
                              "connection.autoconnect", "yes"]);
    }

    Process {
        id: setPriorityProc
        onExited: savedProfilesProc.running = true
    }

    Process {
        id: savedProfilesProc
        running: true
        environment: ({ LANG: "C", LC_ALL: "C" })
        // Per-profile lookup rather than one table: `connection show` without a
        // target cannot report 802-11-wireless.ssid, and the profile name is
        // not a reliable stand-in for it.
        command: ["bash", "-c",
            "nmcli -t -f UUID,TYPE connection show 2>/dev/null "
            + "| awk -F: '$2==\"802-11-wireless\"{print $1}' "
            + "| while read -r u; do "
            +   "nmcli -g 802-11-wireless.ssid,connection.autoconnect-priority,"
            +   "connection.autoconnect,802-11-wireless.band,connection.id "
            +   "connection show \"$u\" 2>/dev/null "
            +   "| paste -sd'|'; "
            + "done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                for (const line of String(text).trim().split("\n")) {
                    if (!line) continue;
                    // Split from the RIGHT: an SSID may legitimately contain
                    // the separator, the three trailing fields never do.
                    const bits = line.split("|");
                    if (bits.length < 5) continue;
                    const name = bits.pop();
                    const band = bits.pop();
                    const auto = bits.pop();
                    const prio = parseInt(bits.pop(), 10);
                    const ssid = bits.join("|");
                    if (!ssid) continue;
                    // Several profiles can share an SSID (band-locked variants).
                    // The highest-priority one is the one whose preference the
                    // user is actually seeing take effect, so it wins the slot.
                    const prev = map[ssid];
                    if (prev && prev.priority >= prio) continue;
                    map[ssid] = {
                        name: name,
                        priority: isFinite(prio) ? prio : 0,
                        autoconnect: auto === "yes",
                        band: band ?? ""
                    };
                }
                root.savedProfiles = map;
            }
        }
    }

    readonly property list<var> friendlyWifiNetworks: [...wifiNetworks].sort((a, b) => {
        if (a.active && !b.active)
            return -1;
        if (!a.active && b.active)
            return 1;
        // Preferred networks rank above unpreferred ones regardless of signal:
        // the whole point of marking one is that it should win even when
        // something louder is in range — which is exactly how a repeater ends
        // up chosen over the router behind it.
        const pa = root.priorityOf(a.ssid);
        const pb = root.priorityOf(b.ssid);
        if (pa !== pb) return pb - pa;
        return b.strength - a.strength;
    })
    property string wifiStatus: "disconnected"

    property string networkName: ""
    property int networkStrength
    // Icon state, in order of what actually matters to look at.
    //
    // The previous version tested `wifiEnabled` BEFORE the status, which made
    // every status icon dead code: with the radio on it always drew signal
    // bars, and the connecting / disconnected / limited icons could only be
    // reached with the radio off — where the status is "disabled" anyway. So
    // an unassociated adapter drew a confident "0 bars" and a captive portal
    // drew full bars. Status is checked first now, and strength is only shown
    // once there is a connection whose strength means something.
    property string materialSymbol: {
        if (root.ethernet) return "lan";
        if (!root.wifiEnabled || root.wifiStatus === "disabled")
            return "signal_wifi_off";
        if (root.wifiStatus === "connecting")
            return "signal_wifi_statusbar_not_connected";
        // Associated but no route out — a captive portal or a dead upstream.
        // Worth its own icon: full bars with no internet is the single most
        // confusing thing a wifi indicator can show.
        if (root.wifiStatus === "limited") return "signal_wifi_bad";
        if (root.wifiStatus === "disconnected") return "wifi_find";

        const s = root.networkStrength;
        return s > 80 ? "signal_wifi_4_bar"
             : s > 60 ? "network_wifi_3_bar"
             : s > 40 ? "network_wifi_2_bar"
             : s > 20 ? "network_wifi_1_bar"
             : "signal_wifi_0_bar";
    }

    // Control
    function enableWifi(enabled = true): void {
        const cmd = enabled ? "on" : "off";
        enableWifiProc.exec(["nmcli", "radio", "wifi", cmd]);
    }

    function toggleWifi(): void {
        enableWifi(!wifiEnabled);
    }

    function rescanWifi(): void {
        wifiScanning = true;
        rescanProcess.running = true;
    }

    function connectToWifiNetwork(accessPoint: WifiAccessPoint): void {
        accessPoint.askingPassword = false;
        root.wifiConnectTarget = accessPoint;
        // We use this instead of `nmcli connection up SSID` because this also creates a connection profile
        connectProc.exec(["nmcli", "dev", "wifi", "connect", accessPoint.ssid])

    }

    function disconnectWifiNetwork(): void {
        if (active) disconnectProc.exec(["nmcli", "connection", "down", active.ssid]);
    }

    function openPublicWifiPortal() {
        Quickshell.execDetached(["xdg-open", "https://nmcheck.gnome.org/"]) // From some StackExchange thread, seems to work
    }

    function changePassword(network: WifiAccessPoint, password: string, username = ""): void {
        // TODO: enterprise wifi with username
        network.askingPassword = false;
        changePasswordProc.exec({
            "environment": {
                "PASSWORD": password,
                "SSID": network.ssid
            },
            "command": ["bash", "-c", 'nmcli connection modify "$SSID" wifi-sec.psk "$PASSWORD"']
        })
    }

    Process {
        id: enableWifiProc
    }

    Process {
        id: connectProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: SplitParser {
            onRead: line => {
                // print(line)
                getNetworks.running = true
            }
        }
        stderr: SplitParser {
            onRead: line => {
                // print("err:", line)
                if (line.includes("Secrets were required")) {
                    root.wifiConnectTarget.askingPassword = true
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.wifiConnectTarget.askingPassword = (exitCode !== 0)
            root.wifiConnectTarget = null
        }
    }

    Process {
        id: disconnectProc
        stdout: SplitParser {
            onRead: getNetworks.running = true
        }
    }

    Process {
        id: changePasswordProc
        onExited: { // Re-attempt connection after changing password
            connectProc.running = false
            connectProc.running = true
        }
    }

    Process {
        id: rescanProcess
        command: ["nmcli", "dev", "wifi", "list", "--rescan", "yes"]
        stdout: SplitParser {
            onRead: {
                wifiScanning = false;
                getNetworks.running = true;
            }
        }
    }

    // Status update
    function update() {
        updateConnectionType.startCheck();
        wifiStatusProcess.running = true
        updateNetworkName.running = true;
        updateNetworkStrength.running = true;
        // Connecting to a new network creates a profile, and forgetting one
        // deletes it, so the saved set is only correct if it is re-read
        // whenever nmcli reports a change.
        if (!savedProfilesProc.running) savedProfilesProc.running = true;
    }

    Process {
        id: subscriber
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            onRead: root.update()
        }
    }

    Process {
        id: updateConnectionType
        property string buffer
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE d status && nmcli -t -f CONNECTIVITY g"]
        running: true
        function startCheck() {
            buffer = "";
            updateConnectionType.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                updateConnectionType.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            const lines = updateConnectionType.buffer.trim().split('\n');
            const connectivity = lines.pop() // none, limited, full
            let hasEthernet = false;
            let hasWifi = false;
            let wifiStatus = "disconnected";
            lines.forEach(line => {
                if (line.includes("ethernet") && line.includes("connected"))
                    hasEthernet = true;
                else if (line.includes("wifi:")) {
                    if (line.includes("disconnected")) {
                        wifiStatus = "disconnected"
                    }
                    else if (line.includes("connected")) {
                        hasWifi = true;
                        wifiStatus = "connected"

                        if (connectivity === "limited") {
                            hasWifi = false;
                            wifiStatus = "limited"
                        }
                    }
                    else if (line.includes("connecting")) {
                        wifiStatus = "connecting"
                    }
                    else if (line.includes("unavailable")) {
                        wifiStatus = "disabled"
                    }
                }
            });
            root.wifiStatus = wifiStatus;
            root.ethernet = hasEthernet;
            root.wifi = hasWifi;
        }
    }

    Process {
        id: updateNetworkName
        command: ["sh", "-c", "nmcli -t -f NAME c show --active | head -1"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                root.networkName = data;
            }
        }
    }

    Process {
        id: updateNetworkStrength
        running: true
        command: ["sh", "-c", "nmcli -f IN-USE,SIGNAL,SSID device wifi | awk '/^\*/{if (NR!=1) {print $2}}'"]
        stdout: SplitParser {
            onRead: data => {
                root.networkStrength = parseInt(data);
            }
        }
    }

    Process {
        id: wifiStatusProcess
        command: ["nmcli", "radio", "wifi"]
        Component.onCompleted: running = true
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiEnabled = text.trim() === "enabled";
            }
        }
    }

    Process {
        id: getNetworks
        running: true
        command: ["nmcli", "-g", "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY", "d", "w"]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                const PLACEHOLDER = "STRINGWHICHHOPEFULLYWONTBEUSED";
                const rep = new RegExp("\\\\:", "g");
                const rep2 = new RegExp(PLACEHOLDER, "g");

                const allNetworks = text.trim().split("\n").map(n => {
                    const net = n.replace(rep, PLACEHOLDER).split(":");
                    return {
                        active: net[0] === "yes",
                        strength: parseInt(net[1]),
                        frequency: parseInt(net[2]),
                        ssid: net[3],
                        bssid: net[4]?.replace(rep2, ":") ?? "",
                        security: net[5] || ""
                    };
                }).filter(n => n.ssid && n.ssid.length > 0);

                // Group networks by SSID and prioritize connected ones
                const networkMap = new Map();
                for (const network of allNetworks) {
                    const existing = networkMap.get(network.ssid);
                    if (!existing) {
                        networkMap.set(network.ssid, network);
                    } else {
                        // Prioritize active/connected networks
                        if (network.active && !existing.active) {
                            networkMap.set(network.ssid, network);
                        } else if (!network.active && !existing.active) {
                            // If both are inactive, keep the one with better signal
                            if (network.strength > existing.strength) {
                                networkMap.set(network.ssid, network);
                            }
                        }
                        // If existing is active and new is not, keep existing
                    }
                }

                const wifiNetworks = Array.from(networkMap.values());

                const rNetworks = root.wifiNetworks;

                const destroyed = rNetworks.filter(rn => !wifiNetworks.find(n => n.frequency === rn.frequency && n.ssid === rn.ssid && n.bssid === rn.bssid));
                for (const network of destroyed)
                    rNetworks.splice(rNetworks.indexOf(network), 1).forEach(n => n.destroy());

                for (const network of wifiNetworks) {
                    const match = rNetworks.find(n => n.frequency === network.frequency && n.ssid === network.ssid && n.bssid === network.bssid);
                    if (match) {
                        match.lastIpcObject = network;
                    } else {
                        rNetworks.push(apComp.createObject(root, {
                            lastIpcObject: network
                        }));
                    }
                }
            }
        }
    }

    Component {
        id: apComp

        WifiAccessPoint {}
    }
}
