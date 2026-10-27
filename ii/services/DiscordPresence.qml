pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs

/**
 * The Discord "YouTube Music" presence (BetterDiscord plugin
 * YouTubeMusicPresence). The plugin owns the behaviour; this only edits
 * ~/.config/ytm-presence/options.json and reads status.json, which the
 * plugin writes when what the card shows changes (plus a 30 s heartbeat).
 */
Singleton {
    id: root

    readonly property string dir: `${Quickshell.env("HOME")}/.config/ytm-presence`
    readonly property string lastfmUser: "Bastian927"

    // Mirrors OPTIONS in the plugin; the file only holds what differs.
    readonly property var defaults: ({
        style: { title: "bold", artist: "smallcaps", info: "plain", label: "caps", lyrics: "bolditalic" },
        equalizer: true,
        lyrics: true,
        animationSeconds: 1,
        rotateSeconds: 4,
        coverOrder: ["lastfm", "desktop", "itunes", "deezer"],
        buttons: ["youtubemusic", "lastfm"],
        hideGamesWhileListening: true,
    })
    readonly property var eqFrames: ["ılıl", "lılı", "ıllı", "lııl", "ılıl", "llıı"]

    // Raw file contents and the merged view the panel binds to.
    property var file: ({})
    readonly property var options: root.merge(root.file)
    property bool fileBad: false

    property var status: ({})
    property bool pluginEnabled: false
    property bool scrobblerActive: false
    property bool watching: false     // panel open: tick + scrobbler check
    property real now: Date.now()

    readonly property bool running: (root.status?.running ?? false) && root.now - (root.status?.updatedAt ?? 0) < 75000
    readonly property bool active: root.running && (root.status?.active ?? false)

    readonly property var styleIds: ["plain", "bold", "bolditalic", "italic", "serifbold", "smallcaps", "caps", "wide", "mono", "spaced"]
    readonly property var styleNames: ({
        plain: "Plain", bold: "Bold", bolditalic: "Bold italic", italic: "Italic", serifbold: "Serif bold",
        smallcaps: "Small caps", caps: "Caps", wide: "Wide", mono: "Mono", spaced: "Spaced",
    })
    readonly property var coverNames: ({ lastfm: "Last.fm", desktop: "Desktop player", itunes: "iTunes", deezer: "Deezer" })
    readonly property var coverIcons: ({ lastfm: "radio", desktop: "computer", itunes: "album", deezer: "library_music" })

    function merge(f) {
        const d = root.defaults;
        const o = Object.assign({}, d, f ?? {});
        o.style = Object.assign({}, d.style, f?.style ?? {});
        o.equalizer = Array.isArray(o.equalizer) ? o.equalizer.length > 0 : !!o.equalizer;
        return o;
    }

    // ── Unicode styles: same mapping as the plugin ─────────────────────
    function _range(upper, lower, digit) {
        return ch => {
            const c = ch.codePointAt(0);
            if (c >= 65 && c <= 90 && upper) return String.fromCodePoint(upper + c - 65);
            if (c >= 97 && c <= 122 && lower) return String.fromCodePoint(lower + c - 97);
            if (c >= 48 && c <= 57 && digit) return String.fromCodePoint(digit + c - 48);
            return ch;
        };
    }
    readonly property string _small: "ᴀʙᴄᴅᴇꜰɢʜɪᴊᴋʟᴍɴᴏᴘǫʀꜱᴛᴜᴠᴡxʏᴢ"
    function styled(name, s) {
        s = String(s ?? "");
        const map = f => Array.from(s).map(f).join("");
        switch (name) {
        case "bold": return map(root._range(0x1D5D4, 0x1D5EE, 0x1D7EC));
        case "bolditalic": return map(root._range(0x1D63C, 0x1D656, 0x1D7EC));
        case "italic": return map(root._range(0x1D608, 0x1D622, 0));
        case "serifbold": return map(root._range(0x1D400, 0x1D41A, 0x1D7CE));
        case "mono": return map(root._range(0x1D670, 0x1D68A, 0x1D7F6));
        case "wide": return map(ch => {
            const c = ch.codePointAt(0);
            return c > 32 && c < 127 ? String.fromCodePoint(c + 0xFEE0) : ch === " " ? "　" : ch;
        });
        case "smallcaps": return map(ch => {
            const c = ch.toLowerCase().codePointAt(0);
            return c >= 97 && c <= 122 ? root._small[c - 97] : ch;
        });
        case "caps": return s.toUpperCase();
        case "spaced": return Array.from(s.toUpperCase()).join(" ");
        default: return s;
        }
    }

    // ── Writing (debounced) ────────────────────────────────────────────
    function set(key, value) {
        const next = Object.assign({}, root.file);
        next[key] = value;
        root.file = next;
        writeTimer.restart();
    }
    function setStyle(line, value) {
        root.set("style", Object.assign({}, root.file?.style ?? {}, { [line]: value }));
    }
    function toggleButton(id) {
        const b = root.options.buttons.slice();
        const i = b.indexOf(id);
        if (i >= 0) b.splice(i, 1); else b.push(id);
        // Keep the plugin's order: YouTube Music first.
        root.set("buttons", ["youtubemusic", "lastfm"].filter(x => b.includes(x)));
    }
    function moveCover(i, dir) {
        const c = root.options.coverOrder.slice();
        const j = i + dir;
        if (j < 0 || j >= c.length) return;
        [c[i], c[j]] = [c[j], c[i]];
        root.set("coverOrder", c);
    }
    function reset() {
        root.file = {};
        writeTimer.restart();
    }

    Timer {
        id: writeTimer
        interval: 300
        onTriggered: optionsFile.setText(JSON.stringify(root.file, null, 2) + "\n")
    }

    FileView {
        id: optionsFile
        path: `${root.dir}/options.json`
        watchChanges: true
        printErrors: false
        onFileChanged: if (!writeTimer.running) reload()
        onLoaded: {
            if (writeTimer.running) return;
            try {
                const t = text().trim();
                const f = t.length ? JSON.parse(t) : {};
                root.file = (f && typeof f === "object" && !Array.isArray(f)) ? f : {};
                root.fileBad = false;
            } catch (e) {
                root.fileBad = true;
            }
        }
        onLoadFailed: if (!writeTimer.running) { root.file = {}; root.fileBad = false; }
    }

    FileView {
        id: statusFile
        path: `${root.dir}/status.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.status = JSON.parse(text()) ?? {}; } catch (e) { /* mid-write; next change fixes it */ }
            root.now = Date.now();
        }
        onLoadFailed: root.status = {}
    }

    FileView {
        id: bdPlugins
        path: `${Quickshell.env("HOME")}/.config/BetterDiscord/data/stable/plugins.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.pluginEnabled = JSON.parse(text())?.YouTubeMusicPresence === true; } catch (e) {}
        }
    }

    Timer {
        running: root.watching
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }

    Timer {
        running: root.watching
        interval: 15000
        repeat: true
        triggeredOnStart: true
        onTriggered: scrobbler.running = true
    }

    Process {
        id: scrobbler
        command: ["systemctl", "--user", "is-active", "--quiet", "rescrobbled"]
        onExited: code => root.scrobblerActive = code === 0
    }
}
