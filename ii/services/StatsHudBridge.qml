pragma Singleton
pragma ComponentBehavior: Bound

// Shared brain for the stats overlay and its settings panel.
//
// The two are separate layer-shell surfaces and cannot reach into each other,
// so everything both of them need — the stat catalogue, how each stat is
// formatted, and the per-app profiles — lives here. That also means adding a
// stat is ONE entry in `catalogue` plus one case in `statFor`, and it appears
// in the overlay, the picker and the presets at once.

import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell

Singleton {
    id: root

    // Every stat the HUD can show, in picker order.
    readonly property var catalogue: [
        "fps", "playtime", "hz", "cpu", "cpufreq", "load", "gpu", "gpuclk",
        "ram", "swap", "vram", "vrampct", "temp", "gputemp", "fan",
        "power", "gpupower", "batt", "battstat", "disk", "diskfree",
        "net", "netloss", "netdrop", "retrans", "conns",
        "ping", "pingloss",
        "wifi", "wifirate", "cached", "corepeak", "ctx",
        "procs", "uptime"
    ]

    // Grouped view of the catalogue, for the stat picker — one flat wall of 34
    // chips is unreadable; these headers break it into scannable sections.
    readonly property var categories: [
        { name: "Performance", ids: ["fps", "playtime", "hz", "cpu", "cpufreq", "load", "gpu", "gpuclk", "corepeak"] },
        { name: "Memory",      ids: ["ram", "swap", "vram", "vrampct", "cached"] },
        { name: "Thermal & power", ids: ["temp", "gputemp", "fan", "power", "gpupower", "batt", "battstat"] },
        { name: "Disk",        ids: ["disk", "diskfree"] },
        { name: "Network",     ids: ["net", "netloss", "netdrop", "retrans", "conns", "ping", "pingloss", "wifi", "wifirate", "link"] },
        { name: "System",      ids: ["ctx", "procs", "uptime"] }
    ]

    readonly property var baseCfg: Config.options.statsHud

    // ── Per-app profiles ────────────────────────────────────────────────
    // What is worth watching depends on the task: a game wants FPS and
    // thermals, a build wants CPU and disk. A profile overrides the global
    // settings key-by-key, so it only has to state what differs.
    readonly property string focusedApp: AppDisplay.focusedApp
    readonly property var appProfiles: {
        try { return JSON.parse(Config.options.statsHud.appProfiles || "{}"); }
        catch (e) { return ({}); }
    }
    readonly property var activeProfile: root.appProfiles[root.focusedApp] ?? null
    readonly property bool profileActive: root.activeProfile !== null
    readonly property var profiledApps: Object.keys(root.appProfiles)

    // Effective settings the overlay actually draws with.
    readonly property var cfg: ({
        layout:    root.activeProfile?.layout    ?? root.baseCfg.layout,
        position:  root.activeProfile?.position  ?? root.baseCfg.position,
        opacity:   root.activeProfile?.opacity   ?? root.baseCfg.opacity,
        showIcons: root.activeProfile?.showIcons ?? root.baseCfg.showIcons,
        marginX:   root.baseCfg.marginX,
        marginY:   root.baseCfg.marginY,
        fields:    root.activeProfile?.fields    ?? root.baseCfg.fields
    })

    function saveAppProfile(appId, p) {
        if (!appId || appId.length === 0) return;
        const all = Object.assign({}, root.appProfiles);
        all[appId] = p;
        Config.options.statsHud.appProfiles = JSON.stringify(all);
    }

    function clearAppProfile(appId) {
        const all = Object.assign({}, root.appProfiles);
        delete all[appId];
        Config.options.statsHud.appProfiles = JSON.stringify(all);
    }

    // ── Layouts ─────────────────────────────────────────────────────────
    function fields(layout) {
        // "custom" is the escape hatch: the presets are opinionated about what
        // earns the space, this one is exactly what you ticked, in tick order.
        if (layout === "custom") {
            const f = root.cfg.fields;
            return (f && f.length > 0) ? f : ["fps", "cpu", "gpu"];
        }
        switch (layout) {
            case "compact":  return ["fps"];
            case "bar":      return ["fps", "cpu", "gpu", "ram", "net"];
            case "stack":    return ["fps", "cpu", "gpu", "net"];
            default:         return ["fps", "hz", "cpu", "gpu", "ram", "vram",
                                     "temp", "gputemp", "fan", "net"];
        }
    }

    // The ping probe is the only stat that SENDS anything, so it runs only
    // while a stat that needs it is actually on screen — ticking it on is the
    // consent, and untticking it stops the traffic.
    Binding {
        target: SysStats
        property: "pingEnabled"
        value: {
            const f = root.fields(root.cfg.layout) ?? [];
            return f.indexOf("ping") >= 0 || f.indexOf("pingloss") >= 0;
        }
    }

    // Same consent rule for the compositor frame counter. It is the one stat
    // whose measurement costs something: a FrameAnimation makes the whole
    // shell render at full refresh for as long as it runs, so it counts only
    // while something is actually reading the number — the HZ stat being on
    // screen, or the settings panel showing its "Panel refresh" line.
    //
    // Without this the switch was unreachable: `fpsCounterEnabled` was
    // declared false in SysStats and never assigned anywhere, so the counter
    // never ran and HZ read a permanent 0.
    Binding {
        target: SysStats
        property: "fpsCounterEnabled"
        value: (root.fields(root.cfg.layout) ?? []).indexOf("hz") >= 0
               || GlobalStates.statsHudSettingsOpen
    }

    // ── Units ───────────────────────────────────────────────────────────
    // Alternative shapes for the same measurement. Which one is useful
    // depends on the question you are asking: RAM in GB answers "how much is
    // left", in % answers "am I close to the limit"; a network rate in MB/s
    // is about files, in Mbit/s it is about the link.
    readonly property var formats: ({
        net:     ["bytes", "bits", "packets-off"],
        disk:    ["bytes", "bits"],
        ram:     ["gb", "pct", "both"],
        vram:    ["gb", "pct", "both"],
        swap:    ["gb", "pct"],
        temp:    ["c", "f"],
        gputemp: ["c", "f"],
        cpufreq: ["ghz", "mhz"],
        gpuclk:  ["mhz", "ghz"],
        uptime:  ["hm", "dhm"],
        playtime: ["hm", "dhm"],
        fps:      ["int", "dec"],
        netdrop:  ["rate", "total"],
        retrans:  ["pct", "rate"],
        wifi:     ["pct", "dbm"],
        diskfree: ["gb", "pct"]
    })

    readonly property var unitChoices: {
        try { return JSON.parse(Config.options.statsHud.units || "{}"); }
        catch (e) { return ({}); }
    }

    function unitOf(id) {
        const opts = root.formats[id];
        if (!opts) return "";
        return root.unitChoices[id] ?? opts[0];
    }

    function setUnit(id, fmt) {
        const all = Object.assign({}, root.unitChoices);
        all[id] = fmt;
        Config.options.statsHud.units = JSON.stringify(all);
    }

    // Cycle through a stat's formats — one tap in the picker rather than a
    // submenu per stat.
    function cycleUnit(id) {
        const opts = root.formats[id];
        if (!opts || opts.length < 2) return;
        const cur = root.unitOf(id);
        root.setUnit(id, opts[(opts.indexOf(cur) + 1) % opts.length]);
    }

    function rate(bps, fmt) {
        if (fmt === "bits") {
            const b = bps * 8;
            if (b < 1000000) return (b / 1000).toFixed(0) + " Kb";
            return (b / 1000000).toFixed(1) + " Mb";
        }
        return SysStats.humanRate(bps);
    }

    function temp(c, fmt) {
        return fmt === "f" ? Math.round(c * 9 / 5 + 32) + "°F" : Math.round(c) + "°";
    }

    function amount(usedGb, totalGb, fmt) {
        const pct = totalGb > 0 ? Math.round(100 * usedGb / totalGb) : 0;
        if (fmt === "pct") return pct + "%";
        if (fmt === "both") return usedGb.toFixed(1) + "G/" + pct + "%";
        return usedGb.toFixed(1) + "G";
    }

    // ── Formatting ──────────────────────────────────────────────────────
    // One place that knows each stat's icon, label, value and alarm point.
    function statFor(id) {
        switch (id) {
            // A dash when nothing is measuring the game, rather than the
            // panel's refresh rate dressed up as FPS.
            // 0 in red when nothing is measuring the game. It still must not
            // claim the panel's refresh rate as the game's frame rate — but a
            // red zero says "not being measured" more loudly than a dash.
            case "fps":  return { icon: SysStats.fpsAvailable ? "sports_esports" : "speed",
                                  label: SysStats.fpsAvailable
                                    ? (SysStats.fpsApp.length > 0 ? SysStats.fpsApp : "FPS") : "FPS",
                                  value: SysStats.fpsAvailable
                                    ? (root.unitOf("fps") === "dec"
                                        ? SysStats.fps.toFixed(1)
                                        : Math.round(SysStats.fps).toString())
                                    : "0",
                                  warn: !SysStats.fpsAvailable || SysStats.fps < 30 };
            case "hz":   return { icon: "monitor", label: "HZ",
                                  value: Math.round(SysStats.refreshHz).toString(), warn: false };
            case "cpu":  return { icon: "memory", label: "CPU",
                                  value: Math.round(SysStats.cpuPct) + "%",
                                  warn: SysStats.cpuPct > 90 };
            case "cpufreq": return { icon: "bolt", label: "CLK",
                                  value: root.unitOf("cpufreq") === "mhz"
                                    ? Math.round(SysStats.cpuFreqGhz * 1000) + "M"
                                    : SysStats.cpuFreqGhz.toFixed(1) + "G", warn: false };
            case "load": return { icon: "stacked_line_chart", label: "LOAD",
                                  value: SysStats.load1.toFixed(2), warn: SysStats.load1 > 16 };
            case "gpu":  return { icon: "developer_board", label: "GPU",
                                  value: Math.round(SysStats.gpuPct) + "%",
                                  warn: SysStats.gpuPct > 95 };
            case "gpuclk": return { icon: "speed", label: "GCLK",
                                  value: root.unitOf("gpuclk") === "ghz"
                                    ? (SysStats.gpuClockMhz / 1000).toFixed(2) + "G"
                                    : Math.round(SysStats.gpuClockMhz) + "M", warn: false };
            case "ram":  return { icon: "database", label: "RAM",
                                  value: root.amount(SysStats.memUsedGb, SysStats.memTotalGb,
                                                     root.unitOf("ram")),
                                  warn: SysStats.memUsedPct > 90 };
            case "swap": return { icon: "swap_horiz", label: "SWAP",
                                  value: root.amount(SysStats.swapUsedGb, SysStats.swapTotalGb,
                                                     root.unitOf("swap")),
                                  warn: SysStats.swapTotalGb > 0
                                        && SysStats.swapUsedGb / SysStats.swapTotalGb > 0.5 };
            case "vram": return { icon: "sd_card", label: "VRAM",
                                  value: root.amount(SysStats.vramUsedGb, SysStats.vramTotalGb,
                                                     root.unitOf("vram")),
                                  warn: SysStats.vramPct > 92 };
            case "vrampct": return { icon: "sd_card", label: "VRAM%",
                                  value: Math.round(SysStats.vramPct) + "%",
                                  warn: SysStats.vramPct > 92 };
            case "temp": return { icon: "thermostat", label: "CPU°",
                                  value: root.temp(SysStats.cpuTemp, root.unitOf("temp")),
                                  warn: SysStats.cpuTemp > 90 };
            case "gputemp": return { icon: "thermostat", label: "GPU°",
                                  value: root.temp(SysStats.gpuTemp, root.unitOf("gputemp")),
                                  warn: SysStats.gpuTemp > 90 };
            case "fan":  return { icon: "mode_fan", label: "FAN",
                                  value: Math.round(SysStats.fanRpm) + "", warn: false };
            case "power": return { icon: "battery_charging_full", label: "PWR",
                                  value: SysStats.battWatts.toFixed(1) + "W", warn: false };
            case "gpupower": return { icon: "flash_on", label: "GPUW",
                                  value: SysStats.gpuWatts.toFixed(1) + "W", warn: false };
            case "batt": return { icon: "battery_std", label: "BAT",
                                  value: Math.round(SysStats.battPct) + "%",
                                  warn: SysStats.battPct < 15 };
            case "disk": return { icon: "storage", label: "DISK",
                                  value: "R" + root.rate(SysStats.diskReadBps, root.unitOf("disk"))
                                       + " W" + root.rate(SysStats.diskWriteBps, root.unitOf("disk")),
                                  warn: false };
            case "net":  return { icon: "swap_vert", label: "NET",
                                  value: "↓" + root.rate(SysStats.netRxBps, root.unitOf("net"))
                                       + "  ↑" + root.rate(SysStats.netTxBps, root.unitOf("net")),
                                  warn: false };
            // NIC-level loss. Any sustained drop here is local — buffers or a
            // struggling wifi link — so even a fraction of a percent warns.
            case "netloss": return { icon: "error_outline", label: "LOSS",
                                  value: SysStats.netLossPct >= 0.01
                                       ? SysStats.netLossPct.toFixed(2) + "%" : "0%",
                                  warn: SysStats.netLossPct >= 0.5 };
            case "netdrop": return { icon: "block", label: "DROP",
                                  value: root.unitOf("netdrop") === "total"
                                       ? String(Math.round(SysStats.netDropTotal))
                                       : Math.round(SysStats.netDropRate) + "/s",
                                  warn: SysStats.netDropRate > 0 };
            // Retransmits mean loss somewhere on the path. Under ~1% is normal
            // background noise on wifi; sustained double digits is a bad link.
            case "retrans": return { icon: "replay", label: "RTX",
                                  value: root.unitOf("retrans") === "rate"
                                       ? SysStats.tcpRetransRate.toFixed(1) + "/s"
                                       : SysStats.tcpRetransPct.toFixed(1) + "%",
                                  warn: SysStats.tcpRetransPct >= 2 };
            case "conns": return { icon: "lan", label: "CONN",
                                  value: String(SysStats.tcpEstab),
                                  warn: false };
            // -1 is "not measured yet" (or ping disabled) and must not render
            // as a real reading — an unmeasured latency shown as 0 ms would be
            // the most flattering possible lie.
            case "ping": return { icon: "network_ping", label:
                                    SysStats.pingSource && SysStats.pingSource !== "gateway"
                                    ? SysStats.pingSource.toUpperCase().slice(0, 8) : "PING",
                                  value: SysStats.pingMs >= 0
                                       ? Math.round(SysStats.pingMs) + " ms" : "—",
                                  warn: SysStats.pingMs >= 100 };
            case "pingloss": return { icon: "signal_disconnected", label: "P-LOSS",
                                  value: SysStats.pingLossPct >= 0
                                       ? Math.round(SysStats.pingLossPct) + "%" : "—",
                                  warn: SysStats.pingLossPct >= 2 };
            case "battstat": return { icon: SysStats.battStatus === "Charging"
                                    ? "battery_charging_full" : "battery_std",
                                  label: "BAT",
                                  value: Math.round(SysStats.battPct) + "%"
                                       + (SysStats.battStatus === "Charging" ? "+" : ""),
                                  warn: SysStats.battPct < 15
                                        && SysStats.battStatus !== "Charging" };
            case "diskfree": return { icon: "hard_drive", label: "FREE",
                                  value: root.unitOf("diskfree") === "pct"
                                    ? Math.round(SysStats.rootUsedPct) + "%"
                                    : SysStats.rootFreeGb.toFixed(0) + "G",
                                  warn: SysStats.rootUsedPct > 92 };
            // Percentage rather than raw dBm: -47 means nothing at a glance.
            case "wifi": return { icon: "wifi", label: SysStats.wifiSsid || "WIFI",
                                  value: root.unitOf("wifi") === "dbm"
                                    ? Math.round(SysStats.wifiDbm) + "dBm"
                                    : Math.round(SysStats.wifiPct) + "%",
                                  warn: SysStats.wifiDbm !== 0 && SysStats.wifiDbm < -75 };
            case "wifirate": return { icon: "network_check", label: "LINK",
                                  value: Math.round(SysStats.wifiMbit) + "Mb", warn: false };
            case "cached": return { icon: "cached", label: "CACHE",
                                  value: SysStats.cachedGb.toFixed(1) + "G", warn: false };
            // The HOTTEST core: an all-core average hides one pinned thread,
            // which is exactly the case worth seeing.
            case "corepeak": return { icon: "grid_view", label: "CORE",
                                  value: Math.round(SysStats.coreMaxPct) + "%",
                                  warn: SysStats.coreMaxPct > 98 };
            case "ctx":  return { icon: "sync_alt", label: "CTX",
                                  value: Math.round(SysStats.ctxPerSec / 1000) + "k",
                                  warn: false };
            case "procs": return { icon: "list_alt", label: "PROC",
                                  value: SysStats.procCount + "", warn: false };
            case "uptime": return { icon: "schedule", label: "UP",
                                  value: root.unitOf("uptime") === "dhm"
                                    ? (Math.floor(SysStats.uptimeSec / 86400) + "d"
                                       + Math.floor((SysStats.uptimeSec % 86400) / 3600) + "h")
                                    : (Math.floor(SysStats.uptimeSec / 3600) + "h"
                                       + Math.floor((SysStats.uptimeSec % 3600) / 60) + "m"),
                                  warn: false };
            // In-game time played — the runtime of the current game process.
            case "playtime": {
                const s = SysStats.gamePlaytimeSec;
                return { icon: "stadia_controller", label: "PLAYED",
                         value: SysStats.gamePid > 0
                            ? (root.unitOf("playtime") === "dhm"
                                ? (Math.floor(s / 86400) + "d" + Math.floor((s % 86400) / 3600) + "h")
                                : (Math.floor(s / 3600) + "h" + Math.floor((s % 3600) / 60) + "m"))
                            : "—",
                         warn: false };
            }
        }
        return { icon: "help", label: id, value: "?", warn: false };
    }
}





