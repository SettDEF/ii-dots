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

    // Written next to BetterDiscord's own data by scripts/discord/IIVoiceOverlay.plugin.js.
    readonly property string path: `${Quickshell.env("HOME")}/.config/BetterDiscord/data/ii-discord-voice.json`

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

    /// Your voice settings as Discord holds them (plugin 0.2+), or null:
    /// { mute, deaf, mode: "VOICE_ACTIVITY"|"PUSH_TO_TALK", autoThreshold, threshold,
    ///   noiseSuppression, noiseCancellation (Krisp), echoCancellation, automaticGainControl,
    ///   inputVolume 0..100, outputVolume 0..200, inputDevice, outputDevice,
    ///   inputDevices [{id,name}], outputDevices [{id,name}], can: {…which controls work} }
    readonly property var settings: root.fresh ? (root._doc.settings ?? null) : null
    /// The plugin is there and can take commands.
    readonly property bool controllable: root.settings !== null

    /// Ask Discord (through the plugin) to change a voice setting. The plugin
    /// polls the command file, applies it with Discord's own action creators —
    /// the same calls its Voice & Video page makes — and republishes.
    function command(action, value) {
        const body = JSON.stringify({ id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`, at: Date.now(), action, value });
        cmdWriter.setText(body);
        // Optimistic: the menu reflects the change at once; the plugin's
        // republish confirms (or corrects) it a moment later.
        if (root._doc.settings) {
            const s = Object.assign({}, root._doc.settings);
            if (action === "toggleMute") s.mute = !s.mute;
            else if (action === "toggleDeaf") s.deaf = !s.deaf;
            else if (action === "autoThreshold") s.autoThreshold = !!value;
            else if (action in s) s[action] = value;
            root._doc = Object.assign({}, root._doc, { settings: s });
        }
    }
    FileView {
        id: cmdWriter
        path: `${Quickshell.env("HOME")}/.config/BetterDiscord/data/ii-discord-cmd.json`
        printErrors: false
        blockWrites: false
    }

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
