pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Per-app firewall: OpenSnitch through snitch-bridge, or, while OpenSnitch is stopped and
 * vitals-netd runs, Vitals (per-app traffic and block rules in the kernel, `vitals net`).
 * The bridge (snitch-bridge) writes the live
 * state to ~/.local/state/snitch-bridge/state.json and reads commands from
 * commands.jsonl; until it runs, `demo` shows sample data so the UI can be judged.
 */
Singleton {
    id: root

    readonly property string dir: `${Quickshell.env("HOME")}/.local/state/snitch-bridge`
    property var state: null
    /// OpenSnitch stopped and vitals-netd counting: Vitals is the engine (apps, bytes, block rules;
    /// no modes, ports or rule list)
    readonly property bool vitalsEngine: !engineRunning && netdAlive
    property bool netdAlive: false
    /// Sample data until an engine is connected, so the layout can be judged.
    readonly property bool demo: !vitalsEngine && !(state?.connected ?? false)
    /// Bridge running but opensnitchd not connected to it.
    readonly property bool engineDown: !(state?.connected ?? false)
    /// Real data has no per-app bytes; shares fall back to connections.
    readonly property bool hasBytes: apps.some(a => (a.down ?? 0) + (a.up ?? 0) > 0)
    function share(a) {
        if (hasBytes) return ((a.down ?? 0) + (a.up ?? 0)) / Math.max(1, totalDown + totalUp);
        return (a.conns ?? 0) / Math.max(1, apps.reduce((n, x) => n + (x.conns ?? 0), 0));
    }
    readonly property var s: vitalsEngine ? vitalsState : demo ? demoState : state

    readonly property bool enabled: s.enabled
    /// "learn" (allow + record) | "ask" | "block" (block new apps)
    readonly property string mode: s.mode
    readonly property var apps: s.apps
    readonly property var ports: s.ports
    readonly property string profile: s.profile
    readonly property var log: s.log
    readonly property var events: s.events ?? []
    readonly property var ruleList: s.ruleList ?? []
    readonly property var stats: s.stats ?? ({})
    readonly property int blockedToday: s.blockedToday

    property bool watching: false
    /// Selected tab of the firewall panel (also settable over IPC).
    property string panelTab: "apps"

    // ── Engine (opensnitchd) ────────────────────────────────────────
    /// "active" | "inactive" | "failed" … from systemctl.
    property string engineState: "unknown"
    property bool engineAutostart: false
    /// The daemon must call the bridge at 127.0.0.1:50051 (see snitch-bridge).
    property bool addressOk: true
    readonly property bool engineRunning: engineState === "active"
    /// Running but not talking to the bridge: every new connection waits for a
    /// UI that never answers. This stalled games at load and crashed skate.
    readonly property bool stalled: engineRunning && !(state?.connected ?? false)
    property string busy: ""

    Timer {
        interval: 3000
        repeat: true
        triggeredOnStart: true
        running: root.watching
        onTriggered: if (!engineProc.running) engineProc.running = true
    }
    Process {
        id: engineProc
        command: ["sh", "-c", "systemctl is-active opensnitchd; systemctl is-enabled opensnitchd; grep -q '\"Address\": *\"127.0.0.1:50051\"' /etc/opensnitchd/default-config.json && echo addr-ok || echo addr-bad; [ -n \"$(find /run/vitals/net.json -newermt '-6 seconds' 2>/dev/null)\" ] && echo netd-on || echo netd-off"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                root.engineState = l[0] ?? "unknown";
                root.engineAutostart = (l[1] ?? "") === "enabled";
                root.addressOk = (l[2] ?? "") === "addr-ok";
                root.netdAlive = (l[3] ?? "") === "netd-on";
            }
        }
    }
    // Privileged actions go through pkexec (one password prompt each).
    function privileged(label, script) {
        root.busy = label;
        privProc.exec(["pkexec", "sh", "-c", script]);
    }
    Process {
        id: privProc
        onExited: { root.busy = ""; engineProc.running = true }
    }
    function startEngine() { privileged("start", "systemctl start opensnitchd") }
    function stopEngine() { privileged("stop", "systemctl stop opensnitchd") }
    function setAutostart(on) { privileged("autostart", on ? "systemctl enable opensnitchd" : "systemctl disable opensnitchd") }
    function fixAddress() {
        privileged("fix", "sed -i 's|\"Address\": *\"[^\"]*\"|\"Address\":\"127.0.0.1:50051\"|' /etc/opensnitchd/default-config.json && systemctl restart opensnitchd");
    }

    readonly property real totalDown: (vitalsEngine ? undefined : state?.totalDown) ?? apps.reduce((n, a) => n + (a.down ?? 0), 0)
    readonly property real totalUp: (vitalsEngine ? undefined : state?.totalUp) ?? apps.reduce((n, a) => n + (a.up ?? 0), 0)
    readonly property int totalConns: apps.reduce((n, a) => n + (a.conns ?? 0), 0)
    /// Last 60 samples of { down, up } in bytes/s, newest last.
    property var history: []
    Timer {
        interval: 1000
        repeat: true
        running: root.watching
        onTriggered: {
            if (root.demo) root.jitterDemo();
            const h = root.history.slice(-59);
            h.push({ down: root.totalDown, up: root.totalUp });
            root.history = h;
        }
    }

    // The bridge rewrites state.json ~2.6×/s (71 KB). Read it only while the
    // panel is open, at most once a second, and keep every section that did
    // not change as the SAME array, so its rows are not rebuilt.
    FileView {
        id: stateFile
        path: root.watching ? `${root.dir}/state.json` : ""
        watchChanges: root.watching
        onFileChanged: if (!reloadThrottle.running) reloadThrottle.start()
        onLoaded: root.ingest(text())
        onLoadFailed: root.state = null
    }
    Timer {
        id: reloadThrottle
        interval: 1000
        onTriggered: stateFile.reload()
    }
    property string lastText: ""
    function ingest(t) {
        if (t === root.lastText) return;
        root.lastText = t;
        let next;
        try { next = JSON.parse(t) } catch (e) { root.state = null; return }
        const prev = root.state;
        if (prev) {
            for (const k of Object.keys(next)) {
                const a = prev[k], b = next[k];
                if (a !== undefined && typeof b === "object" && b !== null && JSON.stringify(a) === JSON.stringify(b))
                    next[k] = a;    // unchanged: keep the old array → no rebuild
            }
        }
        root.state = next;
    }

    // Commands: one JSON object per line, consumed by the bridge.
    function send(cmd) {
        if (root.demo) { root.applyDemo(cmd); return }
        cmdProc.exec(["sh", "-c", 'mkdir -p "$1" && printf "%s\\n" "$2" >> "$1/commands.jsonl"', "sh", root.dir, JSON.stringify(cmd)])
    }
    Process { id: cmdProc }

    function setEnabled(on) { send({ cmd: "enable", on }) }
    function setMode(m) { send({ cmd: "mode", mode: m }) }
    function setAppAction(path, action) {   // allow | block | ask
        if (root.vitalsEngine) { root.vitalsRule(path, action === "block"); return }
        send({ cmd: "app", path, action })
    }
    function setPort(id, open) { send({ cmd: "port", id, open }) }
    function setProfile(p) { send({ cmd: "profile", profile: p }) }
    function setRuleEnabled(name, on) { send({ cmd: "rule-enable", name, on }) }
    function deleteRule(name) { send({ cmd: "rule-delete", name }) }

    function fmtRate(bps) {
        if (bps < 1) return "0";
        const u = ["B", "KB", "MB", "GB"];
        let i = 0, v = bps;
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++ }
        return `${v < 10 && i > 0 ? v.toFixed(1) : Math.round(v)} ${u[i]}/s`;
    }

    // ── Vitals engine ────────────────────────────────────────────────────
    // `vitals net --json`: every app with traffic or a rule, its bytes from the kernel
    // (vitals-netd), and whether it is blocked. Read while the panel is open.
    readonly property string vitalsBin: `${Quickshell.env("HOME")}/.local/bin/vitals`
    property var vitalsApps: []
    readonly property var vitalsState: ({
        connected: true, enabled: true, mode: "", profile: "", blockedToday: 0,
        apps: root.vitalsApps, ports: [], log: [], events: [], ruleList: [], stats: ({})
    })
    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.watching && root.vitalsEngine
        onTriggered: if (!vitalsProc.running) vitalsProc.running = true
    }
    Process {
        id: vitalsProc
        command: [root.vitalsBin, "net", "--json", "-n", "40"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list;
                try { list = JSON.parse(text) } catch (e) { return }
                // rules reach only this user's apps: the system's own stay listed, without a switch
                root.vitalsApps = (list ?? []).map(a => ({
                    path: a.name, name: a.name, icon: String(a.name).toLowerCase(),
                    action: a.blocked ? "block" : "allow", own: a.own,
                    down: a.down_bps ?? 0, up: a.up_bps ?? 0,
                    conns: (a.tcp ?? 0) + (a.udp ?? 0),
                    hosts: a.blocked && (a.dropped_pps ?? 0) >= 1
                        ? [`dropping ${Math.round(a.dropped_pps)} packets/s`]
                        : (a.remotes ?? [])
                }));
            }
        }
    }
    function vitalsRule(name, block) {
        ruleProc.exec([root.vitalsBin, "net", block ? "block" : "unblock", name]);
    }
    Process {
        id: ruleProc
        onExited: vitalsProc.running = true
    }

    // ── Demo data ────────────────────────────────────────────────────────
    property var demoState: ({
        enabled: true,
        mode: "learn",
        profile: "home",
        blockedToday: 14,
        apps: [
            { path: "/usr/lib/tela-zen/tela-zen", name: "tela-zen", icon: "tela-zen", action: "allow", down: 2180000, up: 41000, conns: 38,
              hosts: ["music.youtube.com:443", "rr3---sn-4g5e6nsz.googlevideo.com:443", "github.com:443"] },
            { path: "/opt/discord/Discord", name: "Discord", icon: "discord", action: "allow", down: 40200, up: 9100, conns: 6,
              hosts: ["gateway.discord.gg:443", "media.discordapp.net:443"] },
            { path: "/usr/bin/steam", name: "Steam", icon: "steam", action: "allow", down: 0, up: 0, conns: 3,
              hosts: ["api.steampowered.com:443", "cm4-fra1.steamserver.net:27017"] },
            { path: "Skate.exe", name: "skate.", icon: "steam_icon_3354750", action: "ask", down: 0, up: 12400, conns: 2,
              hosts: ["163.123.x.x:3659 udp"] },
            { path: "/usr/bin/rescrobbled", name: "rescrobbled", icon: "", action: "allow", down: 120, up: 80, conns: 1,
              hosts: ["ws.audioscrobbler.com:443"] },
            { path: "/usr/lib/telemetry/agent", name: "telemetry-agent", icon: "", action: "block", down: 0, up: 0, conns: 0,
              hosts: ["collect.example-metrics.com:443"] },
        ],
        ports: [
            { id: "kdeconnect", name: "KDE Connect", detail: "1714–1764 tcp/udp", open: true },
            { id: "localsend", name: "LocalSend", detail: "53317 tcp/udp", open: true },
            { id: "steamremote", name: "Steam Remote Play", detail: "27031–27036 udp · 27036–27037 tcp", open: false },
            { id: "sunshine", name: "Sunshine streaming", detail: "47984–48010", open: false },
        ],
        log: [
            { t: "14:02:11", app: "telemetry-agent", dest: "collect.example-metrics.com:443", verdict: "block" },
            { t: "14:01:58", app: "tela-zen", dest: "music.youtube.com:443", verdict: "allow" },
            { t: "14:01:40", app: "skate.", dest: "163.123.x.x:3659 udp", verdict: "ask" },
            { t: "14:00:12", app: "Discord", dest: "gateway.discord.gg:443", verdict: "allow" },
            { t: "13:58:03", app: "rescrobbled", dest: "ws.audioscrobbler.com:443", verdict: "allow" },
        ],
        events: [
            { t: "14:02:11", verdict: "block", rule: "deny-telemetry-agent", proto: "tcp", src: "192.168.1.42", sport: 51822, dst: "34.117.59.81", host: "collect.example-metrics.com", dport: 443, uid: 1000, pid: 41822, path: "/usr/lib/telemetry/agent", app: "telemetry-agent", args: "/usr/lib/telemetry/agent --daemon --interval 300", cwd: "/" },
            { t: "14:01:58", verdict: "allow", rule: "allow-tela-zen", proto: "tcp", src: "192.168.1.42", sport: 50214, dst: "142.250.185.110", host: "music.youtube.com", dport: 443, uid: 1000, pid: 2871, path: "/usr/lib/tela-zen/tela-zen", app: "tela-zen", args: "/usr/lib/tela-zen/tela-zen -contentproc -childID 12 -isForBrowser", cwd: "/home/caesar" },
            { t: "14:01:40", verdict: "allow", rule: "(learn) new app, once", proto: "udp", src: "192.168.1.42", sport: 3659, dst: "163.123.192.20", host: "", dport: 3659, uid: 1000, pid: 52110, path: "/home/caesar/.local/share/Steam/steamapps/common/Proton - Experimental/files/bin/wine64-preloader", app: "wine64-preloader", args: "Z:\\mnt\\storage\\Games\\ReSkate\\Skate.exe -reskate", cwd: "/opt/games/ReSkate" },
            { t: "14:00:12", verdict: "allow", rule: "allow-discord", proto: "tcp", src: "192.168.1.42", sport: 49920, dst: "162.159.135.234", host: "gateway.discord.gg", dport: 443, uid: 1000, pid: 3302, path: "/home/caesar/.config/discord/app-1.0.161/Discord", app: "Discord", args: "Discord --type=utility --utility-sub-type=network.mojom.NetworkService", cwd: "/home/caesar" },
            { t: "13:59:47", verdict: "allow", rule: "allow-system-dns", proto: "udp", src: "127.0.0.1", sport: 40211, dst: "127.0.0.53", host: "", dport: 53, uid: 977, pid: 711, path: "/usr/lib/systemd/systemd-resolved", app: "systemd-resolved", args: "/usr/lib/systemd/systemd-resolved", cwd: "/" },
            { t: "13:58:03", verdict: "allow", rule: "allow-rescrobbled", proto: "tcp", src: "192.168.1.42", sport: 48802, dst: "130.211.19.189", host: "ws.audioscrobbler.com", dport: 443, uid: 1000, pid: 1402, path: "/home/caesar/.cargo/bin/rescrobbled", app: "rescrobbled", args: "/home/caesar/.cargo/bin/rescrobbled", cwd: "/home/caesar" },
        ],
        ruleList: [
            { name: "allow-reskate", action: "allow", duration: "always", enabled: true, precedence: true, nolog: false, condition: "process.command ~ (?i)(skate\\.exe|reskatelauncher\\.exe)" },
            { name: "allow-tela-zen", action: "allow", duration: "always", enabled: true, precedence: false, nolog: false, condition: "process.path == /usr/lib/tela-zen/tela-zen" },
            { name: "allow-discord", action: "allow", duration: "always", enabled: true, precedence: false, nolog: false, condition: "process.path == /home/caesar/.config/discord/app-1.0.161/Discord" },
            { name: "allow-system-dns", action: "allow", duration: "always", enabled: true, precedence: true, nolog: true, condition: "process.path == /usr/lib/systemd/systemd-resolved  AND  dest.port == 53" },
            { name: "deny-telemetry-agent", action: "deny", duration: "always", enabled: true, precedence: false, nolog: false, condition: "process.path == /usr/lib/telemetry/agent" },
            { name: "allow-steam-cm", action: "allow", duration: "until restart", enabled: false, precedence: false, nolog: false, condition: "process.path == /usr/bin/steam  AND  dest.host ~ ^(.*\\.)?steamserver\\.net$" },
        ],
        stats: {
            daemonVersion: "1.7.2", uptime: 15420, rules: 6, connections: 4821, accepted: 4790, dropped: 14, ignored: 17,
            dns: 1203, ruleHits: 4644, ruleMisses: 177,
            byHost: [{ key: "music.youtube.com", count: 812 }, { key: "rr3---sn-4g5e6nsz.googlevideo.com", count: 640 }, { key: "gateway.discord.gg", count: 211 }, { key: "github.com", count: 96 }, { key: "ws.audioscrobbler.com", count: 41 }, { key: "collect.example-metrics.com", count: 14 }],
            byPort: [{ key: "443", count: 4102 }, { key: "53", count: 412 }, { key: "3659", count: 160 }, { key: "80", count: 87 }, { key: "27017", count: 60 }],
            byProto: [{ key: "tcp", count: 4380 }, { key: "udp", count: 441 }],
            byUid: [{ key: "1000", count: 4402 }, { key: "977", count: 412 }, { key: "0", count: 7 }],
            byExecutable: [{ key: "/usr/lib/tela-zen/tela-zen", count: 2810 }, { key: "/home/caesar/.config/discord/app-1.0.161/Discord", count: 611 }, { key: "/usr/lib/systemd/systemd-resolved", count: 412 }, { key: "wine64-preloader (skate.)", count: 160 }],
        },
    })

    // Demo traffic wanders so the graph moves.
    function jitterDemo() {
        const d = JSON.parse(JSON.stringify(root.demoState));
        d.apps.forEach(a => {
            if (a.action === "block") return;
            const f = 0.55 + Math.random() * 0.9;
            a.down = Math.max(0, Math.round((a.base = a.base ?? a.down) * f));
            a.up = Math.max(0, Math.round((a.baseUp = a.baseUp ?? a.up) * f));
        });
        root.demoState = d;
    }

    function applyDemo(c) {
        const d = JSON.parse(JSON.stringify(root.demoState));
        if (c.cmd === "enable") d.enabled = c.on;
        if (c.cmd === "mode") d.mode = c.mode;
        if (c.cmd === "profile") d.profile = c.profile;
        if (c.cmd === "app") d.apps.forEach(a => { if (a.path === c.path) a.action = c.action });
        if (c.cmd === "port") d.ports.forEach(p => { if (p.id === c.id) p.open = c.open });
        root.demoState = d;
    }
}
