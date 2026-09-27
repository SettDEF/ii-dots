pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.services.network

/**
 * Network state, over nmcli. Four sources, none of which answers alone:
 *   - `nmcli monitor`     when anything changed; the only refresh trigger
 *   - `nmcli device wifi` the scan list, i.e. what the APs advertise
 *   - `nmcli connection`  saved profiles: priority, autoconnect, band
 *   - `iw`                the live association the scan list cannot see
 */
Singleton {
    id: root

    // ── Connection state ───────────────────────────────────────────────────

    /// Reaches the internet. A captive portal is associated but leaves this false.
    property bool wifi: true
    property bool ethernet: false

    property bool wifiEnabled: false
    property bool wifiScanning: false
    readonly property bool wifiConnecting: connectProc.running
    property WifiAccessPoint wifiConnectTarget

    /// "connected" | "connecting" | "limited" | "disconnected" | "disabled"
    property string wifiStatus: "disconnected"
    property string networkName: ""
    property int networkStrength: 0

    readonly property list<WifiAccessPoint> wifiNetworks: []
    readonly property WifiAccessPoint active: root.wifiNetworks.find(n => n.active) ?? null

    /// Status before strength, or the status icons are unreachable and a
    /// captive portal draws four bars.
    readonly property string materialSymbol: {
        if (root.ethernet) return "lan";
        if (!root.wifiEnabled || root.wifiStatus === "disabled") return "signal_wifi_off";
        if (root.wifiStatus === "connecting") return "signal_wifi_statusbar_not_connected";
        // Associated with no route out. Worth its own icon: full bars and no
        // internet is the most confusing thing a wifi indicator can show.
        if (root.wifiStatus === "limited") return "signal_wifi_bad";
        if (root.wifiStatus === "disconnected") return "wifi_find";

        const s = root.networkStrength;
        return s > 80 ? "signal_wifi_4_bar"
             : s > 60 ? "network_wifi_3_bar"
             : s > 40 ? "network_wifi_2_bar"
             : s > 20 ? "network_wifi_1_bar"
             : "signal_wifi_0_bar";
    }

    // ── nmcli terse parsing ────────────────────────────────────────────────

    /// `nmcli -t` escapes ":" as "\:", so a bare split tears a BSSID into six.
    function splitTerse(line: string): var {
        const fields = [];
        let current = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) { current += line[++i]; }
            else if (c === ":") { fields.push(current); current = ""; }
            else current += c;
        }
        fields.push(current);
        return fields;
    }

    // ── Saved profiles and preference ──────────────────────────────────────
    // "Prefer this one" is connection.autoconnect-priority, which the daemon
    // already acts on. Keyed by SSID, but the value carries the profile NAME:
    // a band-locked profile may be called anything, and modifying by SSID would
    // edit the wrong one.

    property var savedProfiles: ({})     // ssid -> { name, priority, autoconnect, band }

    readonly property int preferredPriority: 20

    function profileFor(ssid) { return root.savedProfiles[ssid] ?? null; }
    function isSaved(ssid) { return root.savedProfiles[ssid] !== undefined; }
    function priorityOf(ssid) { return root.savedProfiles[ssid]?.priority ?? 0; }
    function isPreferred(ssid) { return root.priorityOf(ssid) > 0; }
    function autoconnectOf(ssid) { return root.savedProfiles[ssid]?.autoconnect ?? false; }
    function bandLockOf(ssid) { return root.savedProfiles[ssid]?.band ?? ""; }

    /// Re-reads the table afterwards: the UI shows what nmcli accepted.
    function modifyProfile(ssid, ...settings): void {
        const profile = root.profileFor(ssid);
        if (!profile) return;
        profileEditProc.exec(["nmcli", "connection", "modify", profile.name, ...settings]);
    }

    function setAutoconnect(ssid, on): void {
        root.modifyProfile(ssid, "connection.autoconnect", on ? "yes" : "no");
    }
    function setPriority(ssid, n): void {
        root.modifyProfile(ssid, "connection.autoconnect-priority", String(n));
    }
    /// For a 5GHz and a 2.4GHz AP sharing an SSID. "" clears the lock.
    function setBandLock(ssid, band): void {
        root.modifyProfile(ssid, "802-11-wireless.band", band);
    }
    /// Only a saved network can carry one; the UI hides the control otherwise.
    function setPreferred(ssid, preferred): void {
        root.modifyProfile(ssid,
            "connection.autoconnect-priority",
            String(preferred ? root.preferredPriority : 0),
            "connection.autoconnect", "yes");
    }

    Process {
        id: profileEditProc
        onExited: savedProfilesProc.running = true
    }

    Process {
        id: savedProfilesProc
        running: true
        environment: ({ LANG: "C", LC_ALL: "C" })
        // Per profile, not one table: `connection show` with no target cannot
        // report 802-11-wireless.ssid, and the profile name is not a reliable
        // stand-in for it.
        command: ["bash", "-c",
            "nmcli -t -f UUID,TYPE connection show 2>/dev/null "
            + "| awk -F: '$2==\"802-11-wireless\"{print $1}' "
            + "| while read -r u; do "
            +   "nmcli -g 802-11-wireless.ssid,connection.autoconnect-priority,"
            +   "connection.autoconnect,802-11-wireless.band,connection.id "
            +   "connection show \"$u\" 2>/dev/null | paste -sd'|'; "
            + "done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const table = {};
                for (const line of String(text).trim().split("\n")) {
                    if (!line) continue;
                    // From the right: an SSID may contain the separator.
                    const parts = line.split("|");
                    if (parts.length < 5) continue;
                    const name = parts.pop();
                    const band = parts.pop();
                    const autoconnect = parts.pop();
                    const priority = parseInt(parts.pop(), 10);
                    const ssid = parts.join("|");
                    if (!ssid) continue;

                    // Band-locked variants share an SSID; the highest priority wins.
                    const existing = table[ssid];
                    const value = isFinite(priority) ? priority : 0;
                    if (existing && existing.priority >= value) continue;

                    table[ssid] = {
                        name: name,
                        priority: value,
                        autoconnect: autoconnect === "yes",
                        band: band ?? ""
                    };
                }
                root.savedProfiles = table;
            }
        }
    }

    // ── Frequency, in human terms ──────────────────────────────────────────
    // nmcli reports MHz; the band and channel are what show a repeater sharing
    // its backhaul channel, or an unintended 2.4GHz association.

    function bandFor(freq) {
        if (freq >= 5925) return "6 GHz";
        if (freq >= 4900) return "5 GHz";
        return "2.4 GHz";
    }

    function channelFor(freq) {
        if (freq === 2484) return 14;                  // the one that breaks the formula
        if (freq >= 5925) return Math.round((freq - 5950) / 5);
        if (freq >= 4900) return Math.round((freq - 5000) / 5);
        return Math.round((freq - 2407) / 5);
    }

    /// Inverse of NetworkManager's own linear -100..-50 mapping. Derived —
    /// linkInfo has the real dBm for the connected network.
    function approxDbm(pct) { return Math.round(pct / 2 - 100); }

    // ── Live link detail ───────────────────────────────────────────────────
    // What the adapter negotiated. A -49 dBm link through a repeater scans
    // perfect and still stutters; the retry count is what shows it.

    property var linkInfo: ({})

    readonly property string networkInterface: root.linkInfo.dev ?? ""
    readonly property string ipAddress: (root.linkInfo.ip ?? "").split("/")[0]
    readonly property string gateway: root.linkInfo.gw ?? ""
    readonly property string macAddress: root.linkInfo.mac ?? ""

    /// Set by whatever panel is reading it: this shells out to iw and ip.
    property bool detailsVisible: false

    Timer {
        interval: 3000
        repeat: true
        running: root.detailsVisible
        triggeredOnStart: true
        onTriggered: if (!linkInfoProc.running) linkInfoProc.running = true
    }

    Process {
        id: linkInfoProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["bash", "-c",
            'd=$(nmcli -t -f DEVICE,TYPE,STATE d status | awk -F: \'$2=="wifi" && $3=="connected"{print $1; exit}\'); '
            + '[ -n "$d" ] || exit 0; '
            + 'link=$(iw dev "$d" link 2>/dev/null); station=$(iw dev "$d" station dump 2>/dev/null); '
            + 'printf "dev=%s\\n" "$d"; '
            + 'printf "%s\\n" "$link" | sed -n "s/.*freq: *\\([0-9]*\\).*/freq=\\1/p"; '
            + 'printf "%s\\n" "$link" | sed -n "s/.*signal: *\\(-[0-9]*\\).*/dbm=\\1/p"; '
            + 'printf "%s\\n" "$link" | sed -n "s/.*tx bitrate: *\\([0-9.]*\\).*/tx=\\1/p"; '
            + 'printf "%s\\n" "$link" | sed -n "s/.*rx bitrate: *\\([0-9.]*\\).*/rx=\\1/p"; '
            // station dump uses a TAB, not a space.
            + 'printf "%s\\n" "$station" | sed -n "s/.*tx retries:[[:space:]]*\\([0-9]*\\).*/retries=\\1/p"; '
            + 'printf "%s\\n" "$station" | sed -n "s/.*tx failed:[[:space:]]*\\([0-9]*\\).*/failed=\\1/p"; '
            + 'printf "%s\\n" "$station" | sed -n "s/.*connected time:[[:space:]]*\\([0-9]*\\).*/uptime=\\1/p"; '
            + 'ip -4 -o addr show dev "$d" 2>/dev/null | awk \'{print "ip="$4; exit}\'; '
            + 'ip route | awk -v d="$d" \'$1=="default" && $5==d {print "gw="$3; exit}\'; '
            + 'sed "s/^/mac=/" /sys/class/net/"$d"/address 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: {
                const info = {};
                for (const line of String(text).trim().split("\n")) {
                    const eq = line.indexOf("=");
                    if (eq > 0) info[line.slice(0, eq)] = line.slice(eq + 1);
                }
                root.linkInfo = info;
            }
        }
    }

    // ── The list a person sees ─────────────────────────────────────────────

    readonly property list<var> friendlyWifiNetworks: [...root.wifiNetworks].sort((a, b) => {
        if (a.active !== b.active) return a.active ? -1 : 1;
        // Preferred outranks louder, or a repeater beats the router behind it.
        const pa = root.priorityOf(a.ssid);
        const pb = root.priorityOf(b.ssid);
        if (pa !== pb) return pb - pa;
        return b.strength - a.strength;
    })

    // ── Control ────────────────────────────────────────────────────────────

    function enableWifi(enabled = true): void {
        enableWifiProc.exec(["nmcli", "radio", "wifi", enabled ? "on" : "off"]);
    }

    function toggleWifi(): void { root.enableWifi(!root.wifiEnabled); }

    function rescanWifi(): void {
        root.wifiScanning = true;
        rescanProc.running = true;
    }

    /// `dev wifi connect`, not `connection up`: this one creates the profile.
    function connectToWifiNetwork(accessPoint: WifiAccessPoint): void {
        accessPoint.askingPassword = false;
        root.wifiConnectTarget = accessPoint;
        connectProc.exec(["nmcli", "dev", "wifi", "connect", accessPoint.ssid]);
    }

    function disconnectWifiNetwork(): void {
        if (root.active) disconnectProc.exec(["nmcli", "connection", "down", root.active.ssid]);
    }

    /// NetworkManager's own check URL, which a captive portal intercepts.
    function openPublicWifiPortal(): void {
        Quickshell.execDetached(["xdg-open", "https://nmcheck.gnome.org/"]);
    }

    /// Through the environment: an argv is world-readable.
    function changePassword(network: WifiAccessPoint, password: string, username = ""): void {
        network.askingPassword = false;
        changePasswordProc.exec({
            environment: { PASSWORD: password, SSID: network.ssid },
            command: ["bash", "-c", 'nmcli connection modify "$SSID" wifi-sec.psk "$PASSWORD"']
        });
    }

    Process { id: enableWifiProc }

    Process {
        id: connectProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: SplitParser { onRead: getNetworksProc.running = true }
        stderr: SplitParser {
            onRead: line => {
                if (line.includes("Secrets were required") && root.wifiConnectTarget)
                    root.wifiConnectTarget.askingPassword = true;
            }
        }
        onExited: exitCode => {
            if (root.wifiConnectTarget)
                root.wifiConnectTarget.askingPassword = (exitCode !== 0);
            root.wifiConnectTarget = null;
        }
    }

    Process {
        id: disconnectProc
        stdout: SplitParser { onRead: getNetworksProc.running = true }
    }

    Process {
        id: changePasswordProc
        // Retry the connection with the new secret.
        onExited: {
            connectProc.running = false;
            connectProc.running = true;
        }
    }

    Process {
        id: rescanProc
        command: ["nmcli", "dev", "wifi", "list", "--rescan", "yes"]
        // onExited, not a SplitParser: nmcli prints its header before the scan
        // finishes, so reading line one queries the list mid-scan.
        onExited: {
            root.wifiScanning = false;
            getNetworksProc.running = true;
        }
    }

    // ── Refresh ────────────────────────────────────────────────────────────

    function update(): void {
        connectionTypeProc.running = true;
        radioStateProc.running = true;
        networkNameProc.running = true;
        networkStrengthProc.running = true;
        // Connecting creates a profile and forgetting deletes one.
        if (!savedProfilesProc.running) savedProfilesProc.running = true;
    }

    /// The only thing that drives a refresh. Nothing here is on a timer.
    Process {
        id: monitorProc
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: root.update() }
    }

    Process {
        id: connectionTypeProc
        running: true
        environment: ({ LANG: "C", LC_ALL: "C" })
        // Both at once: "connected" plus not-"full" is a captive portal.
        command: ["sh", "-c",
            "nmcli -t -f TYPE,STATE d status; echo ---; nmcli -t -f CONNECTIVITY g"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [deviceBlock, connectivityBlock] = String(text).split("---");
                const connectivity = (connectivityBlock ?? "").trim();  // none|portal|limited|full

                let ethernet = false;
                let wifi = false;
                let status = "disconnected";

                for (const line of (deviceBlock ?? "").trim().split("\n")) {
                    const [type, state] = root.splitTerse(line);
                    if (type === "ethernet" && state === "connected") ethernet = true;
                    if (type !== "wifi") continue;

                    if (state === "connected") {
                        // Associated but with no route out.
                        const online = connectivity === "full";
                        wifi = online;
                        status = online ? "connected" : "limited";
                    } else if (state === "unavailable") status = "disabled";
                    else if (state.startsWith("connecting")) status = "connecting";
                    else status = "disconnected";
                }

                root.wifiStatus = status;
                root.ethernet = ethernet;
                root.wifi = wifi;
            }
        }
    }

    Process {
        id: radioStateProc
        running: true
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["nmcli", "radio", "wifi"]
        stdout: StdioCollector {
            onStreamFinished: root.wifiEnabled = text.trim() === "enabled"
        }
    }

    Process {
        id: networkNameProc
        running: true
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["sh", "-c", "nmcli -t -f NAME c show --active | head -1"]
        stdout: StdioCollector {
            onStreamFinished: root.networkName = text.trim()
        }
    }

    Process {
        id: networkStrengthProc
        running: true
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["sh", "-c",
            "nmcli -t -f IN-USE,SIGNAL d wifi | awk -F: '$1==\"*\"{print $2; exit}'"]
        stdout: StdioCollector {
            onStreamFinished: root.networkStrength = parseInt(text.trim()) || 0
        }
    }

    // ── The scan list ──────────────────────────────────────────────────────

    Process {
        id: getNetworksProc
        running: true
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["nmcli", "-t", "-f", "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY", "d", "w"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = new Map();

                for (const line of String(text).trim().split("\n")) {
                    const f = root.splitTerse(line);
                    if (f.length < 4) continue;

                    const ap = {
                        active: f[0] === "yes",
                        strength: parseInt(f[1]) || 0,
                        // "2412 MHz" — take the number.
                        frequency: parseInt(f[2]) || 0,
                        ssid: f[3],
                        bssid: f[4] ?? "",
                        security: f[5] ?? ""
                    };
                    if (!ap.ssid) continue;   // hidden networks have nothing to show

                    // One row per SSID, else a mesh lists its every node.
                    const existing = seen.get(ap.ssid);
                    if (!existing
                        || (ap.active && !existing.active)
                        || (!existing.active && ap.strength > existing.strength))
                        seen.set(ap.ssid, ap);
                }

                const fresh = Array.from(seen.values());
                const live = root.wifiNetworks;
                const same = (a, b) => a.ssid === b.ssid && a.bssid === b.bssid
                                    && a.frequency === b.frequency;

                // In place, not rebuilt: delegates bind to these objects.
                for (let i = live.length - 1; i >= 0; i--) {
                    if (!fresh.some(n => same(n, live[i])))
                        live.splice(i, 1).forEach(n => n.destroy());
                }
                for (const network of fresh) {
                    const match = live.find(n => same(network, n));
                    if (match) match.lastIpcObject = network;
                    else live.push(accessPointComponent.createObject(root, {
                        lastIpcObject: network
                    }));
                }
            }
        }
    }

    Component {
        id: accessPointComponent
        WifiAccessPoint {}
    }
}
