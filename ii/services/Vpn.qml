pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * VPN state and control.
 *
 * Two backends, because they answer different questions:
 *
 *  - NetworkManager (`nmcli`) is the general one. Any VPN with an NM profile
 *    shows up here — OpenVPN, WireGuard, and NordVPN's own NM configs. Always
 *    available on this machine.
 *  - The `nordvpn` CLI, when installed, manages its own daemon and does NOT
 *    create NM profiles for its default (NordLynx) mode, so a purely nmcli
 *    view would show "no VPN" while NordVPN was in fact connected. It is
 *    preferred when present.
 *
 * State updates are event-driven via `nmcli monitor` rather than polled, so an
 * idle machine does no work. The NordVPN side has no event stream, so it is
 * polled — but only while the panel is open (`watching`).
 */
Singleton {
    id: root

    /** Set by the panel while it is visible; gates the NordVPN poll. */
    property bool watching: false

    property bool nordAvailable: false
    property bool connected: false
    /** Server / profile name, e.g. "de1234.nordvpn.com" or "Work VPN". */
    property string activeName: ""
    property string activeCountry: ""
    property string backend: "nm"          // "nord" | "nm"
    property string lastError: ""
    property bool busy: false

    /** NetworkManager VPN profiles: { name, uuid, type, active }. */
    property var profiles: []

    /** Public IP — only populated when explicitly asked for. */
    property string publicIp: ""
    property bool ipChecking: false

    // ── Leak check ────────────────────────────────────────────────────────
    // Most of this is answered locally. Which interface traffic actually
    // leaves by is the strongest signal there is: if a VPN reports "connected"
    // but the default route still points at wlan0, the tunnel is not carrying
    // anything, and no amount of asking a website your IP would tell you why.
    property bool leakChecking: false
    property string exit4: ""      // interface for IPv4
    property string exit6: ""      // interface for IPv6
    property string dnsServers: ""
    property string publicIp6: ""
    property bool leakDone: false

    /** True when an interface name looks like a VPN tunnel. */
    function isTunnel(dev: string): bool {
        return /^(tun|tap|wg|nordlynx|proton|mullvad|ipsec|ppp)/i.test(dev || "");
    }

    /**
     * Findings as { label, value, status } where status is ok | warn | bad.
     * Computed rather than stored so it re-derives whenever any input changes.
     */
    readonly property var findings: {
        if (!root.leakDone) return [];
        const out = [];
        const tun4 = root.isTunnel(root.exit4);
        const tun6 = root.isTunnel(root.exit6);

        out.push({
            label: "IPv4 route",
            value: root.exit4 || "unknown",
            status: !root.connected ? "warn" : (tun4 ? "ok" : "bad")
        });

        if (root.exit6) {
            // The classic leak: IPv4 goes through the tunnel while IPv6 keeps
            // using the physical link, so half your traffic is exposed.
            out.push({
                label: "IPv6 route",
                value: root.exit6,
                status: !root.connected ? "warn" : (tun6 ? "ok" : "bad")
            });
        } else {
            out.push({ label: "IPv6", value: "disabled", status: "ok" });
        }

        // DNS resolving over a non-tunnel link while connected means queries
        // are visible to whoever runs that network, even if the payload is not.
        const dnsOnTunnel = /\b(tun|wg|nordlynx|proton|mullvad)/i.test(root.dnsServers);
        out.push({
            label: "DNS",
            value: root.dnsServers || "unknown",
            status: !root.connected ? "warn" : (dnsOnTunnel ? "ok" : "warn")
        });

        if (root.publicIp)
            out.push({ label: "Public IPv4", value: root.publicIp, status: root.connected ? "ok" : "warn" });
        if (root.publicIp6)
            out.push({ label: "Public IPv6", value: root.publicIp6, status: root.connected ? "ok" : "warn" });

        return out;
    }

    readonly property string verdict: {
        if (!root.leakDone) return "";
        const bad = root.findings.some(f => f.status === "bad");
        const warn = root.findings.some(f => f.status === "warn");
        if (!root.connected) return "No VPN active — this is your real connection";
        if (bad) return "Traffic is NOT going through the tunnel";
        if (warn) return "Tunnelled, but something is worth checking";
        return "Traffic and DNS are going through the tunnel";
    }

    function runLeakCheck(): void {
        root.leakChecking = true;
        leakProc.running = false;
        Qt.callLater(() => leakProc.running = true);
    }

    readonly property string statusText: {
        if (root.busy) return "Working…";
        if (root.connected) return root.activeName || "Connected";
        return "Not connected";
    }

    function refresh(): void {
        detectNord.running = false;
        Qt.callLater(() => detectNord.running = true);
    }

    function connectTo(item): void {
        root.busy = true;
        root.lastError = "";
        if (root.backend === "nord" && item?.country)
            Quickshell.execDetached(["nordvpn", "connect", item.country]);
        else if (item?.uuid)
            Quickshell.execDetached(["nmcli", "connection", "up", "uuid", item.uuid]);
        settle.restart();
    }

    function disconnect(): void {
        root.busy = true;
        root.lastError = "";
        if (root.backend === "nord")
            Quickshell.execDetached(["nordvpn", "disconnect"]);
        else if (root.activeUuid)
            Quickshell.execDetached(["nmcli", "connection", "down", "uuid", root.activeUuid]);
        settle.restart();
    }

    property string activeUuid: ""

    /**
     * Public IP lookup. Deliberately manual: this contacts a third-party
     * service, which is exactly the sort of request a VPN user does not want
     * fired automatically on a timer.
     */
    function checkIp(): void {
        root.ipChecking = true;
        ipProc.running = false;
        Qt.callLater(() => ipProc.running = true);
    }

    // Give the CLI a moment to act, then re-read rather than trusting our
    // optimistic guess about what happened.
    Timer {
        id: settle
        interval: 1200
        onTriggered: { root.busy = false; root.refresh(); }
    }

    Process {
        id: detectNord
        running: true
        command: ["bash", "-c", "command -v nordvpn >/dev/null && echo yes || echo no"]
        stdout: StdioCollector {
            id: nordOut
            onStreamFinished: {
                root.nordAvailable = nordOut.text.trim() === "yes";
                root.backend = root.nordAvailable ? "nord" : "nm";
                nmProc.running = false;
                Qt.callLater(() => nmProc.running = true);
                if (root.nordAvailable) {
                    nordStatus.running = false;
                    Qt.callLater(() => nordStatus.running = true);
                }
            }
        }
    }

    // NetworkManager profiles + which is active.
    Process {
        id: nmProc
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE,STATE", "connection", "show"]
        stdout: StdioCollector {
            id: nmOut
            onStreamFinished: {
                const rows = [];
                let activeName = "", activeUuid = "";
                for (const line of nmOut.text.split("\n")) {
                    if (!line.trim()) continue;
                    // nmcli -t escapes colons inside fields as "\:" — split on
                    // unescaped colons only, or names with colons shift fields.
                    const f = line.split(/(?<!\\):/).map(x => x.replace(/\\:/g, ":"));
                    const [name, uuid, type, state] = f;
                    if (type !== "vpn" && type !== "wireguard") continue;
                    const active = (state || "").toLowerCase() === "activated";
                    rows.push({ name: name, uuid: uuid, type: type, active: active });
                    if (active) { activeName = name; activeUuid = uuid; }
                }
                root.profiles = rows;
                if (root.backend === "nm") {
                    root.connected = activeName !== "";
                    root.activeName = activeName;
                    root.activeUuid = activeUuid;
                    root.activeCountry = "";
                }
            }
        }
    }

    Process {
        id: nordStatus
        command: ["nordvpn", "status"]
        stdout: StdioCollector {
            id: nordOut2
            onStreamFinished: {
                const t = nordOut2.text;
                root.connected = /Status:\s*Connected/i.test(t);
                root.activeName = (t.match(/Hostname:\s*(\S+)/i) || [])[1] ?? "";
                root.activeCountry = (t.match(/Country:\s*(.+)/i) || [])[1]?.trim() ?? "";
            }
        }
    }

    Process {
        id: leakProc
        // One process emitting key=value lines: five separate Processes would
        // race each other and land out of order.
        command: ["bash", "-c", `
            r4=$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* dev \\([^ ]*\\).*/\\1/p' | head -1)
            r6=$(ip -6 route get 2606:4700:4700::1111 2>/dev/null | sed -n 's/.* dev \\([^ ]*\\).*/\\1/p' | head -1)
            dns=$(resolvectl dns 2>/dev/null | sed 's/^Link [0-9]* (\\(.*\\)):/\\1:/' | tr '\\n' ' ' | tr -s ' ')
            [ -z "$dns" ] && dns=$(awk '/^nameserver/{printf "%s ", $2}' /etc/resolv.conf 2>/dev/null)
            echo "r4=$r4"
            echo "r6=$r6"
            echo "dns=$dns"
            echo "ip4=$(curl -fsS --max-time 6 -4 https://ifconfig.co/ip 2>/dev/null | tr -d '\\n')"
            echo "ip6=$(curl -fsS --max-time 6 -6 https://ifconfig.co/ip 2>/dev/null | tr -d '\\n')"
        `]
        stdout: StdioCollector {
            id: leakOut
            onStreamFinished: {
                for (const line of leakOut.text.split("\n")) {
                    const i = line.indexOf("=");
                    if (i < 0) continue;
                    const k = line.slice(0, i), v = line.slice(i + 1).trim();
                    if (k === "r4") root.exit4 = v;
                    else if (k === "r6") root.exit6 = v;
                    else if (k === "dns") root.dnsServers = v;
                    else if (k === "ip4") root.publicIp = v;
                    else if (k === "ip6") root.publicIp6 = v;
                }
                root.leakChecking = false;
                root.leakDone = true;
            }
        }
    }

    Process {
        id: ipProc
        command: ["bash", "-c", "curl -fsS --max-time 6 https://ifconfig.co/ip 2>/dev/null || echo ''"]
        stdout: StdioCollector {
            id: ipOut
            onStreamFinished: {
                root.publicIp = ipOut.text.trim();
                root.ipChecking = false;
            }
        }
    }

    // Event-driven: nmcli emits a line whenever a connection changes state, so
    // the panel stays correct without a timer.
    Process {
        id: monitor
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (/vpn|wireguard|connected|disconnected/i.test(line))
                    root.refresh();
            }
        }
    }

    // NordVPN has no event stream; poll only while the panel is open.
    Timer {
        running: root.watching && root.nordAvailable
        interval: 4000
        repeat: true
        onTriggered: {
            nordStatus.running = false;
            Qt.callLater(() => nordStatus.running = true);
        }
    }
}
