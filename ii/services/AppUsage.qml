pragma Singleton
pragma ComponentBehavior: Bound

// App-usage / screen-time tracker.
//
// Watches the focused window and accumulates seconds per app,
// bucketed by day and by hour-of-day. Persisted to
// ~/.local/state/quickshell/app-usage.json so history survives
// restarts — the HUD "Screen Time" tab reads it back.
//
// Store shape:
//   data.days["YYYY-MM-DD"] = {
//     total:    int,                    // seconds
//     apps:     { appId: int },         // per-app seconds
//     hours:    [24 ints],              // seconds per hour-of-day
//     appHours: { appId: [24 ints] }    // per-app per-hour
//   }
//
// Idle note: idle time isn't separately detected — hypridle locks the
// session on idle, so `!screenLocked` is a fair proxy for "active".

import qs
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root

    property var data: ({ days: ({}) })
    // Bumped on every change so QML bindings re-read the mutated store.
    property int revision: 0

    readonly property int tickSeconds: 15

    // Focused app id; empty → "Desktop".
    readonly property string currentApp: {
        const tl = ToplevelManager.activeToplevel
        const id = tl ? (tl.appId ?? "") : ""
        return id.length > 0 ? id : "Desktop"
    }
    readonly property bool counting: !GlobalStates.screenLocked

    function todayKey() {
        return Qt.formatDate(new Date(), "yyyy-MM-dd")
    }

    function _blankDay() {
        return { total: 0, apps: ({}), hours: new Array(24).fill(0), appHours: ({}) }
    }
    function dayData(dateStr) {
        return root.data.days[dateStr] || root._blankDay()
    }

    function addSeconds(app, secs) {
        const dk = root.todayKey()
        if (!root.data.days[dk])
            root.data.days[dk] = root._blankDay()
        const day = root.data.days[dk]
        const h = (new Date()).getHours()
        day.total += secs
        day.apps[app] = (day.apps[app] || 0) + secs
        day.hours[h] += secs
        if (!day.appHours[app])
            day.appHours[app] = new Array(24).fill(0)
        day.appHours[app][h] += secs
        root.revision++
    }

    // ── Queries (all re-evaluate when `revision` changes) ─────────
    readonly property var today: { root.revision; return root.dayData(root.todayKey()) }
    readonly property int todayTotal: { root.revision; return root.today.total }
    readonly property int yesterdayTotal: {
        root.revision
        const d = new Date()
        d.setDate(d.getDate() - 1)
        return root.dayData(Qt.formatDate(d, "yyyy-MM-dd")).total
    }

    // Apps for a day, sorted desc by seconds → [{ app, seconds }].
    function appsForDay(dateStr) {
        const a = root.dayData(dateStr).apps
        return Object.keys(a)
            .map(k => ({ app: k, seconds: a[k] }))
            .sort((x, y) => y.seconds - x.seconds)
    }

    // Last 7 days incl. today, oldest first → [{ date, label, total }].
    function last7Days() {
        const out = []
        for (let i = 6; i >= 0; i--) {
            const d = new Date()
            d.setDate(d.getDate() - i)
            const key = Qt.formatDate(d, "yyyy-MM-dd")
            out.push({ date: key, label: Qt.formatDate(d, "ddd"),
                       total: root.dayData(key).total })
        }
        return out
    }

    // Every day of a month → [{ date, day, total }] (day = 1..N).
    function monthDays(year, monthIdx) {
        const out = []
        const n = new Date(year, monthIdx + 1, 0).getDate()
        for (let dd = 1; dd <= n; dd++) {
            const key = Qt.formatDate(new Date(year, monthIdx, dd), "yyyy-MM-dd")
            out.push({ date: key, day: dd, total: root.dayData(key).total })
        }
        return out
    }

    // Busiest 2-hour window of a day → { start, end, seconds }.
    // `start`/`end` are hours-of-day (0-24); start = -1 when no usage.
    function peakWindow(dateStr) {
        const h = root.dayData(dateStr).hours || []
        let bestStart = -1, best = 0
        for (let i = 0; i < 23; i++) {
            const v = (h[i] || 0) + (h[i + 1] || 0)
            if (v > best) { best = v; bestStart = i }
        }
        return { start: bestStart,
                 end: bestStart < 0 ? -1 : bestStart + 2,
                 seconds: best }
    }

    // Average daily total over the last 7 days (seconds).
    readonly property int weekAverage: {
        root.revision
        const w = root.last7Days()
        let sum = 0
        for (const e of w) sum += e.total
        return Math.round(sum / 7)
    }

    // "Hh Mm" pretty-print.
    function pretty(secs) {
        const m = Math.round(secs / 60)
        const h = Math.floor(m / 60)
        const mm = m % 60
        if (h > 0) return h + "h " + mm + "m"
        return mm + "m"
    }

    // ── Tracking tick ─────────────────────────────────────────────
    Timer {
        interval: root.tickSeconds * 1000
        running: true
        repeat: true
        onTriggered: {
            if (root.counting)
                root.addSeconds(root.currentApp, root.tickSeconds)
        }
    }

    // ── Persistence ───────────────────────────────────────────────
    FileView {
        id: store
        path: Qt.resolvedUrl(`file://${Quickshell.env("HOME")}/.local/state/quickshell/app-usage.json`)
        onLoaded: {
            try {
                const d = JSON.parse(store.text() || "{}")
                if (d && d.days) {
                    root.data = d
                    root.revision++
                }
            } catch (e) {
                // Corrupt file — start fresh, don't crash.
            }
        }
        onLoadFailed: root.data = ({ days: ({}) })
        Component.onCompleted: reload()
    }
    function save() {
        store.setText(JSON.stringify(root.data))
    }
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.save()
    }
    Component.onDestruction: root.save()
}
