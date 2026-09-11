pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * LauncherRanking — decides what order launcher entries come back in.
 *
 * Three separate signals, deliberately kept apart:
 *
 *   launch counts   how often an entry was started, and when it was last
 *                   started. Owned here, persisted to its own JSON file.
 *   manual priority an ordered id list in Config (launcher.priorityApps).
 *                   Index 0 outranks index 1. Applied as a BOOST on top of
 *                   whichever sort is active rather than being a sort of its
 *                   own, so pinning something doesn't force you out of
 *                   relevance ordering.
 *   hidden          ids the user never wants to see (launcher.hiddenApps).
 *
 * NOT to be confused with the existing AppUsage service, which measures
 * FOCUS SECONDS per day. That answers "what do I spend time in"; this answers
 * "what do I start". An IDE you leave open all day dominates the former and
 * says nothing useful about the latter.
 *
 * PERSISTENCE NOTE — this uses a standalone FileView + a plain `var`, NOT a
 * JsonAdapter. Quickshell's JsonAdapter segfaults on a `property var` inside a
 * nested JsonObject when the file is reloaded (see the warnings in Config.qml
 * and Persistent.qml), and this store is keyed by arbitrary desktop-entry ids.
 * Settings that are NOT dynamically keyed still live in Config, where they
 * belong.
 */
