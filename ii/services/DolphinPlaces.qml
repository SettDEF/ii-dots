pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The user's Dolphin "Places" sidebar, so the shell's explorer shows the same
 * shortcuts the file manager does instead of its own hardcoded list.
 *
 * Parsed with regex rather than an XML reader on purpose: KDE writes the XBEL
 * with undeclared namespace prefixes (`bookmark:info`, `kde:...`), which a
 * strict parser rejects outright — verified against this machine's file.
 */
Singleton {
    id: root

    /// [{ name, path, icon }] — visible, local entries only.
    property var places: []

    readonly property string filePath:
        FileUtils.trimFileProtocol(Directories.home).replace(/\/+$/, "")
        + "/.local/share/user-places.xbel"

    // KDE icon names are its own vocabulary; map the common ones onto Material
    // symbols and let anything unrecognised fall back to a plain folder.
    function _icon(title, path) {
        const key = String(title).toLowerCase();
        if (key === "home") return "home";
        if (key === "desktop") return "desktop_windows";
        if (key === "documents") return "docs";
        if (key === "downloads") return "download";
        if (key === "music") return "music_note";
        if (key === "pictures") return "image";
        if (key === "videos" || key === "movies") return "movie";
        if (key === "applications") return "apps";
        if (key === "trash") return "delete";
        return "folder";
    }

    function _parse(xml) {
        const out = [];
        // One block per <bookmark …>…</bookmark>; href is on the tag, the
        // title and the hidden flag live inside it.
        const re = /<bookmark\b[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/bookmark>/g;
        let m;
        while ((m = re.exec(xml)) !== null) {
            const href = m[1];
            const body = m[2];
            // Remote places (smb://, trash:/ …) are not browsable here.
            if (!href.startsWith("file://"))
                continue;
            // An entry hidden in Dolphin should stay hidden here too.
            if (/IsHidden[^>]*>\s*true/.test(body))
                continue;
            const titleMatch = body.match(/<title>([\s\S]*?)<\/title>/);
            const title = titleMatch ? titleMatch[1].trim() : "";
            let path = href.slice(7);
            try {
                path = decodeURIComponent(path);
            } catch (e) {
                // A malformed %-escape should drop one entry, not the lot.
                continue;
            }
            if (path.length === 0)
                continue;
            out.push({
                name: title.length > 0 ? title : path.split("/").pop(),
                path: path,
                icon: root._icon(title, path)
            });
        }
        return out;
    }

    FileView {
        id: placesFile
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.places = root._parse(placesFile.text());
            } catch (e) {
                console.log("[DolphinPlaces] parse failed:", e);
                root.places = [];
            }
        }
        // Absent file is normal (no Dolphin, or never customised); the caller
        // falls back to its own defaults.
        onLoadFailed: root.places = []
    }
}
