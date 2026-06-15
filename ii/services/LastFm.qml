pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Last.fm scrobble service. Reads username + API key from
 * `~/.local/share/qs-lastfm.conf` (one `key=value` per line:
 *   username=…
 *   apikey=…
 * ) and polls Last.fm every 30 s for the current user's most recent
 * track + top artists of the past 7 days.
 *
 * `nowPlaying` flips true while the most recent track has the
 * `@attr.nowplaying` flag (Last.fm sets that on the entry that's
 * currently being scrobbled by a player).
 *
 * Lightweight: a single `curl` per refresh, gated on having credentials,
 * skipped while loading. The HUD or any quicktoggle can bind to the
 * exposed properties directly.
 */
Singleton {
    id: root

    property string username: ""
    property string apiKey:   ""

    property var  recentTrack: null
    property var  topArtists:  []
    property bool loading:     false

    readonly property bool ready: username.length > 0 && apiKey.length > 0

    readonly property bool   nowPlaying:  recentTrack?.["@attr"]?.nowplaying === "true"
    readonly property string trackName:   recentTrack?.name   ?? ""
    readonly property string artistName:  recentTrack?.artist?.["#text"] ?? ""
    readonly property string albumName:   recentTrack?.album?.["#text"]  ?? ""
    readonly property string albumArtUrl: {
        const imgs = recentTrack?.image
        if (!Array.isArray(imgs) || imgs.length === 0) return ""
        // Prefer "large" if present; fall back to last entry.
        const large = imgs.find(i => i?.size === "large" || i?.size === "extralarge")
        return (large ?? imgs[imgs.length - 1])?.["#text"] ?? ""
    }
    readonly property string profileUrl:
        username.length > 0 ? `https://www.last.fm/user/${username}` : ""

    function refresh() {
        if (!ready || loading) return
        loading = true
        const u = encodeURIComponent(username)
        recentProc.exec({ command: ["bash", "-c",
            `curl -sf "https://ws.audioscrobbler.com/2.0/?method=user.getrecenttracks` +
            `&user=${u}&api_key=${apiKey}&format=json&limit=1"`] })
        artistProc.exec({ command: ["bash", "-c",
            `curl -sf "https://ws.audioscrobbler.com/2.0/?method=user.gettopartists` +
            `&user=${u}&api_key=${apiKey}&format=json&limit=5&period=7day"`] })
    }

    function loadConfig() {
        loadProc.exec({ command: ["bash", "-c",
            "cat ~/.local/share/qs-lastfm.conf 2>/dev/null || true"] })
    }

    function saveConfig(newUsername, newApiKey) {
        username = newUsername ?? ""
        apiKey   = newApiKey   ?? ""
        saveProc.exec({ command: ["bash", "-c",
            `printf 'username=%s\\napikey=%s\\n' '${username}' '${apiKey}' ` +
            `> ~/.local/share/qs-lastfm.conf`] })
        if (ready) refresh()
    }

    Process {
        id: loadProc
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                lines.forEach(l => {
                    const idx = l.indexOf("=")
                    if (idx < 0) return
                    const k = l.substring(0, idx)
                    const v = l.substring(idx + 1)
                    if (k === "username") root.username = v
                    if (k === "apikey")   root.apiKey   = v
                })
                if (root.ready) root.refresh()
            }
        }
    }
    Process { id: saveProc }

    Process {
        id: recentProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false
                try {
                    const j = JSON.parse(text.trim())
                    const tracks = j?.recenttracks?.track
                    if (Array.isArray(tracks) && tracks.length > 0)
                        root.recentTrack = tracks[0]
                    else if (tracks)
                        root.recentTrack = tracks
                } catch (e) {}
            }
        }
    }
    Process {
        id: artistProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text.trim())
                    const arr = j?.topartists?.artist ?? []
                    root.topArtists = arr.slice(0, 5)
                } catch (e) {}
            }
        }
    }

    // Periodic refresh — only fires while credentials are configured.
    Timer {
        interval: 30000
        repeat: true
        running: root.ready
        triggeredOnStart: false
        onTriggered: root.refresh()
    }

    // Bootstrap config on shell start.
    Timer {
        interval: 0; repeat: false; running: true
        onTriggered: root.loadConfig()
    }
}
