import qs.services
import qs.modules.common
import qs.modules.common.models
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "steamVdf.js" as Vdf

// Steam's "non-Steam games": whatever was added through "Add a non-Steam Game",
// which has no desktop entry and so never reached the launcher. Read straight
// from Steam's own shortcuts.vdf and launched back through Steam, so it keeps
// its Proton choice, launch options and overlay.
//
// Owned by LauncherSearch, like the other row sources. Every Steam account on
// the machine contributes; the usual case is one.
QtObject {
    id: root

    readonly property string userdata: `${Quickshell.env("HOME")}/.local/share/Steam/userdata`

    /// uid -> [shortcut] and uid -> { appid: artPath }, kept per account so one
    /// account changing does not rebuild the others.
    property var _lists: ({})
    property var _arts: ({})

    /// Every visible shortcut, by name.
    readonly property var games: {
        const out = [];
        for (const uid in root._lists)
            for (const g of root._lists[uid])
                if (!g.hidden)
                    out.push(Object.assign({ art: root._arts[uid]?.[g.appid] ?? "" }, g));
        return out.sort((a, b) => a.name.localeCompare(b.name));
    }

    function launch(game) {
        // Through Steam: it owns the compatibility tool and launch options.
        Quickshell.execDetached(["steam", `steam://rungameid/${game.gameId}`]);
    }

    function _set(map, uid, value) {
        const next = Object.assign({}, root[map]);
        next[uid] = value;
        root[map] = next;
    }

    // Portrait art beats the wide capsule, which beats the small icon; Steam
    // stores them as <appid>p / <appid> / <appid>_icon.
    function _indexArt(uid, model) {
        const rank = { "p": 3, "": 2, "_icon": 1 };
        const best = {};
        for (let i = 0; i < model.count; i++) {
            const m = String(model.get(i, "fileName")).match(/^(\d+)(p|_icon)?\.(png|jpe?g|webp)$/i);
            if (!m) continue;
            const id = Number(m[1]), r = rank[m[2] ?? ""];
            if (!best[id] || r > best[id].r)
                best[id] = { r, path: String(model.get(i, "filePath")).replace(/^file:\/\//, "") };
        }
        const out = {};
        for (const id in best) out[id] = best[id].path;
        root._set("_arts", uid, out);
    }

    // One reader per Steam account directory.
    readonly property FolderListModel users: FolderListModel {
        folder: "file://" + root.userdata
        showFiles: false
        showDirs: true
        showDotAndDotDot: false
    }

    readonly property Instantiator readers: Instantiator {
        model: root.users
        delegate: QtObject {
            id: user
            required property string fileName
            readonly property string config: `${root.userdata}/${user.fileName}/config`

            property FileView vdf: FileView {
                path: `${user.config}/shortcuts.vdf`
                // Absent until the account adds a non-Steam game.
                printErrors: false
                watchChanges: true
                onFileChanged: reload()
                onLoaded: root._set("_lists", user.fileName, Vdf.parse(data()))
                onLoadFailed: root._set("_lists", user.fileName, [])
            }
            property FolderListModel grid: FolderListModel {
                folder: "file://" + user.config + "/grid"
                showDirs: false
                showDotAndDotDot: false
                onCountChanged: root._indexArt(user.fileName, this)
            }
        }
    }

    // ── Launcher rows ────────────────────────────────────────────────────
    function _matches(g, words) {
        const hay = g.name.toLowerCase();
        return words.every(w => hay.includes(w));
    }

    /// Rows for an already-prefix-stripped query; empty query matches nothing,
    /// the launcher is for finding, not listing.
    function rows(searchString) {
        const words = String(searchString ?? "").toLowerCase().split(/\s+/).filter(w => w.length > 0);
        if (words.length === 0) return [];
        return root.games.filter(g => root._matches(g, words)).map(g => root.resultComp.createObject(null, {
            type: Translation.tr("Game"),
            name: g.name,
            comment: Translation.tr("Non-Steam game"),
            iconName: g.art.length > 0 ? g.art : "sports_esports",
            iconType: g.art.length > 0 ? LauncherSearchResult.IconType.System
                                       : LauncherSearchResult.IconType.Material,
            verb: Translation.tr("Play"),
            execute: () => root.launch(g)
        }));
    }

    /// The same list in the shape the `games` command group takes.
    readonly property var gameCommands: root.games.map(g => ({
        action: g.name,
        icon: g.art.length > 0 ? g.art : "sports_esports",
        iconType: g.art.length > 0 ? LauncherSearchResult.IconType.System
                                   : LauncherSearchResult.IconType.Material,
        description: Translation.tr("Non-Steam game"),
        execute: () => root.launch(g)
    }))

    property Component resultComp: Component { LauncherSearchResult {} }
}