Singleton {
    id: root

    // ── Live data ────────────────────────────────────────────────────────
    // Shape: { "<appId>": { n: <launch count>, last: <epoch ms> } }
    property var launches: ({})

    // Mutating a JS object in place emits no change signal, so bindings that
    // read through the functions below would never re-evaluate. Every mutation
    // bumps this, and the functions reference it, which makes them reactive.
    property int revision: 0

    readonly property string storePath: FileUtils.trimFileProtocol(
        `${Directories.state}/user/launcher-ranking.json`)

    // ── Tunables (from Config) ───────────────────────────────────────────
    readonly property bool trackingEnabled: Config.options?.launcher?.trackUsage ?? true
    // Days after which a launch counts half as much. Small = "what I use NOW"
    // wins; large = lifetime totals win. 14 is a middle ground.
    readonly property real halfLifeDays: Config.options?.launcher?.frecencyHalfLife ?? 14
    readonly property var priorityApps: Config.options?.launcher?.priorityApps ?? []
    readonly property var hiddenApps: Config.options?.launcher?.hiddenApps ?? []

    // ── Reads ────────────────────────────────────────────────────────────
    function count(id) {
        root.revision // dependency
        if (!id) return 0
        return root.launches[id]?.n ?? 0
    }

    function lastUsed(id) {
        root.revision
        if (!id) return 0
        return root.launches[id]?.last ?? 0
    }

    /**
     * Frecency: launch count decayed by how long ago it was last used.
     *
     *     score = n * 2^(-ageDays / halfLifeDays)
     *
     * Raw counts ossify — something launched 200 times last year outranks the
     * thing you opened twice this morning forever. Decay fixes that while
     * still rewarding sustained use.
     */
    function frecency(id) {
        root.revision
        const rec = root.launches[id]
        if (!rec || !rec.n) return 0
        const ageDays = Math.max(0, (Date.now() - (rec.last ?? 0)) / 86400000)
        const hl = Math.max(0.1, root.halfLifeDays)
        return rec.n * Math.pow(2, -ageDays / hl)
    }

    // Higher = more important. 0 means "not prioritised".
    function priorityOf(id) {
        if (!id) return 0
        const i = root.priorityApps.indexOf(id)
        return i < 0 ? 0 : (root.priorityApps.length - i)
    }

    function isHidden(id) {
        return !!id && root.hiddenApps.indexOf(id) >= 0
    }

    // ── Writes ───────────────────────────────────────────────────────────
    function recordLaunch(id) {
        // Guard on a real id: AppLaunch.launch() is also handed desktop-action
        // objects whose id is "", and counting those would create a junk key.
        if (!root.trackingEnabled || !id || id.length === 0) return
        const cur = root.launches[id] ?? { n: 0, last: 0 }
        cur.n = (cur.n ?? 0) + 1
        cur.last = Date.now()
        root.launches[id] = cur
        root.revision++
        saveTimer.restart()
    }

    function resetOne(id) {
        if (!id || !root.launches[id]) return
        delete root.launches[id]
        root.revision++
        saveTimer.restart()
    }

    function resetAll() {
        root.launches = ({})
        root.revision++
        saveTimer.restart()
    }

    // ── Priority list helpers (ordered id list, mirrors launcher.pinnedApps) ──
    // An ordered list rather than an {id: rank} map: dynamic keys are exactly
    // what the JsonAdapter cannot store safely.
    function _writeList(key, arr) {
        Config.options.launcher[key] = arr.slice()
    }

    function raisePriority(id) {
        if (!id) return
        const arr = root.priorityApps.slice()
        const i = arr.indexOf(id)
        if (i < 0) arr.unshift(id)          // not listed → straight to the top
        else if (i > 0) { arr.splice(i, 1); arr.splice(i - 1, 0, id) }
        root._writeList("priorityApps", arr)
    }

    function lowerPriority(id) {
        if (!id) return
        const arr = root.priorityApps.slice()
        const i = arr.indexOf(id)
        if (i < 0 || i >= arr.length - 1) return
        arr.splice(i, 1); arr.splice(i + 1, 0, id)
        root._writeList("priorityApps", arr)
    }

    function togglePriority(id) {
        if (!id) return
        const arr = root.priorityApps.slice()
        const i = arr.indexOf(id)
        if (i < 0) arr.unshift(id); else arr.splice(i, 1)
        root._writeList("priorityApps", arr)
    }

    function clearPriorities() { root._writeList("priorityApps", []) }

    function toggleHidden(id) {
        if (!id) return
        const arr = root.hiddenApps.slice()
        const i = arr.indexOf(id)
        if (i < 0) arr.push(id); else arr.splice(i, 1)
        root._writeList("hiddenApps", arr)
    }

    function clearHidden() { root._writeList("hiddenApps", []) }

    // ── Sorting ──────────────────────────────────────────────────────────
    // Every mode is a comparator over { entry, score } where `score` is the
    // fuzzy-match score (only meaningful for "relevance").
    //
    // `priorityBoost` is added on top of ALL modes so a prioritised entry
    // floats without hijacking the chosen ordering.
    readonly property var sortModes: [
        { id: "frecency",     label: qsTr("Smart"),        icon: "auto_awesome",
          hint: qsTr("Most used, weighted toward recent") },
        { id: "relevance",    label: qsTr("Relevance"),    icon: "search",
          hint: qsTr("Best text match for what you typed") },
        { id: "frequency",    label: qsTr("Most used"),    icon: "trending_up",
          hint: qsTr("Highest lifetime launch count") },
        { id: "recent",       label: qsTr("Recent"),       icon: "history",
          hint: qsTr("Most recently launched first") },
        { id: "alphabetical", label: qsTr("A–Z"),          icon: "sort_by_alpha",
          hint: qsTr("Plain alphabetical order") },
    ]

    function _key(item, mode) {
        const id = item.entry?.id ?? ""
        switch (mode) {
        case "frequency":    return root.count(id)
        case "recent":       return root.lastUsed(id)
        case "frecency":     return root.frecency(id)
        case "alphabetical": return 0        // handled by the name tiebreak
        default:             return item.score ?? 0
        }
    }

    /**
     * Order a [{entry, score}] list. Returns a new array; does not mutate.
     * Hidden entries are dropped unless showHidden is set.
     */
    function apply(items, mode, opts) {
        const o = opts ?? ({})
        const m = mode ?? "frecency"
        let out = items.filter(it => o.showHidden || !root.isHidden(it.entry?.id))

        const boost = o.usePriority === false ? 0 : 1
        out.sort((a, b) => {
            const ai = a.entry?.id ?? "", bi = b.entry?.id ?? ""
            if (boost) {
                const pd = root.priorityOf(bi) - root.priorityOf(ai)
                if (pd !== 0) return pd
            }
            if (m === "alphabetical") {
                return (a.entry?.name ?? "").localeCompare(b.entry?.name ?? "")
            }
            const d = root._key(b, m) - root._key(a, m)
            if (d !== 0) return d
            // Stable, meaningful tiebreak: fall back to match quality, then name.
            const sd = (b.score ?? 0) - (a.score ?? 0)
            if (sd !== 0) return sd
            return (a.entry?.name ?? "").localeCompare(b.entry?.name ?? "")
        })
        if (o.reverse) out.reverse()
        if (o.limit > 0) out = out.slice(0, o.limit)
        return out
    }

    // ── Persistence ──────────────────────────────────────────────────────
    FileView {
        id: store
        path: Qt.resolvedUrl(`file://${root.storePath}`)
        onLoaded: {
            try {
                const d = JSON.parse(store.text() || "{}")
                if (d && typeof d === "object" && d.launches) {
                    root.launches = d.launches
                    root.revision++
                }
            } catch (e) {
                // Corrupt file — start clean rather than taking the shell down.
            }
        }
        onLoadFailed: root.launches = ({})
        Component.onCompleted: reload()
    }

    function save() {
        store.setText(JSON.stringify({ version: 1, launches: root.launches }))
    }

    // Debounced: a launch burst (or holding Enter) must not cause a write per
    // event. Also flushed periodically and on shutdown so a crash loses little.
    Timer {
        id: saveTimer
        interval: 4000
        repeat: false
        onTriggered: root.save()
    }
    Timer {
        interval: 120000
        running: true
        repeat: true
        onTriggered: if (saveTimer.running) root.save()
    }
    Component.onDestruction: root.save()
}
