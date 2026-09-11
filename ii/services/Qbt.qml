pragma Singleton
import QtQuick
import Quickshell

/**
 * qBittorrent WebUI bridge.
 *
 * Polls `127.0.0.1:8080/api/v2/torrents/info` on a Timer, exposes the list
 * as `torrents`, and provides pause/resume/delete actions. No subprocesses —
 * uses the built-in XMLHttpRequest. Localhost-only WebUI must be enabled in
 * qBittorrent (see ~/.config/qBittorrent/qBittorrent.conf:[Preferences]).
 */
Singleton {
    id: root

    property string baseUrl: "http://127.0.0.1:8080"
    property int pollMs: 2000
    property bool available: false
    property var torrents: []
    // Session-wide rates (bytes/sec) and active count, derived from the list.
    property real totalDown: 0
    property real totalUp: 0
    property int activeCount: 0
    property string lastError: ""

    // Underscore-prefixed but intentionally callable from UI code (Menu items
    // that need a one-off endpoint without a dedicated wrapper).
    function _request(method, path, body, onOk) {
        const xhr = new XMLHttpRequest()
        xhr.open(method, root.baseUrl + path)
        if (method === "POST")
            xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status >= 200 && xhr.status < 300) {
                root.available = true
                root.lastError = ""
                if (onOk) onOk(xhr.responseText)
            } else {
                root.available = false
                root.lastError = `HTTP ${xhr.status}: ${xhr.statusText || "no qBittorrent"}`
                if (path === "/api/v2/torrents/info") {
                    root.torrents = []
                    root.totalDown = 0
                    root.totalUp = 0
                    root.activeCount = 0
                }
            }
        }
        xhr.send(body || null)
    }

    function refresh() {
        _request("GET", "/api/v2/torrents/info", null, text => {
            try {
                const arr = JSON.parse(text)
                let down = 0, up = 0, active = 0
                for (let i = 0; i < arr.length; ++i) {
                    down += arr[i].dlspeed || 0
                    up   += arr[i].upspeed || 0
                    const s = arr[i].state || ""
                    if (s === "downloading" || s === "uploading"
                        || s === "stalledDL" || s === "stalledUP"
                        || s === "forcedDL"  || s === "forcedUP"
                        || s === "metaDL")
                        active++
                }
                root.torrents = arr
                root.totalDown = down
                root.totalUp = up
                root.activeCount = active
            } catch (e) {
                root.lastError = "parse error: " + e.message
            }
        })
    }

    // Actions ── single hash, or pipe-joined list of hashes for batches.
    function pause(hashes)  { _request("POST", "/api/v2/torrents/pause",  "hashes=" + encodeURIComponent(hashes), () => refresh()) }
    function resume(hashes) { _request("POST", "/api/v2/torrents/resume", "hashes=" + encodeURIComponent(hashes), () => refresh()) }
    function recheck(hashes){ _request("POST", "/api/v2/torrents/recheck","hashes=" + encodeURIComponent(hashes), () => refresh()) }
    function deleteTorrent(hashes, deleteFiles) {
        const body = "hashes=" + encodeURIComponent(hashes) + "&deleteFiles=" + (deleteFiles ? "true" : "false")
        _request("POST", "/api/v2/torrents/delete", body, () => refresh())
    }
    function addUrl(url, savePath) {
        // multipart/form-data would be cleaner but URL-add accepts plain form too
        let body = "urls=" + encodeURIComponent(url)
        if (savePath) body += "&savepath=" + encodeURIComponent(savePath)
        _request("POST", "/api/v2/torrents/add", body, () => refresh())
    }
    function pauseAll()  { pause("all") }
    function resumeAll() { resume("all") }

    // ── Categorisation helpers ──────────────────────────────────────────
    function isPausedState(s)  { return s === "pausedDL" || s === "pausedUP" || s === "stoppedDL" || s === "stoppedUP" }
    function isSeedingState(s) { return s === "uploading" || s === "stalledUP" || s === "forcedUP" || s === "queuedUP" }
    function isErrorState(s)   { return s === "error" || s === "missingFiles" || s === "unknown" }
    function isDownloadingState(s) { return s === "downloading" || s === "stalledDL" || s === "forcedDL" || s === "metaDL" || s === "queuedDL" || s === "checkingDL" || s === "allocating" }
    function isCompletedState(s)   { return s === "uploading" || s === "stalledUP" || s === "queuedUP" || s === "pausedUP" || s === "stoppedUP" || s === "checkingUP" }

    Timer {
        // Poll fast only while qBittorrent is actually up; when it's not
        // running, back off to 15s instead of hammering a dead endpoint every 2s.
        interval: root.available ? root.pollMs : 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
