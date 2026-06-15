pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.modules.common

Singleton {
    id: root

    // The active player index shown in the corner popup
    property int activeIndex: 0
    readonly property var players: MprisController.players
    readonly property MprisPlayer activePlayer: players[activeIndex] ?? null

    onPlayersChanged: {
        if (activeIndex >= players.length)
            activeIndex = Math.max(0, players.length - 1)
        _snapToPlaying()
    }

    // Auto-follow whichever player becomes active on the system
    Connections {
        target: MprisController
        function onActivePlayerChanged() {
            const idx = Array.from({ length: root.players.length }, (_, i) => i)
                .find(i => root.players[i] === MprisController.activePlayer)
            if (idx !== undefined) root.activeIndex = idx
        }
    }

    // Auto-detect which player is *currently playing* and route the
    // active slot to it. Watches every player's playback state — the
    // moment one transitions to Playing (Spotify resumed, the phone hits
    // play, a YouTube tab unpauses…), we switch activeIndex so the
    // volume slider and other context-aware UI follow it without the
    // user having to paginate the dots manually.
    Instantiator {
        model: root.players
        delegate: QtObject {
            required property MprisPlayer modelData
            readonly property Connections _conn: Connections {
                target: modelData
                function onPlaybackStateChanged() {
                    if (modelData.playbackState !== MprisPlaybackState.Playing) return
                    const idx = root.players.indexOf(modelData)
                    if (idx >= 0 && idx !== root.activeIndex) root.activeIndex = idx
                }
            }
        }
    }

    // On startup / when the player list changes, prefer whatever is
    // already playing so the slider is routed correctly even before the
    // user touches anything.
    function _snapToPlaying() {
        for (let i = 0; i < root.players.length; i++) {
            if (root.players[i]?.playbackState === MprisPlaybackState.Playing) {
                root.activeIndex = i
                return
            }
        }
    }

    // Returns accent color for a given desktopEntry string
    function accentForEntry(de) {
        const d = (de ?? "").toLowerCase()
        let cfg = {}
        try { cfg = JSON.parse(Config.options.media.playerColors || "{}") } catch (e) { cfg = {} }
        // Check user-configured overrides first
        for (const key of Object.keys(cfg)) {
            if (d.includes(key.toLowerCase()))
                return cfg[key]
        }
        // Built-in defaults using terminal palette
        if (d.includes("youtube") || d.includes("ytmusic") || d.includes("strawberry") || d.includes("cider"))
            return Appearance.m3colors.term1
        if (d.includes("spotify") || d.includes("elisa"))
            return Appearance.m3colors.term2
        if (d.includes("firefox") || d.includes("deezer"))
            return Appearance.m3colors.term3
        if (d.includes("chromium") || d.includes("chrome") || d.includes("tidal"))
            return Appearance.m3colors.term4
        if (d.includes("rhythmbox") || d.includes("vlc"))
            return Appearance.m3colors.term5
        if (d.includes("mpv") || d.includes("celluloid"))
            return Appearance.colors.colPrimary
        return Appearance.colors.colPrimary
    }

    function accentForPlayer(player) {
        return accentForEntry(player?.desktopEntry ?? "")
    }

    // ── Per-player audio-mute tracking (sink-input mute state) ─────────
    // Updated every 2s by polling pactl. Map is { lowercased-key → bool }
    // keyed by the player's desktopEntry / first identity word / dbusName head.
    property var mutedKeys: ({})

    function _keysForPlayer(p) {
        if (!p) return []
        const out = []
        const de = (p.desktopEntry ?? "").toLowerCase()
        if (de) out.push(de)
        const id = (p.identity ?? "").toLowerCase().split(" ")[0]
        if (id && !out.includes(id)) out.push(id)
        const dn = (p.dbusName ?? "").toLowerCase().split(".")[0]
        if (dn && !out.includes(dn)) out.push(dn)
        return out
    }

    // Returns true if the player's audio sink-input is muted
    function isPlayerMuted(p) {
        const m = root.mutedKeys
        for (const k of _keysForPlayer(p)) if (m[k] === true) return true
        return false
    }

    // First player that's currently playing AND not muted (any player)
    function firstAudibleActivePlayer() {
        for (const p of root.players) {
            if (p?.playbackStatus === MprisPlaybackState.Playing && !isPlayerMuted(p))
                return p
        }
        return null
    }

    // True if this MPRIS player represents YouTube Music — works for both the
    // dedicated app AND a Firefox/Chromium tab on music.youtube.com (in which
    // case desktopEntry is just "firefox", so we also sniff identity / art URL).
    function isYoutubeMusic(p) {
        if (!p) return false
        const de = (p.desktopEntry ?? "").toLowerCase()
        if (de.includes("youtube") || de.includes("ytmusic")) return true
        const id = (p.identity ?? "").toLowerCase()
        if (id.includes("youtube music") || id.includes("ytmusic")) return true
        const art = (p.trackArtUrl ?? "").toLowerCase()
        if (art.includes("ytimg.com") || art.includes("youtube.com")) return true
        return false
    }
    readonly property bool contextIsYoutubeMusic: isYoutubeMusic(contextPlayer)

    // Map a desktopEntry string to a Material Symbol icon
    function iconForEntry(de) {
        const d = (de ?? "").toLowerCase()
        if (d.includes("spotify"))                                 return "graphic_eq"
        if (d.includes("youtube") || d.includes("ytmusic"))        return "smart_display"
        if (d.includes("firefox") || d.includes("librewolf"))      return "language"
        if (d.includes("chrom")   || d.includes("brave") || d.includes("vivaldi")) return "language"
        if (d.includes("vlc")     || d.includes("mpv") || d.includes("celluloid")) return "movie"
        if (d.includes("rhythmbox") || d.includes("strawberry") || d.includes("elisa") || d.includes("amberol")) return "library_music"
        if (d.includes("discord") || d.includes("vesktop"))        return "forum"
        if (d.includes("cider")   || d.includes("apple"))          return "graphic_eq"
        if (d.includes("tidal"))                                   return "graphic_eq"
        if (d.includes("deezer"))                                  return "graphic_eq"
        return "music_note"
    }
    function iconForPlayer(p) { return iconForEntry(p?.desktopEntry ?? "") }

    // Chooses which icon should appear in bar / workspace media slot.
    // - If active player is unmuted → its icon
    // - Else if some other player is playing & unmuted → that player's icon
    // - Else → muted icon
    readonly property string contextIcon: {
        const active = root.activePlayer
        if (active && !root.isPlayerMuted(active)) return iconForPlayer(active)
        const audible = firstAudibleActivePlayer()
        if (audible) return iconForPlayer(audible)
        return "music_off"
    }
    readonly property var contextPlayer: {
        const active = root.activePlayer
        if (active && !root.isPlayerMuted(active)) return active
        return firstAudibleActivePlayer() ?? active
    }
    readonly property bool contextMuted: {
        const active = root.activePlayer
        if (!active) return false
        if (!isPlayerMuted(active)) return false
        return firstAudibleActivePlayer() === null
    }

    // Poll pactl every 2s directly and rebuild the muted-key map using native JS.
    Process {
        id: muteScanProc
        command: ["pactl", "list", "sink-inputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text) return;
                const out = {};
                const sections = text.split(/Sink Input #/);
                for (let i = 1; i < sections.length; i++) {
                    const blob = sections[i];
                    const muteMatch = blob.match(/Mute:\s*(yes|no)/);
                    if (!muteMatch) continue;
                    const muted = muteMatch[1] === "yes";
                    
                    const keys = new Set();
                    const props = ["application.process.binary", "application.name", "media.name", "application.icon_name"];
                    for (let j = 0; j < props.length; j++) {
                        const prop = props[j];
                        const escapedProp = prop.replace(/\./g, "\\.");
                        const reg = new RegExp(escapedProp + '\\s*=\\s*"([^"]+)"');
                        const m = blob.match(reg);
                        if (m) {
                            const val = m[1].trim().toLowerCase();
                            const firstWord = val.split(/\s+/)[0];
                            if (firstWord) {
                                keys.add(firstWord);
                            }
                        }
                    }
                    
                    for (const k of keys) {
                        out[k] = out[k] || muted;
                    }
                }
                root.mutedKeys = out;
            }
        }
    }
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: muteScanProc.running = true
    }
    Component.onCompleted: muteScanProc.running = true
}
