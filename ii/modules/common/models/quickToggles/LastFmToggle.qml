import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Quickshell

/**
 * Music tile. Prefers the local MPRIS player when something is actively
 * playing; falls back to the most recent Last.fm scrobble otherwise.
 *
 *   - Tap: play/pause the local player when one is present, else open
 *     the user's Last.fm profile (or the API account page if not yet
 *     configured).
 *   - Long-press / right-click: refresh Last.fm scrobble data.
 */
QuickToggleModel {
    // ── Source selection ────────────────────────────────────────────────
    readonly property var  mprisTrack: MprisController.activeTrack
    readonly property bool mprisActive:
        MprisController.activePlayer !== null
        && (mprisTrack?.title?.length ?? 0) > 0

    // Title / artist / artwork — local MPRIS wins, scrobble fills in
    // when nothing is locally playing.
    readonly property string trackTitle:
        mprisActive ? mprisTrack.title : LastFm.trackName
    readonly property string trackArtist:
        mprisActive ? mprisTrack.artist : LastFm.artistName
    readonly property string trackArt:
        mprisActive
            ? (mprisTrack.artUrl ?? "")
            : LastFm.albumArtUrl

    // ── Display ─────────────────────────────────────────────────────────
    name: trackTitle.length > 0
        ? trackTitle
        : Translation.tr("Music")

    statusText: {
        if (mprisActive) return trackArtist
        if (!LastFm.ready) return Translation.tr("Last.fm not set")
        if (LastFm.loading && !LastFm.recentTrack) return Translation.tr("Loading…")
        if (trackArtist.length > 0) return trackArtist
        return Translation.tr("Nothing playing")
    }

    tooltipText: trackTitle.length > 0
        ? `${trackTitle}${trackArtist.length > 0 ? " — " + trackArtist : ""}`
        : Translation.tr("No music")

    // Material symbol fallback when no album art image is available.
    icon: MprisController.isPlaying ? "music_note"
        : (mprisActive ? "pause" : "queue_music")

    // Album art — replaces the symbol when present.
    iconImage: trackArt

    available: mprisActive || LastFm.ready
    toggled: MprisController.isPlaying || LastFm.nowPlaying

    // Tap → control local playback if we have a player; otherwise
    // open the Last.fm profile, or the API account creation page when
    // not yet configured.
    mainAction: () => {
        if (MprisController.activePlayer) {
            if (MprisController.canTogglePlaying) MprisController.togglePlaying()
        } else if (LastFm.ready) {
            Quickshell.execDetached(["xdg-open", LastFm.profileUrl])
        } else {
            Quickshell.execDetached(["xdg-open",
                "https://www.last.fm/api/account/create"])
        }
    }

    altAction: () => LastFm.refresh()
    hasMenu: false
}
