import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Quickshell

// Launcher rows for the clipboard prefix, with the sort mode and the
// work-safety blur that only this view needs. Owned by LauncherSearch, not a
// service of its own: nothing else has any business building these.
QtObject {
    id: root

    /// "newest" | "oldest" | "size". LauncherSearch.clipboardSort aliases it,
    /// so the search bar keeps setting it by the name it always used.
    property string sort: "newest"

    /// Blur image entries when a neighbouring entry looks like it came from
    /// somewhere the user would rather not have on screen at work.
    readonly property bool workSafetyActive: {
        const enabled = Config.options.workSafety.enable.clipboard;
        const sensitiveNetwork = StringUtils.stringListContainsSubstring(
            Network.networkName.toLowerCase(),
            Config.options.workSafety.triggerCondition.networkNameKeywords);
        return enabled && sensitiveNetwork;
    }

    function containsUnsafeLink(entry) {
        if (entry === undefined) return false;
        return StringUtils.stringListContainsSubstring(
            entry.toLowerCase(), Config.options.workSafety.triggerCondition.linkKeywords);
    }

    // Entries start with "<id>\t...".
    function _idOf(e) { return parseInt((e || "").split("\t")[0]) || 0; }

    function _sizeOf(e) {
        const m = (e || "").match(/binary data\s+(\d+(?:\.\d+)?)\s*(KiB|MiB|GiB|B)/i);
        if (!m) return (e || "").length;
        const n = parseFloat(m[1]);
        const u = m[2].toUpperCase();
        return u === "GIB" ? n * 1024 * 1024 : u === "MIB" ? n * 1024 : u === "KIB" ? n : n / 1024;
    }

    // Decode on demand and idempotently, so the file exists when an action
    // runs rather than only when a thumbnail happened to render.
    function _decode(entry) {
        const num = (entry.match(/^\s*(\d+)/)?.[1]) || "";
        const path = `${Directories.cliphistDecode}/clip-${num}.png`;
        const esc = StringUtils.shellSingleQuoteEscape(entry);
        return { path, cmd: `mkdir -p '${Directories.cliphistDecode}'; [ -f '${path}' ]`
            + ` || printf '${esc}' | ${Cliphist.cliphistBinary} decode > '${path}'` };
    }

    function _imageActions(entry) {
        if (!Cliphist.entryIsImage(entry)) return [];
        const d = root._decode(entry);
        return [root.resultComp.createObject(null, {
            name: Translation.tr("Copy path"),
            iconName: "link",
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => Quickshell.execDetached(["bash", "-c",
                `${d.cmd}; printf '%s' '${d.path}' | wl-copy`])
        }), root.resultComp.createObject(null, {
            name: Translation.tr("Open in file manager"),
            iconName: "folder_open",
            iconType: LauncherSearchResult.IconType.Material,
            // Dolphin selects the file; otherwise open the containing dir.
            execute: () => Quickshell.execDetached(["bash", "-c",
                `${d.cmd}; if command -v dolphin >/dev/null 2>&1;`
              + ` then dolphin --select '${d.path}';`
              + ` else xdg-open '${Directories.cliphistDecode}'; fi`])
        })];
    }

    /// Rows for an already-prefix-stripped query.
    function rows(searchString) {
        const sorted = Cliphist.fuzzyQuery(searchString).slice();
        // Explicit sort, regardless of fuzzy ordering.
        if (root.sort === "newest")      sorted.sort((a, b) => root._idOf(b) - root._idOf(a));
        else if (root.sort === "oldest") sorted.sort((a, b) => root._idOf(a) - root._idOf(b));
        else if (root.sort === "size")   sorted.sort((a, b) => root._sizeOf(b) - root._sizeOf(a));

        return sorted.map((entry, index, array) => {
            let blur = Cliphist.entryIsImage(entry) && root.workSafetyActive;
            if (blur)
                blur = root.containsUnsafeLink(array[index - 1])
                    || root.containsUnsafeLink(array[index + 1]);
            return root.resultComp.createObject(null, {
                rawValue: entry,
                name: StringUtils.cleanCliphistEntry(entry),
                verb: "",
                type: `#${entry.match(/^\s*(\S+)/)?.[1] || ""}`,
                execute: () => Cliphist.copy(entry),
                actions: [root.resultComp.createObject(null, {
                        name: Translation.tr("Copy"),
                        iconName: "content_copy",
                        iconType: LauncherSearchResult.IconType.Material,
                        execute: () => Cliphist.copy(entry)
                    }),
                    ...root._imageActions(entry),
                    root.resultComp.createObject(null, {
                        name: Translation.tr("Delete"),
                        iconName: "delete",
                        iconType: LauncherSearchResult.IconType.Material,
                        execute: () => Cliphist.deleteEntry(entry)
                    })],
                blurImage: blur
            });
        }).filter(Boolean);
    }

    property Component resultComp: Component { LauncherSearchResult {} }
}
