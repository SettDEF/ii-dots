import qs.services
import qs.modules.common
import qs.modules.common.models
import QtQuick
import Quickshell

// Launcher rows for the emoji prefix. Owned by LauncherSearch, not a service
// of its own: nothing else has any business building these.
QtObject {
    id: root

    /// Rows for an already-prefix-stripped query.
    function rows(searchString) {
        return Emojis.fuzzyQuery(searchString).map(entry => {
            const emoji = entry.match(/^\s*(\S+)/)?.[1] || "";
            return root.resultComp.createObject(null, {
                rawValue: entry,
                name: entry.replace(/^\s*\S+\s+/, ""),
                iconName: emoji,
                iconType: LauncherSearchResult.IconType.Text,
                verb: Translation.tr("Copy"),
                type: Translation.tr("Emoji"),
                execute: () => {
                    Quickshell.clipboardText = entry.match(/^\s*(\S+)/)?.[1];
                }
            });
        }).filter(Boolean);
    }

    property Component resultComp: Component { LauncherSearchResult {} }
}
