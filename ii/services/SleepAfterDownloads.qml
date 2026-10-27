pragma Singleton

import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.functions

/**
 * "Quiet, then sleep when the downloads are done" (the lock screen's right panel).
 *
 * start(): the Quiet profile, held so the charger steps do not raise it; then waits until
 * nothing downloads: the torrents that are really moving (Torrents, which polls qBittorrent's
 * local Web API) and the browser's .part files (Downloads). Paused torrents (stoppedDL) never
 * count. When it has been quiet for a minute it sleeps.
 *
 * qBittorrent blocks sleep while any torrent is "downloading", stalled ones (no peers) too, so
 * those are stopped first and started again after waking; the profile goes back as well.
 */
Singleton {
    id: root

    /// nothing moving for this long before sleeping (a torrent between pieces, the next file)
    readonly property int settleMs: 60000

    /// "idle" | "waiting" | "sleeping"
    property string phase: "idle"
    readonly property bool waiting: phase === "waiting"

    /// [{ name, progress (0..1, -1 unknown), speed (B/s), eta (s, -1 unknown), kind: torrent|browser, stalled, hash }]
    readonly property var items: {
        const list = [];
        for (const t of Torrents.torrents) {
            // stoppedDL, queuedDL and errored ones are not downloading
            const live = ["downloading", "forcedDL", "metaDL", "forcedMetaDL", "checkingDL"].includes(t.state);
            const stalled = t.state === "stalledDL";
            if (!live && !stalled) continue;
            list.push({ name: t.name, progress: t.progress, speed: t.dlspeed ?? 0, eta: (t.eta ?? 8640000) >= 8640000 ? -1 : t.eta,
                        kind: "torrent", stalled: stalled && (t.dlspeed ?? 0) === 0, hash: t.hash });
        }
        for (const d of Downloads.active)
            list.push({ name: d.name, progress: -1, speed: d.speed ?? 0, eta: -1, kind: "browser", stalled: false, hash: "" });
        return list;
    }
    /// torrents downloading with no peers: they do not keep the wait going
    readonly property var stalled: items.filter(i => i.stalled)
    readonly property var moving: items.filter(i => !i.stalled)

    property real quietSince: 0
    property real now: Date.now()
    readonly property real secondsLeft: waiting && quietSince > 0 ? Math.max(0, (settleMs - (now - quietSince)) / 1000) : -1

    property string _profileBefore: ""
    property var _stoppedHashes: []
    property real _sleptAt: 0

    function start() {
        if (phase !== "idle") return;
        _profileBefore = Rog.profile;
        Rog.hold("Quiet");
        quietSince = 0;
        phase = "waiting";
        _check();
    }

    function cancel() {
        if (phase === "idle") return;
        suspendDelay.stop();
        if (_stoppedHashes.length > 0) Torrents.resume(_stoppedHashes.join("|"));
        _stoppedHashes = [];
        phase = "idle";
        quietSince = 0;
        Rog.release(_profileBefore);
    }

    function _check() {
        if (phase !== "waiting") return;
        if (moving.length > 0) {
            quietSince = 0;
        } else if (quietSince === 0) {
            quietSince = Date.now();
        } else if (Date.now() - quietSince >= settleMs) {
            _sleep();
        }
    }

    function _sleep() {
        phase = "sleeping";
        _stoppedHashes = stalled.map(i => i.hash).filter(h => h);
        if (_stoppedHashes.length > 0) Torrents.pause(_stoppedHashes.join("|"));
        // a moment for qBittorrent to drop its sleep lock once nothing downloads
        suspendDelay.restart();
    }

    /// Back from sleep (the clock jumped): what was stopped starts again, the profile goes back.
    function _woke() {
        if (_stoppedHashes.length > 0) Torrents.resume(_stoppedHashes.join("|"));
        _stoppedHashes = [];
        phase = "idle";
        quietSince = 0;
        Rog.release(_profileBefore);
    }

    // unlocked while waiting: you are using it again, so no sleep (and the profile goes back)
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() { if (!GlobalStates.screenLocked && root.phase === "waiting") root.cancel(); }
    }

    // Torrents polls every 10 s, Downloads on every .part change: decide on each new answer
    Connections {
        target: Torrents
        function onTorrentsChanged() { root._check(); }
    }
    Connections {
        target: Downloads
        function onActiveChanged() { root._check(); }
    }

    Timer {
        id: suspendDelay
        interval: 1500
        onTriggered: {
            root._sleptAt = Date.now();
            Session.suspend();
        }
    }

    Timer {
        // the countdown's seconds, and the sleep watch: a gap far longer than the interval
        interval: 1000
        repeat: true
        running: root.phase !== "idle"
        property real last: Date.now()
        onTriggered: {
            const t = Date.now();
            if (root.phase === "sleeping" && root._sleptAt > 0 && t - last > 20000) root._woke();
            last = t;
            root.now = t;
            root._check();
        }
    }

    Timer {
        // a suspend that was refused (another app blocking it): back to waiting, try again in a minute
        interval: 90000
        running: root.phase === "sleeping"
        onTriggered: {
            if (root.phase !== "sleeping") return;
            root.phase = "waiting";
            root.quietSince = Date.now();
        }
    }
}
