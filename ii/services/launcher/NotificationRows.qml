import qs.services
import qs.modules.common
import qs.modules.common.models
import QtQuick
import Quickshell

// Launcher rows for the notification prefix. Owned by LauncherSearch, the way
// ClipboardRows and EmojiRows are.
QtObject {
    id: root

    // Newest first, and never the whole history: the launcher is for finding
    // one thing, and the sidebar already shows the full list.
    readonly property int limit: 50

    function _matches(n, q) {
        if (q.length === 0) return true;
        const hay = `${n.appName} ${n.summary} ${n.body}`.toLowerCase();
        return hay.includes(q.toLowerCase());
    }

    function _ago(ms) {
        const s = Math.max(0, Math.round((Date.now() - ms) / 1000));
        if (s < 60) return Translation.tr("just now");
        if (s < 3600) return Translation.tr("%1m ago").arg(Math.floor(s / 60));
        if (s < 86400) return Translation.tr("%1h ago").arg(Math.floor(s / 3600));
        return Translation.tr("%1d ago").arg(Math.floor(s / 86400));
    }

    /// Rows for an already-prefix-stripped query.
    function rows(searchString) {
        const q = (searchString ?? "").trim();
        const list = (Notifications.list ?? [])
            .filter(n => n && root._matches(n, q))
            .slice()
            .sort((a, b) => (b.time ?? 0) - (a.time ?? 0))
            .slice(0, root.limit);

        return list.map(n => root.resultComp.createObject(null, {
            name: n.summary && n.summary.length > 0 ? n.summary : n.body,
            // The body is the useful half when a summary is just the app name.
            rawValue: n.body,
            // appIcon is what the sender asked for; it is a system icon name
            // or a path, which is exactly what IconType.System takes.
            iconName: n.appIcon && n.appIcon.length > 0 ? n.appIcon : "dialog-information",
            iconType: LauncherSearchResult.IconType.System,
            verb: Translation.tr("Copy"),
            type: `${n.appName} · ${root._ago(n.time ?? 0)}`,
            execute: () => { Quickshell.clipboardText = `${n.summary}\n${n.body}`.trim(); },
            actions: [
                // The sender's own buttons, so "Reply"/"Open" still work from here.
                ...((n.actions ?? []).map(a => root.resultComp.createObject(null, {
                    name: a.text ?? a.identifier ?? "",
                    iconName: "open_in_new",
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => Notifications.attemptInvokeAction(n.notificationId, a.identifier)
                }))),
                root.resultComp.createObject(null, {
                    name: Translation.tr("Dismiss"),
                    iconName: "close",
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => Notifications.discardNotification(n.notificationId)
                })
            ]
        })).filter(Boolean);
    }

    property Component resultComp: Component { LauncherSearchResult {} }
}
