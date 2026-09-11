pragma Singleton
pragma ComponentBehavior: Bound

// Live system stats for the on-screen HUD.
//
// Everything here comes straight from /proc and /sys through FileView — no
// helper binary and no subprocess per tick. A Rust daemon was considered and
// rejected: these are plain counter files, the work is subtracting two
// integers, and a helper would add a build step, a process to supervise and an
// IPC hop for no measurable gain. Where a helper WOULD earn its place is
// per-process accounting (which needs eBPF or cgroup walking) — that already
// exists separately under scripts/net.
//
// Counters are cumulative, so every rate is (now - last) / elapsed. The first
// tick after activation is discarded, otherwise it would report the whole
// uptime's traffic as one second's worth.

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Polling only runs while something is showing the HUD: these are cheap
    // reads, but "cheap" times 1Hz forever is still battery for nothing.
    property bool active: false
    property int intervalMs: 1000
    // The compositor-FPS counter uses a FrameAnimation, which forces the whole
    // shell to render at full refresh rate for as long as it runs — that alone
    // pegs a core whenever the HUD is shown. Off by default; opt in only if you
    // actually need the live FPS readout.
    property bool fpsCounterEnabled: false

    // ── Network ─────────────────────────────────────────────────────────
    property string iface: ""          // "" = auto-pick the busiest
    // Interfaces that have actually carried traffic — the settings picker
    // offers these rather than every virtual device the kernel invented.
    property var interfaces: []
    property real netRxBps: 0
    property real netTxBps: 0
    property real netRxTotal: 0
    property real netTxTotal: 0

    // ── Link quality ────────────────────────────────────────────────────
    // Three independent things, deliberately not merged into one "packet
    // loss" number, because they fail for different reasons and a single
    // figure would hide which one is happening:
    //   netLossPct   packets the NIC itself dropped — a local problem
    //                (driver, buffers, saturated wifi)
    //   tcpRetransPct  segments the kernel had to send again — the classic
    //                proxy for loss SOMEWHERE on the path
    //   pingLossPct  probes that never came back from the peer, plus the RTT
    //                that actually decides whether a game feels laggy
    property real netDropTotal: 0
    property real netErrTotal: 0
    property real netDropRate: 0     // dropped packets/s
    property real netErrRate: 0      // errored packets/s
    property real netLossPct: 0      // NIC drops as % of packets this tick
    property real tcpRetransPct: 0   // retransmitted segments, % this tick
    property real tcpRetransRate: 0  // retransmits/s
    property int  tcpEstab: 0        // open TCP connections
    property real pingMs: -1         // -1 = no measurement yet
    property real pingLossPct: -1
    property string pingTarget: ""
    property string pingSource: ""   // which app the target came from

    // ── CPU / memory ────────────────────────────────────────────────────
    property real cpuPct: 0
    property real memUsedPct: 0
    property real memUsedGb: 0
    property real memTotalGb: 0

    // ── GPU ─────────────────────────────────────────────────────────────
    property real gpuPct: 0
    property real vramUsedGb: 0
    property real vramTotalGb: 0

    // ── Thermals ────────────────────────────────────────────────────────
    property real cpuTemp: 0
    property real gpuTemp: 0
    property real fanRpm: 0

    // ── Everything else the machine will tell us ────────────────────────
    property real cpuFreqGhz: 0
    property real load1: 0
    property real load5: 0
    property real swapUsedGb: 0
    property real swapTotalGb: 0
    property real diskReadBps: 0
    property real diskWriteBps: 0
    property real battPct: 0
    property real battWatts: 0
    property real gpuWatts: 0
    property real gpuClockMhz: 0
    property int procCount: 0
    property real uptimeSec: 0

    readonly property real vramPct: root.vramTotalGb > 0
        ? 100 * root.vramUsedGb / root.vramTotalGb : 0

    property var _prevDisk: null

    // ── More stats ──────────────────────────────────────────────────────
    property real wifiDbm: 0
    property real wifiMbit: 0
    property string wifiSsid: ""
    property real cachedGb: 0
    property real zramGb: 0
    property string battStatus: ""
    property real battTimeH: 0
    property real coreMaxPct: 0
    property int coreCount: 0
    property real ctxPerSec: 0
    property real rootFreeGb: 0
    property real rootUsedPct: 0
    property var _prevCtx: null

    // Signal strength as a 0-100 bar rather than raw dBm, since -47 dBm means
    // nothing at a glance. -30 is excellent, -90 is unusable.
    readonly property real wifiPct: root.wifiDbm === 0 ? 0
        : Math.max(0, Math.min(100, 2 * (root.wifiDbm + 100)))

    FileView { id: fCtx; path: "file:///proc/stat"
        onLoaded: {
            const m = /ctxt\s+(\d+)/.exec(String(fCtx.text()));
            if (!m) return;
            const v = parseFloat(m[1]);
            if (root._prevCtx !== null)
                root.ctxPerSec = Math.max(0, (v - root._prevCtx) / (root.intervalMs / 1000));
            root._prevCtx = v;
        }
    }

    FileView { id: fCached; path: "file:///proc/meminfo"
        onLoaded: {
            const t = String(fCached.text());
            const c = /^Cached:\s+(\d+)/m.exec(t);
            if (c) root.cachedGb = parseFloat(c[1]) / 1024 / 1024;
        }
    }

    FileView { id: fBattSt; path: "file:///sys/class/power_supply/BAT0/status"
        onLoaded: root.battStatus = String(fBattSt.text()).trim() }

    // Per-core: the HOTTEST core, because an all-core average hides a single
    // pinned thread, which is exactly the case you want to see.
    FileView { id: fCores; path: "file:///proc/stat"
        property var prev: ({})
        onLoaded: {
            const lines = String(fCores.text()).split("\n");
            let maxPct = 0, n = 0;
            const now = ({});
            for (let i = 0; i < lines.length; ++i) {
                const p = lines[i].trim().split(/\s+/);
                if (!/^cpu\d+$/.test(p[0])) continue;
                n++;
                let total = 0;
                for (let k = 1; k < p.length; ++k) total += parseFloat(p[k]) || 0;
                const idle = (parseFloat(p[4]) || 0) + (parseFloat(p[5]) || 0);
                now[p[0]] = { total: total, idle: idle };
                const pr = fCores.prev[p[0]];
                if (pr) {
                    const dt = total - pr.total, di = idle - pr.idle;
                    if (dt > 0) maxPct = Math.max(maxPct, 100 * (1 - di / dt));
                }
            }
            fCores.prev = now;
            root.coreCount = n;
            if (maxPct > 0) root.coreMaxPct = maxPct;
        }
    }

    Process {
        id: wifiProbe
        running: false
        command: ["bash", "-c",
            "iw dev 2>/dev/null | awk '/Interface/{i=$2} END{print i}' | while read d; do "
            + "iw dev \"$d\" link 2>/dev/null | awk '"
            + "/SSID/{s=$2} /signal/{g=$2} /tx bitrate/{b=$3} "
            + "END{print s\"|\"g\"|\"b}'; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = String(text).trim().split("|");
                if (p.length < 3) return;
                root.wifiSsid = p[0] || "";
                root.wifiDbm = parseFloat(p[1]) || 0;
                root.wifiMbit = parseFloat(p[2]) || 0;
            }
        }
    }

    Process {
        id: dfProbe
        running: false
        command: ["bash", "-c", "df -B1 --output=avail,pcent / | tail -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = String(text).trim().split(/\s+/);
                if (p.length < 2) return;
                root.rootFreeGb = (parseFloat(p[0]) || 0) / 1024 / 1024 / 1024;
                root.rootUsedPct = parseFloat(p[1].replace("%", "")) || 0;
            }
        }
    }

    // These two shell out, so they run every 5th tick rather than every tick:
    // wifi and disk-free do not change fast enough to justify 1Hz subprocesses.
    property int slowTick: 0

    // Extra sysfs nodes are discovered once, by capability, rather than
    // hardcoded: hwmon numbering is not stable across boots and the GPU's
    // hwmon index moves with driver load order.
    property string gpuHwmon: ""
    property string fanPath: ""
    Process {
        id: extraFinder
        running: true
        command: ["bash", "-c",
            "g=$(ls -d /sys/class/drm/card1/device/hwmon/hwmon*/ 2>/dev/null | head -1); "
            + "echo \"GPU=$g\"; "
            + "for h in /sys/class/hwmon/hwmon*/; do "
            + "[ -r \"$h/fan1_input\" ] && { echo \"FAN=$h/fan1_input\"; break; }; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = String(text);
                const g = /GPU=(\S+)/.exec(t);
                const f = /FAN=(\S+)/.exec(t);
                if (g) root.gpuHwmon = g[1];
                if (f) root.fanPath = f[1];
            }
        }
    }

    FileView { id: fLoad;  path: "file:///proc/loadavg"
        onLoaded: { const p = String(fLoad.text()).trim().split(/\s+/);
                    root.load1 = parseFloat(p[0]) || 0; root.load5 = parseFloat(p[1]) || 0;
                    const pc = /\d+\/(\d+)/.exec(String(fLoad.text()));
                    if (pc) root.procCount = parseInt(pc[1]); } }

    FileView { id: fUp;    path: "file:///proc/uptime"
        onLoaded: root.uptimeSec = parseFloat(String(fUp.text()).split(" ")[0]) || 0 }

    // In-game time: runtime of the current game process. Its start time
    // (field 22 of /proc/PID/stat, USER_HZ=100 ticks since boot) against system
    // uptime — no subprocess, one tiny read per tick, only while a game is up.
    property int gamePid: 0
    property real gamePlaytimeSec: 0
    onGamePidChanged: if (root.gamePid <= 0) root.gamePlaytimeSec = 0
    FileView { id: fGameStat
        path: root.gamePid > 0 ? ("file:///proc/" + root.gamePid + "/stat") : ""
        onLoaded: {
            const t = String(fGameStat.text());
            const rest = t.slice(t.lastIndexOf(")") + 1).trim().split(/\s+/);
            const ticks = parseFloat(rest[19]);   // field 22 overall = starttime
            if (isFinite(ticks)) root.gamePlaytimeSec = Math.max(0, root.uptimeSec - ticks / 100);
        }
    }

    FileView { id: fFreq;  path: "file:///sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
        onLoaded: root.cpuFreqGhz = (parseFloat(String(fFreq.text()).trim()) || 0) / 1000000 }

    FileView { id: fBatt;  path: "file:///sys/class/power_supply/BAT0/capacity"
        onLoaded: root.battPct = parseFloat(String(fBatt.text()).trim()) || 0 }
    FileView { id: fBattW; path: "file:///sys/class/power_supply/BAT0/power_now"
        onLoaded: root.battWatts = (parseFloat(String(fBattW.text()).trim()) || 0) / 1000000 }

    FileView { id: fGpuT;  path: root.gpuHwmon.length > 0 ? "file://" + root.gpuHwmon + "temp1_input" : ""
        onLoaded: root.gpuTemp = (parseFloat(String(fGpuT.text()).trim()) || 0) / 1000 }
    FileView { id: fGpuW;  path: root.gpuHwmon.length > 0 ? "file://" + root.gpuHwmon + "power1_average" : ""
        onLoaded: root.gpuWatts = (parseFloat(String(fGpuW.text()).trim()) || 0) / 1000000 }
    FileView { id: fGpuC;  path: root.gpuHwmon.length > 0 ? "file://" + root.gpuHwmon + "freq1_input" : ""
        onLoaded: root.gpuClockMhz = (parseFloat(String(fGpuC.text()).trim()) || 0) / 1000000 }
    FileView { id: fFan;   path: root.fanPath.length > 0 ? "file://" + root.fanPath : ""
        onLoaded: root.fanRpm = parseFloat(String(fFan.text()).trim()) || 0 }

    FileView { id: fDisk;  path: "file:///proc/diskstats"
        onLoaded: {
            // Sectors are 512 bytes; fields 6 and 10 are sectors read/written.
            let rd = 0, wr = 0;
            const lines = String(fDisk.text()).split("\n");
            for (let i = 0; i < lines.length; ++i) {
                const p = lines[i].trim().split(/\s+/);
                if (p.length < 10) continue;
                // Whole devices only — counting partitions as well would
                // double every byte.
                if (!/^(nvme\d+n\d+|sd[a-z]|mmcblk\d+)$/.test(p[2])) continue;
                rd += parseFloat(p[5]) || 0;
                wr += parseFloat(p[9]) || 0;
            }
            const prev = root._prevDisk;
            if (prev) {
                const dt = root.intervalMs / 1000.0;
                root.diskReadBps  = Math.max(0, (rd - prev.rd) * 512 / dt);
                root.diskWriteBps = Math.max(0, (wr - prev.wr) * 512 / dt);
            }
            root._prevDisk = { rd: rd, wr: wr };
        }
    }

    // ── Frame rate ──────────────────────────────────────────────────────
    // This is the COMPOSITOR's presentation rate, not the game's. When a
    // fullscreen game drives the display it matches, which is the case that
    // matters; for a true in-engine number MangoHud is still the right tool.
    // `fps` is the number to show: the GAME's frame rate when a MangoHud-
    // wrapped app is running, otherwise the compositor's presentation rate.
    // They are different measurements and conflating them would be a lie —
    // `fpsIsApp` says which one you are looking at.
    // -1 means "no source", NOT zero and NOT the refresh rate. Measured: the
    // shell's own frame callbacks read a constant 180 on this machine — the
    // display's refresh — while the game rendered ~61. Presenting that as
    // "FPS" is worse than presenting nothing, because it looks plausible and
    // never moves. Real per-app frame rate requires a Vulkan layer inside the
    // game; without one this stays -1 and the HUD shows a dash.
    readonly property real fps: root.appFpsFresh ? root.appFps : -1
    readonly property bool fpsIsApp: root.appFpsFresh
    readonly property bool fpsAvailable: root.appFpsFresh
    // Kept, but labelled for what it is: the panel's refresh rate.
    readonly property real refreshHz: root.compositorFps
    property string fpsApp: ""

    property real compositorFps: 0
    property int frameCount: 0

    // ── In-app FPS via MangoHud ─────────────────────────────────────────
    // MangoHud streams a CSV row every log_interval ms into a folder; we tail
    // the newest file. A stale file means the game has exited, so the reading
    // expires rather than freezing at the last frame it ever rendered.
    property real appFps: 0
    property real appFpsAt: 0
    readonly property bool appFpsFresh: root.appFps > 0
        && (Date.now() - root.appFpsAt) < 2500

    // How old the producer's file may be before its number is disowned.
    // This has to be judged on the FILE'S mtime, not on when we last read it:
    // stamping appFpsAt at read time made a dead file look eternally fresh, so
    // the HUD sat on the last frame a long-exited game ever rendered (a CSV
    // orphaned at 15:29 still showed its 143 FPS two hours later). The layer
    // writes every log_interval, so anything past a few seconds is a corpse.
    readonly property int fpsFileMaxAgeMs: 5000

    Process {
        id: mangoTail
        running: false
        // Emit the HEADER and the last complete row. The two producers do NOT
        // agree on column order —
        //   MangoHud     fps,frametime,cpu_load,...          (fps first)
        //   Mesa overlay device, format, fps, frame_timing   (fps third)
        // — so the column is located by NAME rather than by index. Assuming
        // position silently read "device" as a frame rate.
        command: ["bash", "-c",
            "f=$(ls -t /dev/shm/mangohud-fps/*.csv /dev/shm/mesa-fps.csv 2>/dev/null | head -1); "
            + "[ -n \"$f\" ] || exit 0; "
            + "age=$(( $(date +%s) - $(stat -c %Y \"$f\") )); "
            + "h=$(grep -m1 -i 'fps' \"$f\"); "
            + "r=$(tail -2 \"$f\" | head -1); "
            + "echo \"$(basename \"$f\")|$age|$h|$r\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = String(text).trim().split("|");
                if (parts.length < 4) return;
                const name = parts[0];
                // A file nobody is writing to any more is not a frame rate.
                if (parseInt(parts[1], 10) * 1000 > root.fpsFileMaxAgeMs) return;
                const header = parts[2].split(",").map(x => x.trim().toLowerCase());
                const row = parts[3].split(",");
                let idx = header.indexOf("fps");
                if (idx < 0) idx = 0;
                const v = parseFloat(row[idx]);
                // The header row itself comes back as text; only a real number
                // counts, which also guards against a half-written line.
                if (!isFinite(v) || v <= 0) return;
                root.appFps = v;
                root.appFpsAt = Date.now();
                root.fpsApp = name.replace(/\.csv$/, "").replace(/_\d.*$/, "");
            }
        }
    }

    readonly property string netRxText: root.humanRate(root.netRxBps)
    readonly property string netTxText: root.humanRate(root.netTxBps)

    function humanRate(bps) {
        if (bps < 1024) return Math.round(bps) + " B/s";
        if (bps < 1024 * 1024) return (bps / 1024).toFixed(0) + " KB/s";
        return (bps / 1024 / 1024).toFixed(1) + " MB/s";
    }

    // Previous samples, for the deltas.
    property var _prevNet: null
    property var _prevCpu: null
    property real _lastMs: 0
    property bool _primed: false

    function poll() {
        netFile.reload();
        snmpFile.reload();
        cpuFile.reload();
        memFile.reload();
        gpuBusy.reload();
        vramUsed.reload();
        if (root.tempPath.length > 0) tempFile.reload();
        fLoad.reload(); fUp.reload(); fFreq.reload(); fDisk.reload();
        if (root.gamePid > 0) fGameStat.reload();
        fBatt.reload(); fBattW.reload();
        if (root.gpuHwmon.length > 0) { fGpuT.reload(); fGpuW.reload(); fGpuC.reload(); }
        if (root.fanPath.length > 0) fFan.reload();
        swapFile.reload();
        fCtx.reload(); fCached.reload(); fBattSt.reload(); fCores.reload();
        root.slowTick = (root.slowTick + 1) % 5;
        if (root.slowTick === 0) { wifiProbe.running = true; dfProbe.running = true; }
    }

    Timer {
        running: root.active
        interval: root.intervalMs
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = Date.now();
            root._lastMs = now;
            root.poll();
        }
    }

    // Frames are counted rather than timed: a FrameAnimation ticks once per
    // presented frame, so counting over a known window gives the real rate
    // without assuming anything about vsync.
    FrameAnimation {
        running: root.active && root.fpsCounterEnabled
        onTriggered: root.frameCount++
    }

    Timer {
        running: root.active
        interval: 1000
        repeat: true
        onTriggered: {
            root.compositorFps = root.frameCount;
            root.frameCount = 0;
            mangoTail.running = true;
        }
    }

    onActiveChanged: {
        if (!root.active) return;
        // Drop the stale baseline so the first rate after re-opening is not
        // computed against a sample from minutes ago.
        root._prevNet = null;
        root._prevCpu = null;
        root._primed = false;
    }

    // ── /proc/net/dev ───────────────────────────────────────────────────
    FileView {
        id: netFile
        path: "file:///proc/net/dev"
        onLoaded: {
            const lines = String(netFile.text()).split("\n");
            let best = null;
            const seen = [];
            for (let i = 2; i < lines.length; ++i) {
                const parts = lines[i].trim().split(/\s+/);
                if (parts.length < 10) continue;
                const name = parts[0].replace(":", "");
                if (name === "lo") continue;
                if (parseFloat(parts[1]) + parseFloat(parts[9]) > 0) seen.push(name);
                const rx = parseFloat(parts[1]);
                const tx = parseFloat(parts[9]);
                // Columns, from the two header rows:
                //   1 bytes  2 packets  3 errs  4 drop   … (receive)
                //   9 bytes 10 packets 11 errs 12 drop   … (transmit)
                const row = {
                    name: name, rx: rx, tx: tx,
                    rxPkts: parseFloat(parts[2]),  rxErrs: parseFloat(parts[3]),
                    rxDrop: parseFloat(parts[4]),
                    txPkts: parseFloat(parts[10]), txErrs: parseFloat(parts[11]),
                    txDrop: parseFloat(parts[12])
                };
                if (root.iface.length > 0) {
                    if (name !== root.iface) continue;
                    best = row;
                    break;
                }
                // Auto-pick: the interface that has actually moved traffic.
                if (!best || (rx + tx) > (best.rx + best.tx))
                    best = row;
            }
            root.interfaces = seen;
            if (!best) return;
            root.netRxTotal = best.rx;
            root.netTxTotal = best.tx;
            root.netDropTotal = best.rxDrop + best.txDrop;
            root.netErrTotal = best.rxErrs + best.txErrs;
            const prev = root._prevNet;
            if (prev && prev.name === best.name) {
                const dt = root.intervalMs / 1000.0;
                root.netRxBps = Math.max(0, (best.rx - prev.rx) / dt);
                root.netTxBps = Math.max(0, (best.tx - prev.tx) / dt);
                // Loss as a share of packets actually moved this tick, not as
                // a lifetime ratio: a card that dropped 100 packets during a
                // storm an hour ago is not dropping packets now, and a
                // cumulative percentage would keep insisting that it is.
                const dPkts = (best.rxPkts - prev.rxPkts) + (best.txPkts - prev.txPkts);
                const dDrop = (best.rxDrop - prev.rxDrop) + (best.txDrop - prev.txDrop);
                const dErr  = (best.rxErrs - prev.rxErrs) + (best.txErrs - prev.txErrs);
                root.netDropRate = Math.max(0, dDrop / dt);
                root.netLossPct = dPkts > 0 ? Math.max(0, 100 * dDrop / (dPkts + dDrop)) : 0;
                root.netErrRate = Math.max(0, dErr / dt);
            }
            root._prevNet = best;
        }
    }

    // ── /proc/net/snmp — TCP retransmissions ────────────────────────────
    // Two lines: a header of column NAMES, then the values. Reading by name
    // matters because the column set differs between kernels.
    property var _prevTcp: null
    FileView {
        id: snmpFile
        path: "file:///proc/net/snmp"
        onLoaded: {
            const lines = String(snmpFile.text()).split("\n");
            let keys = null, vals = null;
            for (const line of lines) {
                if (!line.startsWith("Tcp:")) continue;
                const parts = line.trim().split(/\s+/);
                if (!keys) keys = parts; else { vals = parts; break; }
            }
            if (!keys || !vals) return;
            const get = k => {
                const i = keys.indexOf(k);
                return i < 0 ? 0 : parseFloat(vals[i]);
            };
            const cur = { retrans: get("RetransSegs"), out: get("OutSegs") };
            root.tcpEstab = get("CurrEstab");
            const prev = root._prevTcp;
            if (prev) {
                const dt = root.intervalMs / 1000.0;
                const dR = Math.max(0, cur.retrans - prev.retrans);
                const dO = Math.max(0, cur.out - prev.out);
                root.tcpRetransRate = dR / dt;
                root.tcpRetransPct = dO > 0 ? Math.min(100, 100 * dR / dO) : 0;
            }
            root._prevTcp = cur;
        }
    }

    // ── Ping the peer the game is actually talking to ───────────────────
    // A game does not publish its own netcode stats, so "packet loss in the
    // game" cannot be read out of it. The closest honest measurement is to
    // find the remote address the game's own socket is connected to and probe
    // THAT: same server, same path, real RTT and real loss.
    //
    // Peer discovery is deliberately narrow — a UDP peer off the local subnet
    // belonging to the foreground game's process tree. Games use UDP for
    // gameplay traffic; TCP peers are far more likely to be a launcher,
    // telemetry or a CDN, and pinging those would answer the wrong question.
    // Falls back to the default gateway, which at least separates "my wifi is
    // bad" from "the server is far away".
    property string pingOverride: ""   // set to pin a target manually
    Process {
        id: pingProbe
        running: false
        command: ["bash", "-c",
            "target='" + root.pingOverride + "'; src=manual; "
            + "if [ -z \"$target\" ]; then "
            +   "for p in $(pgrep -f 'steam_app_|\\.exe' 2>/dev/null); do "
            +     "t=$(ss -unp 2>/dev/null | grep -w \"pid=$p\" "
            +       "| awk '{print $6}' | cut -d: -f1 "
            +       "| grep -vE '^(127\\.|192\\.168\\.|10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|0\\.|\\*)' "
            +       "| head -1); "
            +     "[ -n \"$t\" ] && { target=$t; src=$(cat /proc/$p/comm 2>/dev/null); break; }; "
            +   "done; fi; "
            + "if [ -z \"$target\" ]; then "
            +   "target=$(ip route | awk '/^default/{print $3; exit}'); src=gateway; fi; "
            + "[ -n \"$target\" ] || exit 0; "
            // -w bounds total runtime so a black-holed target cannot leave the
            // process hanging until the next probe stacks on top of it.
            + "out=$(ping -n -q -c 4 -i 0.25 -W 1 -w 3 \"$target\" 2>/dev/null); "
            + "loss=$(echo \"$out\" | grep -oE '[0-9]+(\\.[0-9]+)?% packet loss' | grep -oE '^[0-9.]+'); "
            + "rtt=$(echo \"$out\" | awk -F'/' '/^rtt|^round-trip/{print $5}'); "
            + "echo \"$target|$src|${loss:--1}|${rtt:--1}\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = String(text).trim().split("|");
                if (p.length < 4) return;
                root.pingTarget = p[0];
                root.pingSource = p[1];
                root.pingLossPct = parseFloat(p[2]);
                root.pingMs = parseFloat(p[3]);
            }
        }
    }

    // Much slower than the 1Hz stats: four probes take ~1s, and pinging a game
    // server every second would be both pointless and rude.
    Timer {
        interval: 10000
        running: root.active && root.pingEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!pingProbe.running) pingProbe.running = true;
    }
    // Off by default — it emits traffic, unlike every other stat here, so it
    // stays opt-in rather than something the HUD starts doing unannounced.
    property bool pingEnabled: false

    // ── /proc/stat ──────────────────────────────────────────────────────
    FileView {
        id: cpuFile
        path: "file:///proc/stat"
        onLoaded: {
            const first = String(cpuFile.text()).split("\n")[0];
            const p = first.trim().split(/\s+/);
            if (p.length < 5) return;
            let total = 0;
            for (let i = 1; i < p.length; ++i) total += parseFloat(p[i]) || 0;
            const idle = (parseFloat(p[4]) || 0) + (parseFloat(p[5]) || 0);
            const prev = root._prevCpu;
            if (prev) {
                const dt = total - prev.total;
                const di = idle - prev.idle;
                if (dt > 0) root.cpuPct = Math.max(0, Math.min(100, 100 * (1 - di / dt)));
            }
            root._prevCpu = { total: total, idle: idle };
        }
    }

    // ── /proc/meminfo ───────────────────────────────────────────────────
    FileView {
        id: memFile
        path: "file:///proc/meminfo"
        onLoaded: {
            const t = String(memFile.text());
            const mt = /MemTotal:\s+(\d+)/.exec(t);
            const ma = /MemAvailable:\s+(\d+)/.exec(t);
            if (!mt || !ma) return;
            const totalKb = parseFloat(mt[1]);
            const availKb = parseFloat(ma[1]);
            root.memTotalGb = totalKb / 1024 / 1024;
            root.memUsedGb = (totalKb - availKb) / 1024 / 1024;
            root.memUsedPct = 100 * (1 - availKb / totalKb);
        }
    }

    FileView {
        id: swapFile
        path: "file:///proc/meminfo"
        onLoaded: {
            const t = String(swapFile.text());
            const st = /SwapTotal:\s+(\d+)/.exec(t);
            const sf = /SwapFree:\s+(\d+)/.exec(t);
            if (!st || !sf) return;
            root.swapTotalGb = parseFloat(st[1]) / 1024 / 1024;
            root.swapUsedGb = (parseFloat(st[1]) - parseFloat(sf[1])) / 1024 / 1024;
        }
    }

    // ── GPU ─────────────────────────────────────────────────────────────
    readonly property string gpuDir: "/sys/class/drm/card1/device"
    FileView {
        id: gpuBusy
        path: "file://" + root.gpuDir + "/gpu_busy_percent"
        onLoaded: root.gpuPct = parseFloat(String(gpuBusy.text()).trim()) || 0
    }
    FileView {
        id: vramUsed
        path: "file://" + root.gpuDir + "/mem_info_vram_used"
        onLoaded: root.vramUsedGb = (parseFloat(String(vramUsed.text()).trim()) || 0)
            / 1024 / 1024 / 1024
    }
    FileView {
        path: "file://" + root.gpuDir + "/mem_info_vram_total"
        onLoaded: root.vramTotalGb = (parseFloat(String(text()).trim()) || 0)
            / 1024 / 1024 / 1024
    }

    // ── Temperature ─────────────────────────────────────────────────────
    // hwmon numbering is not stable across boots, so the sensor is found by
    // NAME once rather than hardcoding a path that will silently read the
    // wrong chip after a reboot.
    property string tempPath: ""
    Process {
        id: tempFinder
        running: true
        command: ["bash", "-c",
            "for h in /sys/class/hwmon/hwmon*/; do "
            + "n=$(cat $h/name 2>/dev/null); "
            + "case \"$n\" in k10temp|coretemp|zenpower|acpitz) "
            + "[ -r \"$h/temp1_input\" ] && { echo \"$h/temp1_input\"; exit 0; };; esac; done"]
        stdout: StdioCollector {
            onStreamFinished: root.tempPath = String(text).trim()
        }
    }
    FileView {
        id: tempFile
        path: root.tempPath.length > 0 ? "file://" + root.tempPath : ""
        onLoaded: root.cpuTemp = (parseFloat(String(tempFile.text()).trim()) || 0) / 1000
    }
}





