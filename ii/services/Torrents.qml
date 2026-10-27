pragma Singleton
pragma ComponentBehavior: Bound

// qBittorrent, over its local WebUI API.
//
// WHY POLL AN HTTP API RATHER THAN READ THE CONFIG
//   qBittorrent's on-disk state is a binary resume format that is rewritten
//   lazily; the numbers you want (live rates, who is downloading from you) only
//   exist in the running process. The WebUI is already enabled here, listening
//   on 127.0.0.1:8080 with LocalHostAuth off, so it costs nothing to ask it.
//
// WHAT "UPLOADED SOMETHING" MEANS
//   Not "is seeding" — 48 torrents are always nominally seeding and a message
//   for that is noise. The event worth knowing is the transition: this torrent
//   was idle, and now someone is actually pulling data from it. That is a
//   rate going from zero to non-zero, so the service tracks the previous poll
//   and fires on the edge, with a per-torrent cooldown so a flaky peer cannot
//   ring the bell every ten seconds.
//
// Import with `qs.services`.

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    /// Touch from a Scope so the watcher runs without its UI.
    readonly property bool ready: true

    readonly property string api: "http://127.0.0.1:8080/api/v2"
    property bool reachable: false
    property int pollInterval: 10000

    /// Session totals, bytes/sec and bytes.
    property real upRate: 0
    property real dlRate: 0
    property real upTotal: 0
    property real dlTotal: 0

    /// Full torrent list, newest poll.
    property var torrents: []

    readonly property int count: root.torrents.length
    readonly property int activeUploads:
        root.torrents.filter(t => (t.upspeed ?? 0) > 0).length
    /// Torrents whose data qBittorrent can no longer find. Worth surfacing:
    /// on this machine they pile up when an external disk is not mounted, and
    /// a torrent in this state is seeding nothing while looking healthy.
    readonly property int missingFiles:
        root.torrents.filter(t => String(t.state ?? "") === "missingFiles").length

    function fmtBytes(b) { return StringUtils.formatBytes(b) }
    function fmtRate(b) { return (Number(b) || 0) <= 0 ? "—" : root.fmtBytes(b) + "/s" }

    // ── polling ─────────────────────────────────────────────────────────
    Timer {
        interval: root.pollInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root._poll()
    }

    // Both documents over XMLHttpRequest, in the shell itself: a sh and two curls every 10 s
    // before. They describe nearly the same instant; applied together once both are in.
    property bool _polling: false
    function _get(path, done) {
        const xhr = new XMLHttpRequest()
        xhr.open("GET", root.api + path)
        xhr.timeout = 4000
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            let v = null
            if (xhr.status === 200) { try { v = JSON.parse(xhr.responseText) } catch (e) {} }
            done(v)
        }
        xhr.send()
    }
    function _poll() {
        if (root._polling) return
        root._polling = true
        root._get("/transfer/info", info => root._get("/torrents/info", list => {
            root._polling = false
            if (!info || !Array.isArray(list)) { root.reachable = false; return }
            root.reachable = true
            root.upRate = info.up_info_speed ?? 0
            root.dlRate = info.dl_info_speed ?? 0
            root.upTotal = info.up_info_data ?? 0
            root.dlTotal = info.dl_info_data ?? 0
            root._detectUploads(list)
            root.torrents = list.slice().sort((a, b) =>
                (b.upspeed ?? 0) - (a.upspeed ?? 0)
                || (b.dlspeed ?? 0) - (a.dlspeed ?? 0))
        }))
    }

    // ── the notification ────────────────────────────────────────────────
    property var _prevUp: ({})     // hash -> last upspeed
    property var _lastNotified: ({})
    property bool _primed: false
    /// Quiet period per torrent, so one peer reconnecting repeatedly cannot
    /// produce a stream of identical messages.
    readonly property int cooldownMs: 10 * 60 * 1000

    function _detectUploads(list) {
        const nowMs = Date.now()
        const nextUp = ({})
        for (const t of list) {
            const h = String(t.hash ?? "")
            const up = Number(t.upspeed ?? 0)
            nextUp[h] = up
            if (!root._primed) continue          // first poll only records
            const was = Number(root._prevUp[h] ?? 0)
            if (was > 0 || up <= 0) continue     // only the idle -> active edge
            const last = Number(root._lastNotified[h] ?? 0)
            if (nowMs - last < root.cooldownMs) continue
            root._lastNotified[h] = nowMs
            root._notify(t)
        }
        root._prevUp = nextUp
        root._primed = true
    }

    function _notify(t) {
        const name = String(t.name ?? "torrent")
        const body = Translation.tr("%1 · %2 uploaded · %3 peer(s)")
            .arg(root.fmtRate(t.upspeed))
            .arg(root.fmtBytes(t.uploaded))
            .arg(t.num_leechs ?? 0)
        notifier.exec(["notify-send", "-a", "qBittorrent", "-i", "qbittorrent",
                       Translation.tr("Uploading: %1").arg(name.slice(0, 60)), body])
    }

    Process { id: notifier }

    // ── control ─────────────────────────────────────────────────────────
    function pauseAll() { ctl.exec(["curl", "-s", "--max-time", "4", "-X", "POST",
        `${root.api}/torrents/stop`, "-d", "hashes=all"]) }
    function resumeAll() { ctl.exec(["curl", "-s", "--max-time", "4", "-X", "POST",
        `${root.api}/torrents/start`, "-d", "hashes=all"]) }
    function pause(hash) { ctl.exec(["curl", "-s", "--max-time", "4", "-X", "POST",
        `${root.api}/torrents/stop`, "-d", `hashes=${hash}`]) }
    function resume(hash) { ctl.exec(["curl", "-s", "--max-time", "4", "-X", "POST",
        `${root.api}/torrents/start`, "-d", `hashes=${hash}`]) }

    Process { id: ctl }
}
