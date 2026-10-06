import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Quickshell

// What the launcher can offer for whatever is on the clipboard, with no prefix
// typed. clipboardText is a reactive property, so this costs no process and no
// polling — the rows are simply right whenever the launcher is opened.
//
// Only recognised content produces a row. A permanent "nothing useful here"
// line would be noise on every open.
QtObject {
    id: root

    /// Set by LauncherSearch so the Discord row can reach the pin script.
    property string discordPinScript: ""

    readonly property string text: String(Quickshell.clipboardText ?? "").trim()

    function _discordIds(t) {
        const m = t.match(/channels\/(@me|\d{5,})(?:\/(\d{5,}))?/);
        if (m) return m[2] ? `${m[1]}/${m[2]}` : m[1];
        // Developer Mode's "Copy ID" gives a bare snowflake with no link
        // around it, which is what most people actually copy. 17-19 digits
        // and nothing else. Whether it names a server or a channel is decided
        // by the script, which can ask Discord without any auth.
        if (/^\d{17,19}$/.test(t)) return t;
        return "";
    }

    function _isUrl(t) { return /^https?:\/\/\S+$/i.test(t); }

    // Long pastes are usually code or prose, not something to act on from here.
    readonly property bool shortEnough: root.text.length > 0 && root.text.length <= 200

    function _row(name, type, icon, verb, fn) {
        return root.resultComp.createObject(null, {
            name: name, type: type, verb: verb,
            iconName: icon,
            iconType: LauncherSearchResult.IconType.Material,
            execute: fn
        });
    }

    /// Rows for the current clipboard, newest intent first. Empty when there
    /// is nothing recognisable.
    function rows() {
        const t = root.text;
        if (t.length === 0) return [];
        const out = [];

        const dc = root._discordIds(t);
        if (dc.length > 0 && root.discordPinScript.length > 0) {
            out.push(root._row(
                Translation.tr("Pin %1 to /%2").arg(dc).arg("dc"),
                Translation.tr("Clipboard · Discord"), "forum", Translation.tr("Pin"),
                () => Quickshell.execDetached(["bash", "-c",
                    `'${root.discordPinScript}' --from-stdin <<< 'https://discord.com/channels/${dc}'`])));
        }

        if (root._isUrl(t)) {
            out.push(root._row(t, Translation.tr("Clipboard · Link"),
                "open_in_new", Translation.tr("Open"),
                () => Qt.openUrlExternally(t)));
        } else if (root.shortEnough && dc.length === 0) {
            // Not a link, short enough to be a phrase: the two things most
            // worth doing with one.
            out.push(root._row(t, Translation.tr("Clipboard · Translate"),
                "translate", Translation.tr("Translate"),
                () => LauncherSearch.query = Config.options.search.prefix.translate + t));
            out.push(root._row(t, Translation.tr("Clipboard · Search"),
                "travel_explore", Translation.tr("Search"),
                () => Qt.openUrlExternally(Config.options.search.engineBaseUrl + encodeURIComponent(t))));
        }

        return out;
    }

    property Component resultComp: Component { LauncherSearchResult {} }
}
