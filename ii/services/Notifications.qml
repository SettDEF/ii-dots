pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

/**
 * Provides extra features not in Quickshell.Services.Notifications:
 *  - Persistent storage
 *  - Popup notifications, with timeout
 *  - Notification groups by app
 */
Singleton {
	id: root
    component Notif: QtObject {
        id: wrapper
        required property int notificationId // Could just be `id` but it conflicts with the default prop in QtObject
        property Notification notification
        property list<var> actions: notification?.actions.map((action) => ({
            "identifier": action.identifier,
            "text": action.text,
        })) ?? []
        property bool popup: false
        property bool isTransient: notification?.hints.transient ?? false
        property string appIcon: notification?.appIcon ?? ""
        property string appName: notification?.appName ?? ""
        property string body: notification?.body ?? ""
        property string image: notification?.image ?? ""
        property string summary: notification?.summary ?? ""
        property double time
        property string urgency: notification?.urgency.toString() ?? "normal"
        property Timer timer

        onNotificationChanged: {
            if (notification === null) {
                root.discardNotification(notificationId);
            }
        }
    }

    function notifToJSON(notif) {
        return {
            "notificationId": notif.notificationId,
            "actions": notif.actions,
            "appIcon": notif.appIcon,
            "appName": notif.appName,
            "body": notif.body,
            "image": notif.image,
            "summary": notif.summary,
            "time": notif.time,
            "urgency": notif.urgency,
        }
    }
    function notifToString(notif) {
        return JSON.stringify(notifToJSON(notif), null, 2);
    }

    component NotifTimer: Timer {
        required property int notificationId
        interval: 7000
        running: true
        onTriggered: () => {
            const index = root.list.findIndex((notif) => notif.notificationId === notificationId);
            const notifObject = root.list[index];
            print("[Notifications] Notification timer triggered for ID: " + notificationId + ", transient: " + notifObject?.isTransient);
            // The notification may already be gone (dismissed or closed by the app).
            if (!notifObject) { destroy(); return; }
            if (notifObject.isTransient) root.discardNotification(notificationId);
            else root.timeoutNotification(notificationId);
            destroy()
        }
    }

    property bool silent: false

    // Per-app mute + sound, persisted to muted-apps.json. Muted apps still log to history.
    //   mutedApps[app] = 0 (forever) | expiry epoch-ms | true (legacy); soundOffApps[app] = true → silent
    property var mutedApps: ({})
    property var soundOffApps: ({})
    readonly property string mutedAppsPath: String(Directories.notificationsPath).replace(/notifications\.json$/, "muted-apps.json")

    function isAppMuted(appName) {
        if (!appName) return false;
        const e = root.mutedApps[appName];
        return e !== undefined && (e === 0 || e === true || e > Date.now());
    }
    function isAppSoundOff(appName) { return !!(appName && root.soundOffApps[appName]); }
    function mutedRemainingMs(appName) {   // for UI labels; 0/forever -> -1
        const e = root.mutedApps[appName];
        return (e && e !== true) ? Math.max(0, e - Date.now()) : -1;
    }
    function _persistMute() {
        mutedAppsView.setText(JSON.stringify({ muted: root.mutedApps, soundOff: root.soundOffApps }));
    }
    // minutes 0 / omitted = mute forever (until manually unmuted).
    function muteApp(appName, minutes) {
        if (!appName) return;
        const m = Object.assign({}, root.mutedApps);
        m[appName] = (minutes && minutes > 0) ? (Date.now() + minutes * 60000) : 0;
        root.mutedApps = m; root._persistMute();
        root.hideAppPopups(appName);
    }
    // Also hide the app's current popups, or muting from a popup looks like a no-op.
    function hideAppPopups(appName) {
        root.popupList.filter(n => n.appName === appName)
            .forEach(n => root.timeoutNotification(n.notificationId));
    }
    function unmuteApp(appName) {
        if (!appName) return;
        const m = Object.assign({}, root.mutedApps); delete m[appName];
        root.mutedApps = m; root._persistMute();
    }
    function toggleAppMute(appName) { root.isAppMuted(appName) ? root.unmuteApp(appName) : root.muteApp(appName, 0); }
    function setAppSoundOff(appName, off) {
        if (!appName) return;
        const s = Object.assign({}, root.soundOffApps);
        if (off) s[appName] = true; else delete s[appName];
        root.soundOffApps = s; root._persistMute();
    }

    // Expire timed mutes (and refresh the bell icons) ~every 20s.
    Timer {
        interval: 20000; running: true; repeat: true
        onTriggered: {
            const now = Date.now(); let changed = false;
            const m = Object.assign({}, root.mutedApps);
            for (const k in m) { if (m[k] !== 0 && m[k] !== true && m[k] <= now) { delete m[k]; changed = true; } }
            if (changed) { root.mutedApps = m; root._persistMute(); }
        }
    }

    property int unread: 0
    property var filePath: Directories.notificationsPath
    property list<Notif> list: []
    property var popupList: list.filter((notif) => notif.popup);
    property bool popupInhibited: (GlobalStates?.sidebarRightOpen ?? false) || silent || GameMode.fullscreenGame
    property var latestTimeForApp: ({})
    Component {
        id: notifComponent
        Notif {}
    }
    Component {
        id: notifTimerComponent
        NotifTimer {}
    }

    function stringifyList(list) {
        return JSON.stringify(list.map((notif) => notifToJSON(notif)), null, 2);
    }
    
    onListChanged: {
        root.list.forEach((notif) => {
            if (!root.latestTimeForApp[notif.appName] || notif.time > root.latestTimeForApp[notif.appName]) {
                root.latestTimeForApp[notif.appName] = Math.max(root.latestTimeForApp[notif.appName] || 0, notif.time);
            }
        });
        Object.keys(root.latestTimeForApp).forEach((appName) => {
            if (!root.list.some((notif) => notif.appName === appName)) {
                delete root.latestTimeForApp[appName];
            }
        });
    }

    function appNameListForGroups(groups) {
        return Object.keys(groups).sort((a, b) => {
            return groups[b].time - groups[a].time;
        });
    }

    function groupsForList(list) {
        const groups = {};
        list.forEach((notif) => {
            if (!groups[notif.appName]) {
                groups[notif.appName] = {
                    appName: notif.appName,
                    appIcon: notif.appIcon,
                    notifications: [],
                    time: 0
                };
            }
            groups[notif.appName].notifications.push(notif);
            groups[notif.appName].time = latestTimeForApp[notif.appName] || notif.time;
        });
        return groups;
    }

    property var groupsByAppName: groupsForList(root.list)
    property var popupGroupsByAppName: groupsForList(root.popupList)
    property list<string> appNameList: appNameListForGroups(root.groupsByAppName)
    property list<string> popupAppNameList: appNameListForGroups(root.popupGroupsByAppName)

    // Quickshell's IDs restart at 1 each run; offset past saved IDs to avoid collisions.
    property int idOffset
    signal initDone();
    signal notify(notification: var);
    signal discard(id: int);
    signal discardAll();
    signal timeout(id: var);

	NotificationServer {
        id: notifServer
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        keepOnReload: false
        persistenceSupported: true

        onNotification: (notification) => {
            notification.tracked = true
            const newNotifObject = notifComponent.createObject(root, {
                "notificationId": notification.id + root.idOffset,
                "notification": notification,
                "time": Date.now(),
            });
			root.list = [...root.list, newNotifObject];

            // Popup — suppressed for muted apps (they still log to history).
            if (!root.popupInhibited && !root.isAppMuted(newNotifObject.appName)) {
                newNotifObject.popup = true;
                if (notification.expireTimeout != 0) {
                    newNotifObject.timer = notifTimerComponent.createObject(root, {
                        "notificationId": newNotifObject.notificationId,
                        "interval": notification.expireTimeout < 0 ? (Config?.options.notifications.timeout ?? 7000) : notification.expireTimeout,
                    });
                }
                root.unread++;
                // Shell-owned sound, inside the popup branch so it shares its gating.
                // Disable apps' own sounds (e.g. Telegram) to avoid doubling.
                if ((Config?.options.notifications.sound ?? false) && !root.isAppSoundOff(newNotifObject.appName)) {
                    const ev = (Config?.options.notifications.soundName ?? "message-new-instant").replace(/'/g, "");
                    Quickshell.execDetached(["bash", "-c",
                        `canberra-gtk-play -i '${ev}' 2>/dev/null || paplay /usr/share/sounds/Oxygen-Im-Message-In.ogg 2>/dev/null`]);
                }
            }
            root.notify(newNotifObject);
            notifFileView.setText(stringifyList(root.list));
        }
    }

    function markAllRead() {
        root.unread = 0;
    }

    function discardNotification(id) {
        console.log("[Notifications] Discarding notification with ID: " + id);
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        if (index !== -1) {
            // createObject(root, ...) gives the object a QML parent, so it is
            // C++-owned and never garbage-collected. Dropping it from the
            // array only drops the array's reference — the object stays a
            // child of this singleton for the life of the shell, holding its
            // strings AND its reference to the server's Notification, which
            // carries the image. destroy() is deferred to the next event loop
            // pass, so callers reading it during this call are unaffected.
            const dead = root.list[index];
            root.list.splice(index, 1);
            notifFileView.setText(stringifyList(root.list));
            triggerListChange()
            if (dead && dead.destroy) dead.destroy();
        }
        if (notifServerIndex !== -1) {
            notifServer.trackedNotifications.values[notifServerIndex].dismiss()
        }
        root.discard(id); // Emit signal
    }

    function discardAllNotifications() {
        // Same as discardNotification: clearing the array frees nothing on its
        // own. Without this, "clear all" made the history look empty while
        // every object it had ever held stayed resident.
        const dead = root.list.slice(0);
        root.list = []
        for (const n of dead) if (n && n.destroy) n.destroy();
        triggerListChange()
        notifFileView.setText(stringifyList(root.list));
        notifServer.trackedNotifications.values.forEach((notif) => {
            notif.dismiss()
        })
        root.discardAll();
    }

    function cancelTimeout(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null && root.list[index].timer != null)
            root.list[index].timer.stop();
    }

    function restartTimeout(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null && root.list[index].timer != null)
            root.list[index].timer.restart();
    }

    function timeoutNotification(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null)
            root.list[index].popup = false;
        root.timeout(id);
    }

    function timeoutAll() {
        root.popupList.forEach((notif) => {
            root.timeout(notif.notificationId);
        })
        root.popupList.forEach((notif) => {
            notif.popup = false;
        });
    }

    function attemptInvokeAction(id, notifIdentifier) {
        console.log("[Notifications] Attempting to invoke action with identifier: " + notifIdentifier + " for notification ID: " + id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        console.log("Notification server index: " + notifServerIndex);
        if (notifServerIndex !== -1) {
            const notifServerNotif = notifServer.trackedNotifications.values[notifServerIndex];
            const action = notifServerNotif.actions.find((action) => action.identifier === notifIdentifier);
            action.invoke()
        } 
        else {
            console.log("Notification not found in server: " + id)
        }
        root.discardNotification(id);
    }

    function triggerListChange() {
        root.list = root.list.slice(0)
    }

    function refresh() {
        notifFileView.reload()
    }

    Component.onCompleted: {
        refresh()
    }

    FileView {
        id: notifFileView
        path: Qt.resolvedUrl(filePath)
        onLoaded: {
            const fileContents = notifFileView.text()
            // Guarded: an unguarded parse threw out of onLoaded and left the
            // list at its empty default — which the next write then persisted,
            // turning one truncated file into permanent history loss.
            let parsed;
            try {
                parsed = JSON.parse(fileContents);
                if (!Array.isArray(parsed)) throw new Error("not an array");
            } catch (e) {
                console.log("[Notifications] history file unreadable, keeping what is in memory:", e);
                return;
            }
            root.list = parsed.map((notif) => {
                return notifComponent.createObject(root, {
                    "notificationId": notif.notificationId,
                    "actions": [], // Notification actions are meaningless if they're not tracked by the server or the sender is dead
                    "appIcon": notif.appIcon,
                    "appName": notif.appName,
                    "body": notif.body,
                    "image": notif.image,
                    "summary": notif.summary,
                    "time": notif.time,
                    "urgency": notif.urgency,
                });
            });
            let maxId = 0
            root.list.forEach((notif) => {
                maxId = Math.max(maxId, notif.notificationId)
            })

            console.log("[Notifications] File loaded")
            root.idOffset = maxId
            root.initDone()
        }
        onLoadFailed: (error) => {
            if(error == FileViewError.FileNotFound) {
                console.log("[Notifications] File not found, creating new file.")
                root.list = []
                notifFileView.setText(stringifyList(root.list));
            } else {
                console.log("[Notifications] Error loading file: " + error)
            }
        }
    }

    // Persisted per-app mute set.
    FileView {
        id: mutedAppsView
        path: Qt.resolvedUrl(root.mutedAppsPath)
        onLoaded: {
            try {
                const o = JSON.parse(mutedAppsView.text());
                if (o && typeof o === "object") {
                    // Legacy format was the muted map directly.
                    root.mutedApps = (o.muted ?? (o.soundOff ? {} : o)) ?? {};
                    root.soundOffApps = o.soundOff ?? {};
                }
            } catch (e) { /* ignore malformed */ }
        }
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) mutedAppsView.setText("{}");
        }
    }
}
