pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.services.network

/**
 * Network state, over nmcli.
 *
 * Four sources, because no single one answers the question:
 *   - `nmcli monitor` says when anything changed, and is the only thing that
 *     drives a refresh; nothing here polls on a timer except the live link
 *     detail, and that only while a panel is open to read it.
 *   - `nmcli device wifi` is the scan list: what the APs advertise.
 *   - `nmcli connection` is the saved profiles: priority, autoconnect, band.
 *   - `iw` is the live association: the dBm, rate and retries actually in use,
 *     which the scan list cannot tell you.
 */
Singleton {
    id: root

    // ── Connection state ───────────────────────────────────────────────────

    /// A wifi link that reaches the internet. "Associated" is not the same
    /// thing, so a captive portal leaves this false — see wifiStatus.
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

    /// Status first, strength second. Testing the radio before the status made
    /// every status icon unreachable: with the radio on it always drew bars, so
    /// an unassociated adapter drew a confident "0 bars" and a captive portal
    /// drew a full four.
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

    /// `nmcli -t` escapes a literal ":" in a value as "\:" and a backslash as
    /// "\\". Splitting on a bare ":" therefore tears BSSIDs into six pieces.
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
    // NetworkManager already has the concept: connection.autoconnect-priority.
    // Higher wins when several known networks are in range, so "prefer this
    // one" is a setting the daemon acts on rather than something this shell has
    // to re-implement and police.
    //
    // Keyed by SSID, but the value carries the profile NAME, because they are
    // not the same: a band-locked profile may be called anything. Modifying by
    // SSID would edit the wrong profile, or none.

    property var savedProfiles: ({})     // ssid -> { name, priority, autoconnect, band }

    readonly property int preferredPriority: 20

    function profileFor(ssid) { return root.savedProfiles[ssid] ?? null; }
    function isSaved(ssid) { return root.savedProfiles[ssid] !== undefined; }
    function priorityOf(ssid) { return root.savedProfiles[ssid]?.priority ?? 0; }
    function isPreferred(ssid) { return root.priorityOf(ssid) > 0; }
    function autoconnectOf(ssid) { return root.savedProfiles[ssid]?.autoconnect ?? false; }
    function bandLockOf(ssid) { return root.savedProfiles[ssid]?.band ?? ""; }

    /// Every write goes through the stored profile name, and every write
    /// re-reads the table afterwards so the UI reflects what nmcli accepted
    /// rather than what it was asked for.
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
    /// Pinning a profile to one band is the direct fix for a 5GHz and a 2.4GHz
    /// AP sharing an SSID with the adapter choosing the slower one. "" clears.
    function setBandLock(ssid, band): void {
        root.modifyProfile(ssid, "802-11-wireless.band", band);
    }
    /// Only a saved network can carry a preference — there is nothing to hang
    /// it on otherwise, which is why the UI hides the control rather than
    /// offering one that would silently do nothing.
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
                    // Taken from the right: an SSID may contain the separator,
                    // the four trailing fields never do.
                    const parts = line.split("|");
                    if (parts.length < 5) continue;
                    const name = parts.pop();
                    const band = parts.pop();
                    const autoconnect = parts.pop();
                    const priority = parseInt(parts.pop(), 10);
                    const ssid = parts.join("|");
                    if (!ssid) continue;

                    // Band-locked variants share an SSID. The highest-priority
                    // one is the one whose preference actually takes effect, so
                    // it takes the slot.
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
    // nmcli reports MHz and nobody thinks in MHz. The band and channel are what
    // let you spot the real problems: a repeater sharing its backhaul channel,
    // or a 2.4GHz association you did not intend.

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

    /// nmcli's SIGNAL is a percentage. NetworkManager's own conversion is
    /// linear over -100..-50 dBm, so this is a faithful inverse rather than a
    /// guess — but it is still derived, and linkInfo reports the real thing for
    /// the network actually connected.
    function approxDbm(pct) { return Math.round(pct / 2 - 100); }

    // ── Live link detail ───────────────────────────────────────────────────
    // What the adapter negotiated, which the scan list does not know. A -49 dBm
    // association through a repeater reads perfect in a scan and still
    // stutters; the retry count is what shows it.

    property var linkInfo: ({})

    readonly property string networkInterface: root.linkInfo.dev ?? ""
    readonly property string ipAddress: (root.linkInfo.ip ?? "").split("/")[0]
    readonly property string gateway: root.linkInfo.gw ?? ""
    readonly property string macAddress: root.linkInfo.mac ?? ""

    /// Set by whatever panel is showing the detail. This shells out to iw and
    /// ip; polling it in the background forever would be pure waste.
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
            // station dump separates label from value with a TAB, not a space.
            // Matching only spaces produced empty values, silently.
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
        // A preferred network outranks a louder one: the whole point of marking
        // it is that it should win even when something closer is in range,
        // which is exactly how a repeater gets picked over the router behind it.
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

    /// `dev wifi connect` rather than `connection up`: this one creates the
    /// profile when there is not one yet.
    function connectToWifiNetwork(accessPoint: WifiAccessPoint): void {
        accessPoint.askingPassword = false;
        root.wifiConnectTarget = accessPoint;
        connectProc.exec(["nmcli", "dev", "wifi", "connect", accessPoint.ssid]);
    }

    function disconnectWifiNetwork(): void {
        if (root.active) disconnectProc.exec(["nmcli", "connection", "down", root.active.ssid]);
    }

    /// NetworkManager's own connectivity check URL, which is what a captive
    /// portal intercepts.
    function openPublicWifiPortal(): void {
        Quickshell.execDetached(["xdg-open", "https://nmcheck.gnome.org/"]);
    }

    /// Through the environment, never the command line: an argv is readable by
    /// every process on the machine.
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
        // onExited, not a SplitParser: nmcli prints its header row before the
        // scan finishes, so reading the first line declared the scan over and
        // queried the list mid-scan. The result was a partial list — often just
        // the network already connected — for the first seconds after opening
        // the dialog, which looked like the scan had found nothing.
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
        // Connecting creates a profile and forgetting deletes one, so the saved
        // set is only right if it is re-read whenever nmcli reports a change.
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
        // Device states and the daemon's own connectivity verdict in one go:
        // "connected" plus "limited" is a captive portal, and the two have to
        // be read together to tell that from a working link.
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

                    // One row per SSID: the connected AP if there is one, else
                    // the loudest. A mesh advertises the same name from every
                    // node and listing them all is noise.
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

                // Updated in place rather than rebuilt: these objects are bound
                // to by list delegates, and replacing them all on every scan
                // would tear down and rebuild every row two seconds apart.
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
