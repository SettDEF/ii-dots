pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Your current Discord voice channel, as published by the IIVoiceOverlay
 * BetterDiscord plugin (scripts/discord/). Discord has no overlay on Linux
 * Wayland and its RPC is whitelist-only, so the client is read from inside and
 * the result lands in one small file under the runtime dir.
 *
 * Nothing here talks to Discord. If the plugin is not running there is no file
 * and `inVoice` stays false, which the overlay shows as "not in a channel".
 */
Singleton {
    id: root

    readonly property string path: `${Quickshell.env("XDG_RUNTIME_DIR") ?? "/tmp"}/ii-discord-voice.json`

    /// The plugin beats every 10 s while running; older than this means Discord
    /// died mid-call and the file is a ghost.
    readonly property int staleMs: 25000

    property var _doc: ({})
    property real _now: Date.now()

    readonly property bool fresh: (root._doc.updatedAt ?? 0) > 0
        && root._now - root._doc.updatedAt < root.staleMs
    readonly property bool inVoice: root.fresh && root._doc.inVoice === true
    readonly property string channel: root._doc.channel ?? ""
    readonly property string guild: root._doc.guild ?? ""
    /// [{ id, name, avatar, speaking, muted, deafened, streaming, video, self }]
    readonly property var members: root.inVoice ? (root._doc.members ?? []) : []
    readonly property int speakingCount: root.members.filter(m => m.speaking).length

    // Only ticks while there is something to expire.
    Timer {
        running: root._doc.inVoice === true
        interval: 5000
        repeat: true
        onTriggered: root._now = Date.now()
    }

    FileView {
        path: root.path
        // Absent until Discord has run the plugin once; not worth a warning.
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const o = JSON.parse(text());
                if (o && typeof o === "object") {
                    root._doc = o;
                    root._now = Date.now();
                }
            } catch (e) { /* mid-write: the next change event carries the rest */ }
        }
        onLoadFailed: root._doc = ({})
    }
}
