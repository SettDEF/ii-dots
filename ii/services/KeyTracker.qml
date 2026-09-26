// Activity / XP tracker for the HUD level badge.
//
// Hyprland doesn't expose per-keypress events to userspace, so a
// real keylog would need a separate daemon. Instead we treat XP as a
// general "activity" metric — earned for things Quickshell already
// observes via the Hyprland event socket and our own services:
//
//     event                   XP
//     ─────────────────────   ───
//     window focus change      +1
//     workspace switch         +1
//     window open (app launch) +10
//     submap entered/exited    +2
//     hud / corner popup open  +2  (per session)
//     notification received    +5
//
// `lastKey` shows whatever Hyprland just signalled (e.g.
// `activewindow: kitty`), so the HUD line above the level badge stays
// alive without needing a /dev/input keylogger.
//
// xpTotal is persisted to ~/.local/share/qs-hud-xp so progress
// survives restart.
pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    property string lastKey: ""
    property real   xpTotal: 0
    readonly property int xpLevel: Math.floor(xpTotal / 1000) + 1

    // ── lastKey display: cleared after 1.5 s ────────────────────────
    Timer {
        id: clearTimer
        interval: 1500; repeat: false
        onTriggered: root.lastKey = ""
    }
    function flashKey(s) {
        if (!s) return
        if (s !== root.lastKey) root.lastKey = s
        clearTimer.restart()
    }

    // ── XP gain ─────────────────────────────────────────────────────
    function addXp(amount, label) {
        if (!amount) return
        root.xpTotal = root.xpTotal + amount
        if (label) flashKey(label)
        // Throttled disk persist via Timer. 30 s debounce means at most
        // one write per half-minute of sustained activity, and exactly
        // zero writes when the user is idle.
        persistTimer.restart()
    }

    Timer {
        id: persistTimer
        interval: 30000; repeat: false
        onTriggered: xpFile.setText(String(root.xpTotal))
    }

    // ── Persistence: FileView is far cheaper than bash exec — no
    // fork/exec, just a syscall.
    FileView {
        id: xpFile
        path: Qt.resolvedUrl(`file://${Quickshell.env("HOME")}/.local/share/qs-hud-xp`)
        onLoaded: {
            const v = parseFloat((text() || "0").trim())
            if (isFinite(v)) root.xpTotal = v
        }
        onLoadFailed: root.xpTotal = 0
        Component.onCompleted: reload()
    }

    // ── Hyprland event hooks ────────────────────────────────────────
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const name = event.name
            const data = (event.data ?? "").toString()
            // Hyprland emits paired events (workspace + workspacev2,
            // activewindow + activewindowv2). Count only the v2 form
            // when both exist — that's the canonical version with more
            // structured data — to avoid double-XP per user action.
            switch (name) {
                case "activewindowv2":
                    addXp(1, "focus")
                    break
                case "workspacev2":
                    addXp(1, "ws " + data.split(",")[0])
                    break
                case "openwindow":
                    addXp(10, "+ " + (data.split(",")[2] || "window"))
                    break
                case "submap":
                    addXp(2, data || "submap")
                    break
                case "fullscreen":
                    addXp(2, data === "1" ? "fullscreen" : "windowed")
                    break
            }
        }
    }

    // ── HUD / popup open events (small per-session bonus) ───────────
    property bool _hudCounted: false
    property bool _popupCounted: false
    Connections {
        target: GlobalStates
        function onHudOpenChanged() {
            if (GlobalStates.hudOpen && !root._hudCounted) {
                root._hudCounted = true
                addXp(2, "HUD")
            } else if (!GlobalStates.hudOpen) {
                root._hudCounted = false
            }
        }
        function onCornerPopupOpenChanged() {
            if (GlobalStates.cornerPopupOpen && !root._popupCounted) {
                root._popupCounted = true
                addXp(2, "popup")
            } else if (!GlobalStates.cornerPopupOpen) {
                root._popupCounted = false
            }
        }
    }

    // ── Notification gain ───────────────────────────────────────────
    // Notifications service emits notification events; if we don't
    // have direct access we fall back to count-based detection.
    property int _notifSeen: 0
    Connections {
        target: Notifications
        ignoreUnknownSignals: true
        function onUnreadChanged() {
            // Only count *new* notifications, not dismissals.
            const n = Notifications.unread ?? 0
            if (n > root._notifSeen) {
                addXp(5 * (n - root._notifSeen), "notification")
            }
            root._notifSeen = n
        }
    }
}
