pragma Singleton

import QtQuick
import Quickshell

/**
 * Unread counts for dock icons: notifications still in the history, per app.
 *
 * A notification names its sender three ways - desktop entry (best, often
 * missing), icon name (usually the desktop id) and display name ("Telegram
 * Desktop") - while a dock icon has only its desktop id
 * ("org.telegram.desktop"). Both sides are reduced to the same tokens and
 * matched in that order of trust.
 */
Singleton {
    id: root

    // Reverse-DNS parts that say nothing about which app it is.
    readonly property var _noise: ["org", "com", "net", "io", "app", "desktop", "github", "gitlab", "kde", "gnome", "freedesktop", "flatpak"]

    /// "org.telegram.desktop" -> ["orgtelegramdesktop", "telegram"]: the whole
    /// id squashed, plus each part long enough to name an app.
    function tokens(s) {
        const t = String(s ?? "").toLowerCase().replace(/\.desktop$/, "");
        if (t.length === 0) return [];
        const out = [t.replace(/[^a-z0-9]/g, "")];
        for (const part of t.split(/[.\-_ ]+/))
            if (part.length >= 4 && !root._noise.includes(part) && !out.includes(part)) out.push(part);
        return out.filter(x => x.length > 0);
    }

    /// Notifications grouped by every token that could name their app.
    readonly property var _byToken: {
        const map = {};
        for (const n of (Notifications.list ?? [])) {
            if (!n) continue;
            const keys = new Set([...root.tokens(n.desktopEntry), ...root.tokens(n.appIcon), ...root.tokens(n.appName)]);
            for (const k of keys) (map[k] = map[k] ?? []).push(n);
        }
        return map;
    }

    /// The notifications that belong to a dock app (by its desktop id).
    function notificationsFor(appId) {
        const seen = new Set();
        const out = [];
        for (const k of root.tokens(appId))
            for (const n of (root._byToken[k] ?? []))
                if (!seen.has(n)) { seen.add(n); out.push(n); }
        return out;
    }

    function countFor(appId) {
        return root.notificationsFor(appId).length;
    }

    function clearFor(appId) {
        for (const n of root.notificationsFor(appId))
            Notifications.discardNotification(n.notificationId);
    }
}
