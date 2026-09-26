pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

Item {
    id: root
    signal close()

    readonly property string home: `${Quickshell.env("HOME")}`
    // local | wallhaven | reddit | videos, owned by WallpaperHub.
    readonly property string activeSource: WallpaperHub.source
    readonly property string activeMediaType: WallpaperHub.mediaType   // all | pic | vid | we
    readonly property bool favoritesOnly: WallpaperHub.favoritesOnly
    readonly property string viewLayout: WallpaperHub.viewLayout
    readonly property string redditForcedSort: WallpaperHub.forcedSort
    property int activeIndex: 0
    property string query: ""
    property var wallpapers: []
    property bool loading: false

    // ── Pagination state for the active source ────────────────────────
    property int  whPage:        1
    property bool whHasMore:     true
    property bool whLoadingMore: false
    // Prefetch once past this share of the loaded list.
    readonly property real loadMoreThreshold: 0.35
    // Also prefetch once this many items remain ahead (keeps the chain alive on long lists).
    readonly property int prefetchHeadroom: 20

    // Hue palette — 13 buckets, `wh` = Wallhaven's fixed 27-colour API code.
    // Lives in WallpaperHub so the launcher and skwd share the same columns.
    readonly property var hues: WallpaperHub.hues
    // ── Client-side palette extraction (for Reddit + local items) ─────
    // Wallhaven gives us a palette; for other sources tinct extracts one, cached by item id.
    property var palettesByItemId: ({})

    function paletteFor(item) {
        if (!item) return []
        if (Array.isArray(item.palette) && item.palette.length > 0) return item.palette
        return palettesByItemId[item.id] ?? []
    }

    // A local file for tinct: the thumb when there is one. Remote items carry their own palette.
    function _palImageFor(item) {
        if (!item) return ""
        const src = String(item.thumb || item.full || item.path || "")
        const file = src.startsWith("file://") ? decodeURIComponent(src.slice(7)) : src
        return file.startsWith("/") ? file : ""
    }

    // Debounced: extracting on every touchpad index change froze the shell.
    Timer {
        id: focusSettle
        interval: 180
        repeat: false
        onTriggered: {
            if (paletteExtractProc.running || metaProc.running || themeProc.running) {
                // Busy from the last settle — come back rather than piling on.
                focusSettle.restart()
                return
            }
            const i = root.activeIndex
            if (i >= 0 && i < root.filtered.length) {
                root._ensurePaletteFor(root.filtered[i])
                root._ensureThemeFor(root.filtered[i])
                root._fetchMetaFor(root.filtered[i])
            }
        }
    }

    // ── Theme preview ─────────────────────────────────────────────────
    // What applying would theme the shell as: the same tinct call switchwall
    // makes (scheme from config, auto = tinct's own pick), on the thumbnail.
    property var themeByItemId: ({})
    property string _themeMode: "dark"
    Process {
        running: true
        command: ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"]
        stdout: StdioCollector {
            onStreamFinished: root._themeMode = text.indexOf("light") >= 0 ? "light" : "dark"
        }
    }
    // Keyed by scheme and mode too, so changing either does not show a stale preview.
    function _themeKey(item) {
        if (!item || !item.id) return ""
        return `${item.id}|${Config.options.appearance.palette.type || "auto"}|${root._themeMode}`
    }
    function _ensureThemeFor(item) {
        const key = root._themeKey(item)
        if (!key || root.themeByItemId[key] !== undefined || themeProc.running) return
        const src = String(item.thumb || item.path || "")
        const file = src.startsWith("file://") ? decodeURIComponent(src.slice(7)) : src
        if (!file.startsWith("/") || TinctApps.bin === "") return
        const type = Config.options.appearance.palette.type || "auto"
        themeProc.itemId = key
        themeProc.command = [TinctApps.bin, "generate", "--path", file, "--scheme", type,
                             "--mode", root._themeMode, "--json"]
        themeProc.running = true
    }
    Process {
        id: themeProc
        property string itemId: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let t = null
                try { t = JSON.parse(text) } catch (e) { return }
                const next = Object.assign({}, root.themeByItemId)
                next[themeProc.itemId] = t
                root.themeByItemId = next
                if (root._themeKey(WallpaperHub.focusedItem) === themeProc.itemId) WallpaperHub.focusedTheme = t
            }
        }
    }

    function _ensurePaletteFor(item) {
        if (!item || !item.id) return
        if (palettesByItemId[item.id] !== undefined) return
        if (Array.isArray(item.palette) && item.palette.length > 0) return
        const img = _palImageFor(item)
        if (!img) return
        paletteExtractProc.itemId = item.id
        // Heredoc-safe escaping
        const safe = String(img).replace(/'/g, "'\\''")
        paletteExtractProc.command = ["bash", "-c",
            `timeout 4 "$HOME/.local/bin/tinct" image colors '${safe}' --count 5 2>/dev/null`
        ]
        paletteExtractProc.running = true
    }

    Process {
        id: paletteExtractProc
        property string itemId: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const colors = text.trim().split("\n").filter(s => /^#[0-9A-Fa-f]{6}$/.test(s))
                if (colors.length === 0) return
                const next = Object.assign({}, root.palettesByItemId)
                next[paletteExtractProc.itemId] = colors
                root.palettesByItemId = next
            }
        }
    }

    // The selected Wallhaven hex code (no `#`), owned by WallpaperHub.
    readonly property string whColors: WallpaperHub.colors
    function toggleColor(wh) {
        WallpaperHub.toggleColor(wh)
    }
    readonly property string whTerms: WallpaperHub.whTerms
    onWhTermsChanged: if (root.activeSource === "wallhaven") root.queueRefresh()

    readonly property var sources: [
        { id: "local",     icon: "folder",   label: qsTr("Local")     },
        { id: "wallhaven", icon: "public",   label: qsTr("Wallhaven") },
        { id: "reddit",    icon: "forum",    label: qsTr("Reddit")    },
        { id: "videos",    icon: "movie",    label: qsTr("Videos")    },
    ]

    readonly property var mediaTypes: [
        { id: "all", label: "ALL" },
        { id: "pic", label: "PIC" },
        { id: "vid", label: "VID" },
        { id: "we",  label: "WE"  },
    ]

    readonly property var filtered: {
        let list = wallpapers
        // Favourites filter (the heart in the launcher).
        if (root.favoritesOnly)
            list = list.filter(w => WallpaperHub.isFavorite(w.path))
        // Videos tab always filters to kind==vid, regardless of the media-type chip.
        if (activeSource === "videos")
            list = list.filter(w => (w.kind ?? "pic") === "vid")
        if (activeMediaType !== "all")
            list = list.filter(w => (w.kind ?? "pic") === activeMediaType)
        // Reddit/Videos: query filters cached files locally. Wallhaven/local: consumed by the fetcher instead.
        if (activeSource === "reddit" || activeSource === "videos") {
            let q = (root.query || "").trim().toLowerCase()
            q = q.replace(/^r\//, "")
            if (q.length > 0) {
                // Prefer an EXACT subreddit match; fuzzy-match only if nothing matches.
                const exact = list.filter(w => (w.subreddit || "").toLowerCase() === q)
                if (exact.length > 0) {
                    list = exact
                } else {
                    list = list.filter(w =>
                        (w.subreddit || "").toLowerCase().includes(q)
                     || (w.title     || "").toLowerCase().includes(q)
                     || (w.id        || "").toLowerCase().includes(q))
                }
            }
        }
        return list
    }

    // ── Sources ───────────────────────────────────────────────────────
    Process {
        id: localScanProc
        // Extracts a poster frame per video with ffmpeg (Image can't render mp4). Output: kind|thumbpath|realpath.
        command: ["bash", "-c",
            `postdir="$HOME/.cache/quickshell/skwd-posters"; mkdir -p "$postdir"; \\
             find ${root.home}/Pictures/Wallpapers ${root.home}/Pictures/Wallpapers/skwd 2>/dev/null \\
                -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \\
                          -o -iname '*.webp' -o -iname '*.mp4' -o -iname '*.webm' \\
                          -o -iname '*.mkv' -o -iname '*.gif' \\) \\
             | sort -u | head -200 | while IFS= read -r f; do \\
                case "\${f,,}" in \\
                  *.mp4|*.webm|*.mkv|*.gif) \\
                    h=$(printf '%s' "$f" | md5sum | cut -d' ' -f1); \\
                    p="$postdir/$h.jpg"; \\
                    [ -f "$p" ] || ffmpeg -nostdin -y -loglevel quiet \\
                        -i "$f" -vf 'scale=480:-1' -vframes 1 "$p" 2>/dev/null; \\
                    echo "vid|$p|$f" ;; \\
                  *) echo "pic|$f|$f" ;; \\
                esac; \\
             done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l.length > 0)
                root.wallpapers = lines.map(line => {
                    const parts = line.split("|")
                    const kind  = parts[0] || "pic"
                    const thumb = parts[1] || parts[2]
                    const real  = parts[2] || parts[1]
                    return {
                        id: real,
                        title: real.split("/").pop(),
                        // Carousel shows the poster jpg for videos.
                        thumb: "file://" + thumb,
                        full:  "file://" + thumb,
                        source: "local",
                        kind: kind,
                        // path is the REAL file — switchwall.sh's is_video() detects .mp4 and runs mpvpaper.
                        path: real,
                    }
                })
                root.loading = false
            }
        }
    }

    // Applies one page of rows to the carousel: parses, dedupes, restores scroll spot.
    function _applyQuarryPage(data, append) {
        const fresh = (data.data || []).map(w => ({
            id: w.id,
            title: w.title || w.id,
            thumb: w.thumbs?.small ?? w.thumbs?.original ?? w.path,
            full:  w.path,
            // Actual source per row (not all wallhaven any more) — feeds the badge.
            source: w.source || "quarry",
            kind: w.kind || "pic",
            path: w.path,
            // Dominant-colour palette, used for the glow/swatch strip around the focused item.
            palette: Array.isArray(w.colors) ? w.colors.slice(0, 5) : [],
        }))
        const meta = data.meta ?? {}
        const lastPage = meta.last_page ?? 1
        root.whHasMore = (root.whPage < lastPage) && fresh.length > 0

        if (append) {
            // Dedupe by id so an overlapping page can't show the same picture twice.
            const seen = new Set(root.wallpapers.map(w => w.id))
            const keepIdx = root.activeIndex
            root.wallpapers = root.wallpapers.concat(fresh.filter(w => !seen.has(w.id)))
            // ListView resets currentIndex when the model array flips; restore once the binding storm settles.
            Qt.callLater(() => {
                if (keepIdx >= 0 && keepIdx < root.filtered.length
                        && root.activeIndex !== keepIdx)
                    root.activeIndex = keepIdx
            })
        } else {
            root.wallpapers = fresh
        }
    }

    // Fetches one page via quarry (data[]/meta, same shape Wallhaven's API used).
    // The query this tab asks quarry for: tab = scope, text box = search.
    function _quarryQuery(term) {
        return [(term || "").trim(), root.quarryScope].filter(s => s.length > 0).join(" ")
    }

    // Quarry holds one persistent socket connection, so paging is fast.
    function _fetchQuarry(term, page, append) {
        if (!Quarry.connected) {
            // Say so rather than showing an empty tab: the daemon starts on demand.
            root.loading = false
            root.whLoadingMore = false
            return
        }
        root.whLoadingMore = append
        Quarry.page(root._quarryQuery(term), page, 24, function (err, payload) {
            root.whLoadingMore = false
            root.loading = false
            if (err || !payload) return
            root._applyQuarryPage(payload, append)
        })
    }

    // Which scope each tab maps to, in quarry's query language.
    readonly property string quarryScope: {
        switch (root.activeSource) {
        case "wallhaven":
            return ("source:wallhaven kind:wallpaper " + WallpaperHub.whTerms).trim()
        case "videos":
            // Anything that moves, whatever board it came from.
            return "family:video"
        case "reddit":
            return "source:reddit"
        case "local":
            return "source:local"
        default:
            return "kind:wallpaper"
        }
    }

    // Tabs served by quarry; the rest keep their own fetchers.
    readonly property bool quarryServes: root.quarrySources.indexOf(root.activeSource) >= 0
    property var quarrySources: ["wallhaven", "videos", "local", "reddit"]

    function loadMoreWallhaven() {
        if (!root.quarryServes) return
        if (root.loading || root.whLoadingMore || !root.whHasMore) return
        root.whLoadingMore = true
        root.whPage += 1
        root._fetchQuarry(root.query.trim(), root.whPage, true)
    }

    // How many cached files the scan loads at once; grown in pages as the user reaches the end.
    readonly property int scanPageSize: 400
    property int scanLimit: scanPageSize
    property real lastScanTime: 0
    // incremental: only files newer than lastScanTime, appended. A full scan while one runs is queued, not raced.
    property bool _fullScanQueued: false
    function runScan(incremental) {
        if (redditScanProc.running) {
            if (!incremental) root._fullScanQueued = true
            return
        }
        redditScanProc.since = incremental ? root.lastScanTime : 0
        redditScanProc.append = incremental
        redditScanProc.running = true
    }

    // ── Reddit (cached via gallery-dl) ────────────────────────────────
    // Filenames are "<id> <title> [WxH].ext"; id is the leading non-space token.
    Process {
        id: redditScanProc
        onRunningChanged: if (!running && root._fullScanQueued) {
            root._fullScanQueued = false
            root.runScan(false)
        }
        // Sub whose cache to scan (reddit + videos share this cache). Without it,
        // a sub outside the newest-200-across-all-subs window showed "Nothing cached".
        readonly property string scanSub: {
            if (root.activeSource !== "reddit" && root.activeSource !== "videos")
                return ""
            const q = (root.query || "").trim()
            return q.replace(/^r\//i, "").replace(/[^A-Za-z0-9_]/g, "")
        }
        // > 0 → only list files newer than this epoch time, appended (fast incremental rescan during a sync).
        property real since: 0
        property bool append: false
        // Scans both the new and legacy gallery-dl roots; each video's first
        // frame is cached as a poster jpg. Output: kind|posterpath|realpath.
        command: ["bash", "-c",
            `postdir="$HOME/.cache/quickshell/skwd-posters"; mkdir -p "$postdir"
             sub='${redditScanProc.scanSub}'
             limit='${root.scanLimit}'
             since='${Math.floor(redditScanProc.since)}'
             newer=(); [ "$since" -gt 0 ] && newer=( -newermt "@$since" )
             roots=( "$HOME/Pictures/Wallpapers/skwd/reddit" "$HOME/Pictures/Wallpapers/skwd/redgifs" "$HOME/.config/gallery-dl/reddit" "$HOME/.config/gallery-dl/redgifs" )
             exist=(); for r in "\${roots[@]}"; do [ -d "$r" ] && exist+=("$r"); done
             [ \${#exist[@]} -eq 0 ] && exit 0
             types=( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.m4v' -o -iname '*.mkv' -o -iname '*.mov' )
             list=""
             # Asked for one sub → take that sub's WHOLE folder (newest first),
             # case-insensitively, so the carousel holds everything cached for
             # it instead of whatever happened to be downloaded most recently.
             # Matched as a DIRECTORY name, not with -ipath on the full path:
             # the roots live under ~/Pictures/Wallpapers, so a path glob for
             # r/wallpapers matches that prefix too and drags in every sub.
             if [ -n "$sub" ]; then
               mapfile -t sdirs < <(find "\${exist[@]}" -mindepth 1 -maxdepth 1 -type d -iname "$sub" 2>/dev/null)
               if [ \${#sdirs[@]} -gt 0 ]; then
                 list=$(find "\${sdirs[@]}" -maxdepth 1 -type f "\${newer[@]}" \\( "\${types[@]}" \\) -printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | head -"$limit")
               fi
             fi
             # No sub (or nothing cached for it) → newest across every sub.
             # Skipped for incremental passes: there we only want new arrivals.
             if [ -z "$list" ] && [ "$since" -eq 0 ]; then
               list=$(find "\${exist[@]}" -maxdepth 2 -type f \\( "\${types[@]}" \\) -printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | head -200)
             fi
             [ -z "$list" ] && exit 0
             # Hash every path once, in one process (was two md5sum spawns per
             # file: ~2.6 s for 400). Same hashes, so the thumbnail cache holds.
             list=$(printf '%s\\n' "$list" | perl -MDigest::MD5=md5_hex -ne 'chomp; my ($t,$f)=split /\\t/,$_,2; next unless defined $f && length $f; print "$t\\t",md5_hex($f),"\\t$f\\n"')
             [ -z "$list" ] && exit 0
             # Phase 1: missing thumbnails. Pictures go to one tinct process that
             # uses every core; videos need ffmpeg for a frame.
             maxj=$(nproc)
             pics=""
             while IFS=$'\\t' read -r t h f; do
               [ -z "$f" ] && continue
               p="$postdir/$h.jpg"
               [ -f "$p" ] && continue
               case "\${f,,}" in
                 *.mp4|*.webm|*.m4v|*.mkv|*.mov|*.gif)
                   ffmpeg -nostdin -y -loglevel quiet -i "$f" -vf 'scale=720:-2' -vframes 1 "$p" 2>/dev/null &
                   while [ "$(jobs -rp | wc -l)" -ge "$maxj" ]; do wait -n; done ;;
                 *) pics+="$f"$'\\t'"$p"$'\\n' ;;
               esac
             done <<< "$list"
             [ -n "$pics" ] && printf '%s' "$pics" | "$HOME/.local/bin/tinct" image thumb --batch --width --size 720 --quality 80 >/dev/null 2>&1
             wait
             # Phase 2: emit model lines (newest first), thumbnail if it exists.
             # mtime is the last field, for ordering by age.
             while IFS=$'\\t' read -r t h f; do
               [ -z "$f" ] && continue
               p="$postdir/$h.jpg"
               case "\${f,,}" in
                 *.mp4|*.webm|*.m4v|*.mkv|*.mov|*.gif) [ -f "$p" ] && echo "vid|$p|$f|$t" || echo "vid|$f|$f|$t" ;;
                 *) [ -f "$p" ] && echo "pic|$p|$f|$t" || echo "pic|$f|$f|$t" ;;
               esac
             done <<< "$list"`]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l.length > 0)
                const parsed = lines.map(line => {
                    const cols  = line.split("|")
                    const kind  = cols[0] || "pic"
                    // mtime is last, so a "|" in a filename cannot shift it.
                    const mtime = cols.length >= 4 ? (parseFloat(cols[cols.length - 1]) || 0) : 0
                    const real  = cols.length >= 4 ? cols.slice(2, cols.length - 1).join("|")
                                                   : (cols[2] || cols[1])
                    const thumb = cols[1] || real
                    const parts = real.split("/")
                    const name  = parts[parts.length - 1]
                    // Subreddit = parent dir name (gallery-dl: .../reddit/<SUB>/<file>); "" for legacy layouts.
                    const subreddit = parts[parts.length - 2] || ""
                    // gallery-dl names are "<postid> <title>"; other files have no id, so the
                    // path is the key (a first word like "The" collided across wallpapers).
                    const idMatch = name.match(/^((?=[a-z0-9]*\d)[a-z0-9]{5,10})\s+/)
                    // file:// URLs must URL-encode spaces/`#` or Qt's Image refuses with "Cannot open".
                    const encUrl = function(p) {
                        return "file://" + p.split("/").map(encodeURIComponent).join("/")
                    }
                    return {
                        id: real,
                        postId: idMatch ? idMatch[1] : "",
                        title: (idMatch ? name.slice(idMatch[0].length) : name).replace(/\.[a-z0-9]+$/i, ""),
                        subreddit: subreddit,
                        thumb:  encUrl(thumb),
                        full:   encUrl(real),
                        source: "reddit",
                        kind:   kind,
                        path:   real,
                        mtime:  mtime,
                        videoUrl: kind === "vid" ? encUrl(real) : "",
                    }
                })
                // Placed by age; focused card held by path so arrivals never move the view.
                const keep = root.filtered[root.activeIndex]?.path
                if (redditScanProc.append) {
                    // Incremental pass: only genuinely new files, merged in.
                    const seen = {}
                    root.wallpapers.forEach(w => seen[w.path] = true)
                    const fresh = parsed.filter(w => !seen[w.path])
                    if (fresh.length > 0) {
                        root.wallpapers = root.olderAtStart
                            ? root.wallpapers.concat(fresh).sort(root._byAge)
                            : root.wallpapers.concat(fresh)
                        root._focusPath(keep)
                    }
                } else {
                    root._instantMove = true
                    Qt.callLater(() => root._instantMove = false)
                    root.wallpapers = root.olderAtStart ? parsed.slice().sort(root._byAge) : parsed
                    if (root._restorePath.length > 0) {
                        // First scan after opening: the wallpaper focused last time.
                        root._focusPath(root._restorePath)
                        root._restorePath = ""
                    } else if (keep) {
                        // Same list, bigger page: stay on the card.
                        root._focusPath(keep)
                    }
                    // Otherwise stay at 0, the newest.
                }
                // Stamp slightly in the past: missing a file is worse than re-listing one.
                root.lastScanTime = Date.now() / 1000 - 5
                root.loading = false
                // If the previous sync didn't grow wallpapers, advance the per-sub sort cursor.
                if (redditSyncProc._checkSortAdvanceAfterScan) {
                    redditSyncProc._checkSortAdvanceAfterScan = false
                    const sub = redditSyncProc._targetSub
                    const counterKey = redditSyncProc._counterKey || ""
                    // Sort exhausted when AFTER="" or the disk count didn't grow.
                    const afterEmpty = counterKey && (root.redditAfterBySub[counterKey] || "") === ""
                    const noGrowth  = sub && root.wallpapers.length <= redditSyncProc._preCount
                    if (sub && (afterEmpty || noGrowth)) {
                        const cur = (root.redditSortBySub[sub] || 0)
                        if (cur + 1 < root.redditSorts.length) {
                            const m = Object.assign({}, root.redditSortBySub)
                            m[sub] = cur + 1
                            root.redditSortBySub = m
                            // Eagerly fire the next page on the new sort.
                            if (!redditSyncProc.busy) root.syncReddit()
                        }
                    }
                }
            }
        }
    }
    // Re-syncs the Reddit cache via gallery-dl; always re-scans disk after.
    Process {
        id: redditSyncProc
        property bool busy: false
        // Sub + wallpaper count before the sync, to detect a "dry" page and advance the sort order.
        property string _targetSub: ""
        property string _counterKey: ""
        property int _preCount: 0
        property int _sortIdx: 0
        property bool _checkSortAdvanceAfterScan: false
        // The fetcher exits 5 with "run reddit_oauth_setup.sh" on stderr when OAuth isn't set up.
        stderr: SplitParser {
            onRead: line => {
                if (line.indexOf("run reddit_oauth_setup.sh") !== -1
                    && !root._redditAuthWarned) {
                    root._redditAuthWarned = true
                    notifyAuthSetupProc.command = ["bash", "-c",
                        "notify-send -a 'skwd' -u normal "
                        + "'Reddit fetcher needs setup' "
                        + "'Run: ~/.config/quickshell/ii/scripts/colors/reddit_oauth_setup.sh' "
                        + "-i applications-internet"]
                    notifyAuthSetupProc.running = true
                }
            }
        }
        // First stdout line is "AFTER=<token>"; empty means the sort is exhausted.
        stdout: SplitParser {
            onRead: line => {
                if (!line.startsWith("AFTER=")) return
                const token = line.substring(6)
                const m = Object.assign({}, root.redditAfterBySub)
                m[redditSyncProc._counterKey] = token
                root.redditAfterBySub = m
            }
        }
        onRunningChanged: if (!running) {
            redditSyncProc.busy = false
            redditSyncProc._checkSortAdvanceAfterScan = true
            root.runScan(false)
        }
    }
    // Per-sub page counter; advances each syncReddit() call so scrolling to the end pulls fresh posts.
    property var redditPageBySub: ({})
    // Per-sub sort-cycle index; advances once a sort dries up (~1000 items per sort × 10 sorts).
    property var redditSortBySub: ({})
    // Defined in WallpaperHub so the launcher and fetcher share one listing.
    readonly property var redditSorts: WallpaperHub.redditSorts
    property string redditLastSub: ""

    // Reddit's opaque `after` token, persisted per (sub, sort) independently.
    property var redditAfterBySub: ({})
    // One-shot guard: "setup required" notification fires once per session.
    property bool _redditAuthWarned: false
    Process { id: notifyAuthSetupProc }

    // ── Only fetch subs the user actually meant ──────────────────────
    // A sub counts as real only once chosen or typed in full — not on every keystroke.
    property bool querySubConfirmed: false
    function queryIsRealSub() { return root.querySubConfirmed }
    // ── Focused-item metadata ─────────────────────────────────────────
    // dims/format/bytes read off the file (local & reddit-cached only); keyed by id.
    property var metaByItemId: ({})     // id → { dims, format, bytes }
    function metaFor(item) { return item ? (metaByItemId[item.id] ?? null) : null }
    function _fetchMetaFor(item) {
        if (!item || !item.id) return
        if (metaByItemId[item.id] !== undefined) return
        const p = item.path || ""
        if (!p.startsWith("/")) return          // remote — can't inspect cheaply
        metaProc.itemId = item.id
        const safe = p.replace(/'/g, "'\\''")
        metaProc.command = ["bash", "-c",
            `f='${safe}'; [ -f "$f" ] || exit 0; ` +
            `if r=$("$HOME/.local/bin/tinct" image probe "$f" 2>/dev/null); then IFS=$'\\t' read -r w h m s <<< "$r"; echo "\${w}x\${h}|$m|$s"; ` +
            `else d=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$f" 2>/dev/null | head -1); ` +
            `echo "$d|\${f##*.}|$(stat -c%s "$f")"; fi`]
        metaProc.running = true
    }
    Process {
        id: metaProc
        property string itemId: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|")
                if (parts.length < 3) return
                const next = Object.assign({}, root.metaByItemId)
                next[metaProc.itemId] = {
                    dims: parts[0] || "",
                    format: (parts[1] || "").toUpperCase(),
                    bytes: parseInt(parts[2] || "0", 10)
                }
                root.metaByItemId = next
            }
        }
    }

    function syncReddit() {
        // Strip "r/", "/r/", "https://reddit.com/r/", quotes, trailing slashes, whitespace.
        let sub = (root.query || "")
            .trim()
            .replace(/^https?:\/\/(www\.|old\.)?reddit\.com\//i, "")
            .replace(/^\/+/, "")
            .replace(/^r\//i, "")
            .replace(/\/.*$/, "")
            .replace(/[^A-Za-z0-9_+]/g, "")
        if (sub === "") sub = "wallpapers"

        // Sort: forced override (filter panel) wins, else the auto-advancing cursor.
        let sortIdx = (root.redditSortBySub[sub] || 0) % root.redditSorts.length
        if (root.redditForcedSort) {
            const forcedIdx = root.redditSorts.findIndex(s => (s.path + s.q) === root.redditForcedSort)
            if (forcedIdx >= 0) sortIdx = forcedIdx
        }
        const sortDef = root.redditSorts[sortIdx]
        const counterKey = sub + "|" + sortIdx

        // `after` cursor for this (sub, sort). Empty string = first page.
        const afterToken = root.redditAfterBySub[counterKey] || ""

        root.redditLastSub = sub
        redditSyncProc.busy = true
        redditSyncProc._targetSub = sub
        redditSyncProc._sortIdx   = sortIdx
        redditSyncProc._counterKey = counterKey
        redditSyncProc._preCount  = root.wallpapers.length
        liveRescanTimer.restart()

        // Fetcher uses OAuth, limit=100/page, walks via the after cursor.
        // Lives next to switchwall.sh; run reddit_oauth_setup.sh once first.
        const scriptDir = `${root.home}/.config/quickshell/ii/scripts/colors`
        redditSyncProc.command = ["bash", "-c",
            `export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:/usr/bin:$PATH"
             mkdir -p "$HOME/Pictures/Wallpapers/skwd"
             # 100, not 30. fetch_reddit.sh budgets 20s per image and 90s per
             # video internally, so a 30s outer cap guaranteed every video was
             # killed mid-download and truncated any image batch that ran long --
             # fewer wallpapers per page than the 100 actually requested. The
             # script cannot hang past its own per-file caps, so this is a
             # backstop, not the real limit. The carousel still fills live: a
             # rescan every 800ms lists files as they land, not at exit.
             timeout 100 '${scriptDir}/fetch_reddit.sh' '${sub}' '${sortDef.path}${sortDef.q}' '${afterToken}' "$HOME/Pictures/Wallpapers/skwd" 2>>"$HOME/.cache/quickshell/skwd-reddit-sync.log"
             exit 0`]
        redditSyncProc.running = true
    }
    // Reset pagination on a new subreddit; also debounce-saves the typed query.
    onQueryChanged: {
        skwdSaveDebounce.restart()
        // Re-arms the gate; paths that know the sub is real (navigate, restore) set it back right after.
        root.querySubConfirmed = false
        if (root.activeSource !== "reddit") return
        const cleaned = (root.query || "")
            .trim().replace(/^r\//i, "").toLowerCase()
        if (cleaned !== (root.redditLastSub || "").toLowerCase()) {
            // Wipe all sort-variant counters for this sub so the next sync starts fresh at /hot page 1.
            const map = Object.assign({}, root.redditPageBySub)
            for (let k of Object.keys(map)) {
                if (k === cleaned || k.startsWith(cleaned + "|")) delete map[k]
            }
            root.redditPageBySub = map
            // Also reset the sort-cycle index — back to /hot.
            const sm = Object.assign({}, root.redditSortBySub)
            delete sm[cleaned]
            root.redditSortBySub = sm
        }
        if (cleaned.length >= 2) redditSearchKick.restart()
    }
    Timer {
        id: redditSearchKick
        interval: 450      // wait for the user to stop typing
        repeat: false
        onTriggered: {
            if (root.activeSource !== "reddit") return
            if (redditSyncProc.busy) return
            // Half-typed prefixes are not subreddits — don't fetch them.
            if (!root.queryIsRealSub()) return
            root.syncReddit()
        }
    }
    // Rescans on-disk reddit dirs every 800ms during a sync so the carousel populates as files land.
    Timer {
        id: liveRescanTimer
        interval: 800
        repeat: true
        running: false
        onTriggered: {
            if (!redditSyncProc.busy) {
                running = false
                return
            }
            // Incremental: cheap, and doesn't move anything already on screen.
            if (!redditScanProc.running) root.runScan(true)
        }
    }


    // "local" and favourites have no page 2, so load-more is never offered there.
    readonly property bool canLoadMore: root.activeSource === "wallhaven"
        || root.activeSource === "reddit"
        || root.activeSource === "videos"

    // Routes "load more" to whichever backend is active.
    function loadMoreForSource() {
        if (root.activeSource === "wallhaven") root.loadMoreWallhaven()
        else if (root.activeSource === "reddit" || root.activeSource === "videos") root.loadMoreReddit()
    }

    function loadMoreReddit() {
        // Videos tab shares Reddit's fetcher/cache; filtered() selects kind=="vid".
        if (root.activeSource !== "reddit" && root.activeSource !== "videos")
            return
        if (redditSyncProc.busy) return
        root.syncReddit()
    }

    // Opening, a source change and a restore can all ask in the same turn.
    property bool _refreshQueued: false
    function queueRefresh() {
        if (root._refreshQueued) return
        root._refreshQueued = true
        Qt.callLater(() => { root._refreshQueued = false; root.refresh() })
    }
    Connections {
        target: Quarry
        function onConnectedChanged() {
            if (Quarry.connected && root.quarryServes && root.wallpapers.length === 0) root.queueRefresh()
        }
    }

    function refresh() {
        root._sparseTries = 0
        root.loading = true
        root.wallpapers = []
        root.activeIndex = 0
        // New query/source → back to the first page of the disk scan.
        root.scanLimit = root.scanPageSize
        root.lastScanTime = 0
        root._vidChainTries = 0
        root.whPage = 1
        root.whHasMore = true
        root.whLoadingMore = false
        if (root.quarryServes) {
            root._fetchQuarry(query.trim(), 1, false)
        } else if (activeSource === "local") {
            localScanProc.running = true
        } else if (activeSource === "reddit" || activeSource === "videos") {
            // Reads the gallery-dl cache; Sync button triggers a fresh fetch separately.
            root.runScan(false)
        }
    }

    // ── Persistence (skwd panel state, restored on lazy reopen) ───────
    // Restored *before* the first refresh() so the right tab gets fetched.
    Timer { id: skwdSaveDebounce; interval: 250; repeat: false; onTriggered: root._savePersistedState() }

    property string _restorePath: ""
    property bool _instantMove: false
    function _focusPath(path) {
        if (!path) return
        const i = root.filtered.findIndex(w => w.path === path)
        if (i >= 0 && i !== root.activeIndex) root.activeIndex = i
    }

    readonly property bool carouselRtl: false

    // Timeline sources: newest left, older right; mtime = post upload date.
    readonly property bool olderAtStart: root.activeSource === "reddit" || root.activeSource === "videos"

    function _byAge(a, b) { return (b.mtime ?? 0) - (a.mtime ?? 0) }
    function _savePersistedState() {
        const s = Persistent.states.skwd
        if (!s) return
        s.activeSource    = root.activeSource
        s.activeMediaType = root.activeMediaType
        s.query           = root.query
        s.activeIndex     = root.activeIndex
        s.activePath      = root.filtered[root.activeIndex]?.path ?? ""
        // Forced sort is deliberate, kept across sessions. filterOpen isn't (panel always starts closed).
        s.forcedSort      = WallpaperHub.forcedSort
        s.redditPageMap = JSON.stringify(root.redditPageBySub || {})
    }
    function _restorePersistedState() {
        const s = Persistent.states.skwd
        if (!s) return
        if (s.activeSource    && s.activeSource.length    > 0) WallpaperHub.source  = s.activeSource
        if (s.activeMediaType && s.activeMediaType.length > 0) WallpaperHub.mediaType = s.activeMediaType
        if (s.query           !== undefined)                 { root.query = s.query
                                                               // Restored from a real session → fetchable.
                                                               root.querySubConfirmed = true }
        if (s.activeIndex     >= 0)                            root.activeIndex     = s.activeIndex
        if (s.activePath      !== undefined)                   root._restorePath    = s.activePath
        if (s.forcedSort      !== undefined)                   WallpaperHub.forcedSort = s.forcedSort
        try {
            const m = JSON.parse(s.redditPageMap || "{}")
            if (m && typeof m === "object") root.redditPageBySub = m
        } catch (e) { }
    }

    // ── Cache hygiene ────────────────────────────────────────────────
    // Removes empty sub dirs, then reports what's cached so stale page/sort counters can be dropped.
    Process {
        id: cachePruneProc
        command: ["bash", "-c",
            `d="$HOME/Pictures/Wallpapers/skwd/reddit"
             [ -d "$d" ] || exit 0
             find "$d" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null
             ls -1 "$d" 2>/dev/null`]
        stdout: StdioCollector {
            onStreamFinished: {
                const live = {}
                text.trim().split("\n").filter(l => l.length > 0)
                    .forEach(n => live[n.toLowerCase()] = true)
                if (Object.keys(live).length === 0) return
                // Keys are either "<sub>" or "<sub>|<sortIdx>".
                const keep = k => live[String(k).split("|")[0].toLowerCase()] === true
                const prune = m => {
                    const out = {}
                    for (const k of Object.keys(m || {})) if (keep(k)) out[k] = m[k]
                    return out
                }
                const before = Object.keys(root.redditPageBySub || {}).length
                root.redditPageBySub  = prune(root.redditPageBySub)
                root.redditSortBySub  = prune(root.redditSortBySub)
                root.redditAfterBySub = prune(root.redditAfterBySub)
                const after = Object.keys(root.redditPageBySub || {}).length
                if (after !== before) {
                    console.log("[skwd] pruned", before - after, "stale page-map entries")
                    skwdSaveDebounce.restart()
                }
            }
        }
    }
    // Qt.callLater: refreshing straight away clears wallpapers mid-evaluation of
    // filtered's own binding, which Qt reports as a binding loop.
    onActiveSourceChanged:    { skwdSaveDebounce.restart(); root.queueRefresh() }
    onActiveMediaTypeChanged: skwdSaveDebounce.restart()
    Component.onCompleted: {
        _restorePersistedState()
        root.queueRefresh()
        // Pruning only matters now and then.
        const s = Persistent.states.skwd
        if (s && Date.now() - (s.lastPrune ?? 0) > 86400000) {
            s.lastPrune = Date.now()
            cachePruneProc.running = true
        }
        if (!Quarry.connected) {
            Quickshell.execDetached(["systemctl", "--user", "start", "quarryd"])
            Quarry.poke()
        }
    }
    Component.onDestruction: _savePersistedState()

    // Single clamped way to move the selection — wheel, drag, keys, launcher all go through here.
    // ── Wheel → step the carousel ────────────────────────────────────
    property real _wheelAccum: 0
    property int _wheelBurst: 0
    property real _lastWheelMs: 0
    readonly property real wheelStepUnits: 120
    readonly property int maxWheelStride: 12
    // Finger travel per wallpaper on a touchpad, tuned against the 120-unit notch below.
    readonly property real wheelPixelsPerStep: 100
    // A gesture idle this long is over; its leftover fraction doesn't carry into the next one.
    readonly property int wheelIdleMs: 400
    // Opt-in delta logging; see the console.log in wheelScroll below.
    readonly property bool _wheelDebug: Quickshell.env("SKWD_WHEEL_DEBUG") === "1"

    // axis = orientation of the handler that delivered this event, so a diagonal swipe isn't double-counted.
    // Signature of the last event consumed, to drop duplicate deliveries.
    property string _lastWheelSig: ""

    function wheelScroll(event, axis) {
        event.accepted = true
        const now = Date.now()

        // Both handlers receive the event (event.accepted doesn't stop ancestor
        // handlers), so dedupe by delta signature, cleared next event-loop tick.
        const sig = axis + ":" + event.angleDelta.x + "," + event.angleDelta.y
                  + ":" + event.pixelDelta.x + "," + event.pixelDelta.y
        if (sig === root._lastWheelSig)
            return
        root._lastWheelSig = sig
        Qt.callLater(() => root._lastWheelSig = "")

        if (now - root._lastWheelMs > root.wheelIdleMs)
            root._wheelAccum = 0

        const vertical = (axis === undefined) || (axis === Qt.Vertical)
        const px  = vertical ? event.pixelDelta.y : event.pixelDelta.x
        const ang = vertical ? event.angleDelta.y : event.angleDelta.x

        // Normalise both axes to fractions of one wallpaper and take the larger —
        // pixelDelta/angleDelta are each unreliable in different ways per compositor.
        const fromAngle = ang / root.wheelStepUnits
        const fromPixel = px / root.wheelPixelsPerStep
        const steps = Math.abs(fromPixel) > Math.abs(fromAngle) ? fromPixel : fromAngle

        // SKWD_WHEEL_DEBUG=1 qs -c ii prints raw deltas instead of guessing.
        if (root._wheelDebug)
            console.log("[skwd wheel]", (axis === Qt.Horizontal ? "h" : "v"),
                        "angle=" + ang, "pixel=" + px,
                        "steps=" + steps.toFixed(3),
                        "accum=" + (root._wheelAccum + steps).toFixed(3))

        if (steps === 0)
            return
        // Captured before the clock is advanced, or every notch would look 0ms apart.
        const sinceLast = now - root._lastWheelMs
        root._lastWheelMs = now

        // Click wheels send whole ±120 notches and accelerate; touchpads must not.
        const notched = px === 0 && Math.abs(ang) >= 120
        let stride = 1
        if (notched) {
            root._wheelBurst = (sinceLast < 180)
                ? Math.min(root._wheelBurst + 1, 24) : 0
            stride = Math.min(root.maxWheelStride, 1 + Math.floor(root._wheelBurst / 3))
        } else {
            root._wheelBurst = 0
        }
        // Accumulator counts whole wallpapers (1.0 = one), not raw wheel units.
        root._wheelAccum += steps
        while (Math.abs(root._wheelAccum) >= 1) {
            const back = root._wheelAccum > 0
            root._wheelAccum += back ? -1 : 1
            const visualFlip = (root.carouselRtl && !vertical) ? -1 : 1
            root.stepActive((back ? -stride : stride) * visualFlip)
        }
    }

    function setActive(i) {
        if (root.filtered.length === 0) return
        root.activeIndex = Math.max(0, Math.min(i, root.filtered.length - 1))
    }
    function stepActive(delta) {
        root.setActive(root.activeIndex + delta)
    }

    // Forces a Reddit listing sort ("" = auto-cycle); called from skwd's chips and the launcher.
    function applySort(id) {
        WallpaperHub.forcedSort = id
        skwdSaveDebounce.restart()
        // Reset this sub's counters so the next sync uses the newly chosen sort.
        if (id !== "") {
            const sub = (root.query || "wallpapers").trim().replace(/^r\//i, "").toLowerCase()
            const sm = Object.assign({}, root.redditSortBySub)
            delete sm[sub]
            root.redditSortBySub = sm
        }
        if (!redditSyncProc.busy) root.syncReddit()
    }

    Connections {
        target: WallpaperHub
        function onNavigate(sub) {
            WallpaperHub.source = "reddit"
            root.query = sub
            // Picked in the launcher's dropdown → a real sub, safe to fetch.
            root.querySubConfirmed = true
        }
        function onSearch(text) {
            if (root.activeSource === "reddit" || root.query === text) return
            root.query = text
            root.queueRefresh()
        }
        function onCarouselStep(delta) {
            // Keys are visual: Left moves left.
            root.stepActive(root.carouselRtl ? -delta : delta)
        }
        function onReload() { root.refresh() }
        function onSortPicked(id) { root.applySort(id) }
        function onApplyFocused() {
            if (root.activeIndex >= 0 && root.activeIndex < root.filtered.length)
                root.applyWallpaper(root.filtered[root.activeIndex])
        }
    }

    // ── Auto-pagination ───────────────────────────────────────────────
    // Prefetches the next page once the user scrolls past ~80% of the loaded list.
    // Near enough the end to prefetch the next page.
    function _nearLoadEdge() {
        const n = root.filtered.length
        if (n === 0) return false
        const fromLoadEnd = n - 1 - root.activeIndex
        const fromStart   = (n - 1) - fromLoadEnd
        return fromStart / n >= loadMoreThreshold || fromLoadEnd < prefetchHeadroom
    }

    onActiveIndexChanged: {
        skwdSaveDebounce.restart()
        const n = root.filtered.length
        if (n === 0) return
        if (!root._nearLoadEdge()) return
        if (activeSource === "wallhaven") loadMoreWallhaven()
        else if (activeSource === "reddit" || activeSource === "videos") {
            // Check the disk-scan cap first — a sub with 800 cached files shouldn't stop at 400.
            if (root.wallpapers.length >= root.scanLimit) {
                // One page at a time; don't fire a fresh disk scan on every scroll step.
                if (redditScanProc.running) return
                root.scanLimit += root.scanPageSize
                root.runScan(false)
                return
            }
            loadMoreReddit()
        }
    }
    // Tracks previous filtered length: activeIndex doesn't move when a loadMore's items arrive.
    property int _lastFilteredLen: 0
    property int _sparseTries: 0

    // ── Keeping the chain alive on the Videos tab ─────────────────────
    // filtered is video-only there, and a page of 100 posts often has NO video,
    // so filtered never changes. Pump on the unfiltered list too, bounded.
    property int _vidChainTries: 0
    readonly property int maxVidChainTries: 15
    onWallpapersChanged: {
        if (root.activeSource !== "videos") return
        if (root.filtered.length >= 24) { root._vidChainTries = 0; return }
        if (root._vidChainTries >= root.maxVidChainTries) return
        root._vidChainTries++
        root.loadMoreReddit()
    }

    onFilteredChanged: {
        const n = root.filtered.length
        const grew = n > _lastFilteredLen
        _lastFilteredLen = n
        // Barely anything on screen: pull more, but give up on a sub that stays small.
        if (n > 0 && n < 24) {
            if (grew) root._sparseTries = 0
            if (activeSource === "wallhaven") loadMoreWallhaven()
            else if ((activeSource === "reddit" || activeSource === "videos") && root._sparseTries++ < 5) loadMoreReddit()
            return
        }
        // Infinite scroll: near the end and the last fetch grew the list.
        if (grew && n > 0 && root._nearLoadEdge()) {
            if (activeSource === "wallhaven") loadMoreWallhaven()
            else if (activeSource === "reddit" || activeSource === "videos") loadMoreReddit()
        }
    }

    // ── Apply ─────────────────────────────────────────────────────────
    // After apply finishes, close skwd and open the adjuster.
    Process {
        id: applyProc
        onRunningChanged: if (!running) {
            GlobalStates.skwdWallOpen = false
            GlobalStates.requestAdjusterOpen()
        }
    }
    // Right-click menu for a carousel tile.
    // One monitor only: no retheme, and a video wallpaper stops on that output.
    function applyToMonitor(item, monitor) {
        if (!item || !item.path || item.kind === "vid") return
        const local = item.path.startsWith("/")
        const target = local ? item.path : root.wallpaperCachePath(item)
        const stopVideo = `for p in $(pgrep -x mpvpaper); do tr '\\0' ' ' < /proc/$p/cmdline | grep -q ' ${monitor} ' && kill $p; done; true`
        monitorApplyProc.monitor = monitor
        monitorApplyProc.path = target
        monitorApplyProc.command = ["bash", "-c",
            (local ? "" : FileUtils.fetchToFileCommand(item.path, target) + " && ") + stopVideo]
        monitorApplyProc.running = true
    }
    Process {
        id: monitorApplyProc
        property string monitor: ""
        property string path: ""
        onExited: code => {
            if (code !== 0) return
            let map = {}
            try { map = JSON.parse(Config.options.background.monitorWallpapers || "{}") } catch (e) {}
            map[monitorApplyProc.monitor] = monitorApplyProc.path
            Config.options.background.monitorWallpapers = JSON.stringify(map)
        }
    }

    function menuForCarouselItem(md) {
        const local = md.path && md.path.startsWith("/")
        const arr = [
            { icon: "wallpaper", label: "Apply wallpaper",
              onTriggered: () => root.applyWallpaper(md) },
            { icon: "crop", label: "Apply & adjust crop…",
              onTriggered: () => root.applyAndAdjust(md) },
        ]
        // Images only: a video needs mpvpaper on every output it plays on.
        if (Quickshell.screens.length > 1 && md.kind !== "vid") {
            arr[0].label = "Apply to all monitors"
            for (const s of Quickshell.screens) {
                const name = s.name
                arr.push({ icon: "monitor", label: `Apply to ${name} only`,
                           onTriggered: () => root.applyToMonitor(md, name) })
            }
        }
        if (local) {
            arr.push({ separator: true })
            arr.push({ icon: WallpaperHub.isFavorite(md.path) ? "favorite" : "favorite_border",
                       label: WallpaperHub.isFavorite(md.path) ? "Remove from favourites" : "Add to favourites",
                       onTriggered: () => WallpaperHub.toggleFavorite(md.path) })
            // KIO's standalone properties dialog — same as Dolphin, without launching it.
            arr.push({ icon: "info", label: "Properties…",
                       onTriggered: () => Quickshell.execDetached(["kioclient", "openProperties", md.path]) })
            arr.push({ icon: "content_copy", label: "Copy path",
                       onTriggered: () => Quickshell.execDetached(["wl-copy", "--", md.path]) })
            arr.push({ icon: "folder",       label: "Show in files",
                       onTriggered: () => Quickshell.execDetached(["xdg-open", md.path.substring(0, md.path.lastIndexOf("/")) || "/"]) })
        } else {
            // Remote results (not on disk yet): view full image, reach the source page, or save without applying.
            arr.push({ separator: true })
            arr.push({ icon: "open_in_full", label: "View full size",
                       onTriggered: () => Qt.openUrlExternally(md.full || md.path) })
            const page = root.sourcePageUrl(md)
            if (page.length > 0) {
                arr.push({ icon: "link",
                           label: md.source === "wallhaven" ? "View on Wallhaven"
                                                            : `View r/${md.subreddit ?? ""}`,
                           onTriggered: () => Qt.openUrlExternally(page) })
            }
            arr.push({ icon: "download", label: "Save to Wallpapers",
                       onTriggered: () => root.saveWallpaperCopy(md) })
            arr.push({ icon: "content_copy", label: "Copy image link",
                       onTriggered: () => Quickshell.execDetached(["wl-copy", "--", md.full || md.path]) })
        }
        return arr
    }

    // Wallhaven exposes a per-image page keyed by id; reddit items only carry the subreddit.
    function sourcePageUrl(md) {
        if (!md) return ""
        if (md.source === "wallhaven" && md.id) return "https://wallhaven.cc/w/" + md.id
        if (md.source === "reddit" && md.subreddit) return "https://reddit.com/r/" + md.subreddit
        return ""
    }

    // Where a remote item lands once fetched; shared by both "apply" and "save".
    function wallpaperCachePath(item) {
        const targetDir = `${root.home}/Pictures/Wallpapers/skwd`
        let ext = (item.path.match(/\.([a-z0-9]+)(?:\?|$)/i) || [, "jpg"])[1].toLowerCase()
        if (item.kind === "vid" && ext !== "webm" && ext !== "gif") ext = "mp4"
        return `${targetDir}/${item.source}_${item.id}.${ext}`
    }

    // Keep a copy without applying it.
    function saveWallpaperCopy(md) {
        if (!md || !md.path) return
        const target = root.wallpaperCachePath(md)
        Quickshell.execDetached(["bash", "-c",
            FileUtils.fetchToFileCommand(md.path, target, { timeout: 60 })
            + ` && notify-send -a 'skwd' 'Saved to Wallpapers' ${FileUtils.shQuote(target)}`
            + ` || notify-send -a 'skwd' -u critical 'Save failed' ${FileUtils.shQuote(target)}`])
    }

    function applyAndAdjust(item) {
        applyWallpaper(item)
        GlobalStates.requestAdjusterOpen()
    }
    PopupContextMenu { id: skwdCtxMenu }

    function applyWallpaper(item) {
        if (!item) return
        // Any item whose path is already a local filesystem path applies directly, no download step.
        const isLocalPath = item.path && item.path.startsWith("/")
        if (item.source === "local" || isLocalPath) {
            applyProc.command = ["bash", "-c",
                `${Directories.wallpaperSwitchScriptPath} --image '${item.path.replace(/'/g, "'\\''")}'`]
        } else {
            const target = root.wallpaperCachePath(item)
            applyProc.command = ["bash", "-c",
                FileUtils.fetchToFileCommand(item.path, target)
                + ` && ${Directories.wallpaperSwitchScriptPath} --image ${FileUtils.shQuote(target)}`]
        }
        applyProc.running = true
    }

    function openWallTune() {
        GlobalStates.skwdWallOpen = false
        Qt.callLater(() => GlobalStates.wallTuneOpen = true)
    }

    // ── Layout ────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent

        // Wheel anywhere over skwd steps the carousel; dedupe in wheelScroll() prevents double-stepping.
        WheelHandler {
            orientation: Qt.Vertical
            acceptedDevices: PointerDevice.AllDevices
            onWheel: event => root.wheelScroll(event, Qt.Vertical)
        }
        WheelHandler {
            orientation: Qt.Horizontal
            acceptedDevices: PointerDevice.AllDevices
            onWheel: event => root.wheelScroll(event, Qt.Horizontal)
        }


        // ── Carousel (parallelogram) ──────────────────────────────────
        // ClippingRectangle, not Item: plain `clip` only clips to a bounding RECT.
        ClippingRectangle {
            id: carouselArea
            color: "transparent"
            radius: Appearance.rounding.large
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 76
            width: Math.min(parent.width - 80, 1400)
            // Exactly the card height, so the cards fill this box with no dead space.
            height: 258
            visible: root.viewLayout === "carousel"

            // Slide-down entrance, matching the detail row below (same curve, shorter travel).
            property real slideY: -34
            opacity: 0
            transform: Translate { y: carouselArea.slideY }
            Component.onCompleted: carouselEntrance.start()
            ParallelAnimation {
                id: carouselEntrance
                NumberAnimation {
                    target: carouselArea; property: "slideY"
                    from: -34; to: 0; duration: 420; easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: carouselArea; property: "opacity"
                    from: 0; to: 1; duration: 280; easing.type: Easing.OutCubic
                }
            }

            // Left-edge pull-to-refresh/load. Sibling overlay, not ListView's header (would shift originX).
            Item {
                id: startEdge
                readonly property bool fetching: root.olderAtStart && carousel.loadingMore
                    && (carousel.contentX - carousel.originX) < 60
                readonly property real restX: 8
                z: 10
                anchors { top: parent.top; bottom: parent.bottom }
                width: 104
                // The indicator's left edge trails the content's left edge.
                x: startEdge.fetching ? startEdge.restX
                    : Math.min(startEdge.restX, carousel.pullBackPx - startEdge.width)
                // Tracks the finger exactly while dragging; springs once let go.
                Behavior on x {
                    enabled: !carousel.dragging
                    SpringAnimation { spring: 3.2; damping: 0.26; epsilon: 0.5 }
                }
                opacity: startEdge.fetching ? 1 : Math.min(1, carousel.pullBackPx / 36)
                visible: startEdge.x > -startEdge.width + 1

                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialSymbol {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: startEdge.fetching ? "progress_activity"
                            : !root.olderAtStart ? "refresh"
                            : (carousel.refreshProgress >= 1 ? "download" : "refresh")
                        iconSize: 26
                        color: carousel.refreshProgress >= 1 || startEdge.fetching
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colSubtext
                        Behavior on color { ColorAnimation { duration: 160 } }
                        rotation: startEdge.fetching ? 0 : -carousel.refreshProgress * 270
                        // Small pop at the threshold.
                        scale: startEdge.fetching ? 1
                            : 0.7 + Math.min(1, carousel.refreshProgress) * 0.35
                              + (carousel.refreshProgress >= 1 ? 0.08 : 0)
                        Behavior on scale {
                            SpringAnimation { spring: 4; damping: 0.3 }
                        }
                        RotationAnimator on rotation {
                            running: startEdge.fetching
                            loops: Animation.Infinite
                            from: 0; to: 360; duration: 900
                        }
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 96
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: startEdge.fetching ? qsTr("Loading…")
                            : root.olderAtStart
                                ? (carousel.refreshProgress >= 1 ? qsTr("Release to load")
                                                                 : qsTr("Pull to load"))
                                : (carousel.refreshProgress >= 1 ? qsTr("Release to refresh")
                                                                 : qsTr("Pull to refresh"))
                    }
                }
            }

            ListView {
                id: carousel
                anchors.fill: parent
                orientation: ListView.Horizontal
                layoutDirection: root.carouselRtl ? Qt.RightToLeft : Qt.LeftToRight
                // ScriptModel diffs by stable id, so appending pages
                // doesn't reset the carousel — currentIndex stays put.
                model: ScriptModel {
                    values: root.filtered
                    objectProp: "id"
                }
                spacing: 8
                clip: true
                cacheBuffer: 400  // keeps ~1 card off-screen each side
                // Half-width of the active card's slot, matching the delegate's own geometry.
                readonly property real _activeHalf: (440 + 0.18 * height + 12) / 2
                preferredHighlightBegin: width / 2 - _activeHalf
                preferredHighlightEnd:   width / 2 + _activeHalf
                highlightRangeMode: ListView.StrictlyEnforceRange
                highlightFollowsCurrentItem: true
                snapMode: ListView.SnapOneItem
                keyNavigationWraps: false

                // ── Pull-past-the-end to load more ───────────────────────
                // Normalises the drag against a threshold, fires at >= 1.
                // Fixed width: a resizing footer would feed back into overscrollPx.
                footer: Item {
                    // Only where another page can arrive; timeline sources load from the left edge.
                    visible: root.canLoadMore && !root.olderAtStart && root.filtered.length > 0
                    width: visible ? 104 : 0
                    height: carousel.height

                    Column {
                        anchors.centerIn: parent
                        spacing: 8
                        id: footerCol
                        readonly property bool showLoading: carousel.loadingMore && !root.olderAtStart
                        opacity: showLoading ? 1
                            : Math.max(0.35, carousel.pullProgress)
                        Behavior on opacity { NumberAnimation { duration: 160 } }

                        MaterialSymbol {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: parent.showLoading ? "progress_activity"
                                : root.olderAtStart ? "refresh"
                                : (carousel.pullProgress >= 1 ? "download" : "chevron_right")
                            iconSize: 26
                            color: carousel.pullProgress >= 1 || parent.showLoading
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colSubtext
                            Behavior on color { ColorAnimation { duration: 160 } }
                            // Past the threshold the arrow has become the download glyph; stop rotating.
                            rotation: carousel.pullProgress >= 1 ? 0
                                : carousel.pullProgress * 90
                            scale: 1 + carousel.pullProgress * 0.25
                            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                            RotationAnimator on rotation {
                                running: footerCol.showLoading
                                loops: Animation.Infinite
                                from: 0; to: 360; duration: 900
                            }
                        }
                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 96
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: parent.showLoading ? qsTr("Loading…")
                                : root.olderAtStart
                                    ? (carousel.pullProgress >= 1 ? qsTr("Release to refresh")
                                                                  : qsTr("Pull to refresh"))
                                    : (carousel.pullProgress >= 1 ? qsTr("Release to load")
                                                                  : qsTr("Pull for more"))
                        }
                    }
                }

                readonly property real pullThreshold: 90
                // Overshoot past the end of the list.
                readonly property real overscrollPx:
                    Math.max(0, root.carouselRtl ? -horizontalOvershoot : horizontalOvershoot)
                readonly property real pullProgress:
                    Math.min(1, overscrollPx / pullThreshold)
                // Same gesture at the start: pulling back is a refresh (works on every source, including local).
                readonly property real pullBackPx:
                    Math.max(0, root.carouselRtl ? horizontalOvershoot : -horizontalOvershoot)
                readonly property real refreshProgress:
                    Math.min(1, pullBackPx / pullThreshold)
                readonly property bool loadingMore:
                    root.loading || root.whLoadingMore || redditSyncProc.running
                // Latched so one drag fires once, not on every bounce oscillation.
                property bool _pullFired: false
                onDraggingChanged: {
                    if (dragging) { _pullFired = false; return }
                    if (_pullFired || loadingMore) return
                    if (pullProgress >= 1 && !root.olderAtStart) {
                        _pullFired = true
                        root.loadMoreForSource()
                    } else if (refreshProgress >= 1) {
                        _pullFired = true
                        if (root.olderAtStart) root.loadMoreForSource()
                        else root.refresh()
                    }
                }
                // Fixed short slide, not fixed pixel speed, so a big jump doesn't crawl.
                highlightMoveVelocity: -1
                // Instant after a scan: animating across hundreds of cards builds a delegate for each.
                highlightMoveDuration: root._instantMove ? 0 : 130
                // Guards against ListView's snap-back: on model growth it briefly
                // resets currentIndex to 0, which would otherwise write back to root.activeIndex.
                property bool _syncingFromRoot: false
                Component.onCompleted: currentIndex = root.activeIndex
                onCurrentIndexChanged: {
                    // Must not skip focusSettle below, or wheel/keyboard steps move the
                    // carousel without updating the info/palette panels.
                    if (!_syncingFromRoot
                            && currentIndex !== root.activeIndex
                            && currentIndex >= 0)
                        root.activeIndex = currentIndex
                    // Kick off palette extraction + metadata for items without a Wallhaven palette.
                    if (currentIndex >= 0 && currentIndex < root.filtered.length) {
                        focusSettle.restart()
                    }
                }
                Connections {
                    target: root
                    function onActiveIndexChanged() {
                        if (carousel.currentIndex === root.activeIndex) return
                        carousel._syncingFromRoot = true
                        carousel.currentIndex = root.activeIndex
                        carousel._syncingFromRoot = false
                    }
                }
                // Restores currentIndex after an append (it briefly drops to 0 during the reflow).
                onCountChanged: {
                    if (currentIndex !== root.activeIndex
                            && root.activeIndex < count) {
                        _syncingFromRoot = true
                        currentIndex = root.activeIndex
                        _syncingFromRoot = false
                    }
                }
                // DragOverBounds, not StopAtBounds: a flick still stops cleanly at the end.
                boundsBehavior: Flickable.DragOverBounds
                // Phone-style inertial flick: low deceleration for a long, fading glide.
                flickDeceleration: 800
                maximumFlickVelocity: 6000

                // ── Wheel → step the carousel ─────────────────────────
                // Two handlers, one per axis (WheelHandler only looks at one).
                WheelHandler {
                    target: null
                    orientation: Qt.Vertical
                    acceptedDevices: PointerDevice.AllDevices
                    onWheel: event => root.wheelScroll(event, Qt.Vertical)
                }
                WheelHandler {
                    target: null
                    orientation: Qt.Horizontal
                    acceptedDevices: PointerDevice.AllDevices
                    onWheel: event => root.wheelScroll(event, Qt.Horizontal)
                }
                // Middle-click and drag to pan through the wallpapers.
                DragHandler {
                    id: panDrag
                    target: null
                    acceptedButtons: Qt.MiddleButton
                    cursorShape: Qt.ClosedHandCursor
                    property int startIndex: 0
                    // One wallpaper per ~90px dragged (either axis).
                    readonly property real pxPerItem: 90
                    onActiveChanged: {
                        // root, not carousel: _wheelAccum lives on root.
                        if (active) startIndex = root.activeIndex
                        else root._wheelAccum = 0
                    }
                    onTranslationChanged: {
                        if (!active) return
                        const moved = translation.x + translation.y
                        const target = startIndex - Math.round(moved / pxPerItem)
                        root.setActive(target)
                    }
                }

                delegate: Item {
                    required property var modelData
                    required property int index
                    readonly property bool active: index === carousel.currentIndex
                    // Slot must reserve the space content occupies, or the active card overflows its neighbours.
                    readonly property real frameHeight: carousel.height
                    readonly property real skewPad: 0.18 * frameHeight
                    width: (active ? 440 : 110) + skewPad + 12
                    height: carousel.height
                    z: active ? 10 : 1
                    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                    Item {
                        anchors.centerIn: parent
                        readonly property bool active: parent.active
                        width: active ? 440 : 110
                        height: parent.frameHeight
                        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                        // Parallelogram via skew — image fills the frame and skews with it
                        Rectangle {
                            anchors.fill: parent
                            transform: Matrix4x4 {
                                matrix: Qt.matrix4x4(1, -0.18, 0, 0,
                                                     0,  1,    0, 0,
                                                     0,  0,    1, 0,
                                                     0,  0,    0, 1)
                            }
                            radius: parent.active ? 20 : 6
                            color: Appearance.colors.colLayer1Base
                            clip: true
                            border.width: parent.active ? 3 : 1
                            border.color: parent.active
                                ? Appearance.m3colors.m3primary
                                : Qt.alpha("white", 0.15)
                            Behavior on radius       { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            Behavior on border.width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 180 } }

                            Image {
                                id: carouselImg
                                anchors.fill: parent
                                anchors.margins: parent.border.width
                                property var modelDataRef: parent.parent.parent.modelData
                                property int retries: 0
                                source: modelDataRef.thumb
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                // Thumbs are small (≤1280px), so caching avoids a full re-decode on rescroll.
                                cache: true
                                smooth: true
                                // Larger than grid tiles, but capped below 4K.
                                sourceSize.width: 760
                                // Hide until fully decoded to avoid a partial-JPEG rainbow flash.
                                opacity: status === Image.Ready ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                onStatusChanged: {
                                    if (status !== Image.Error) return
                                    if (retries === 0 && modelDataRef.full
                                            && modelDataRef.full !== source) {
                                        retries = 1
                                        source = modelDataRef.full
                                    }
                                }
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: carouselImg.width
                                        height: carouselImg.height
                                        radius: Math.max(0, carouselImg.parent.radius - carouselImg.parent.border.width)
                                    }
                                }
                            }

                            // Auto-play the focused video; Loader unloads to release the decoder.
                            Loader {
                                id: videoFocusLoader
                                anchors.fill: parent
                                anchors.margins: parent.border.width
                                readonly property var _md: parent.parent.parent.modelData
                                readonly property int _idx: parent.parent.parent.index
                                readonly property bool _active: _md
                                    && _md.kind === "vid"
                                    && _idx === carousel.currentIndex
                                    && (_md.videoUrl || "").length > 0
                                active: _active
                                visible: active
                                asynchronous: true
                                sourceComponent: Item {
                                    MediaPlayer {
                                        id: videoPlayer
                                        source: videoFocusLoader._md.videoUrl
                                        loops: MediaPlayer.Infinite
                                        audioOutput: AudioOutput { muted: true; volume: 0 }
                                        videoOutput: vidOut
                                        Component.onCompleted: play()
                                        // A rescan can swap the source under this player; setSource() resets
                                        // to Stopped and onCompleted won't refire, so re-issue play() on ready.
                                        onMediaStatusChanged: {
                                            if ((mediaStatus === MediaPlayer.LoadedMedia
                                                 || mediaStatus === MediaPlayer.BufferedMedia)
                                                && playbackState !== MediaPlayer.PlayingState)
                                                play()
                                        }
                                        onErrorOccurred: (err, msg) => console.warn("skwd video:", err, msg)
                                    }
                                    VideoOutput {
                                        id: vidOut
                                        anchors.fill: parent
                                        fillMode: VideoOutput.PreserveAspectCrop
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width: vidOut.width
                                                height: vidOut.height
                                                radius: Math.max(0, carouselImg.parent.radius - carouselImg.parent.border.width)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Favourite toggle, top-right of the focused card.
                        Rectangle {
                            id: favBtn
                            visible: index === carousel.currentIndex
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 6
                            width: 26; height: 26; radius: 13
                            readonly property bool on: WallpaperHub.isFavorite(modelData?.path ?? "")
                            color: Qt.alpha("black", favHov.hovered ? 0.75 : 0.5)
                            HoverHandler { margin: Appearance.sizes.touchSlop; id: favHov }
                            TapHandler {
                                margin: Appearance.sizes.touchSlop
                                onTapped: WallpaperHub.toggleFavorite(modelData?.path ?? "")
                            }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: favBtn.on ? "favorite" : "favorite_border"
                                iconSize: 15
                                color: favBtn.on ? Appearance.m3colors.m3error : "white"
                            }
                        }

                        // PIC badge bottom-right
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.margins: 4
                            implicitWidth: badgeText.implicitWidth + 10
                            implicitHeight: 14
                            radius: 3
                            color: Qt.alpha("black", 0.7)
                            StyledText {
                                id: badgeText
                                anchors.centerIn: parent
                                text: (modelData.kind ?? "pic").toUpperCase()
                                font.pixelSize: 8
                                font.weight: Font.Bold
                                color: "white"
                            }
                        }

                        // Play glyph overlay — marks animated wallpapers.
                        Rectangle {
                            anchors.centerIn: parent
                            visible: (modelData?.kind ?? "pic") === "vid"
                            width: 34; height: 34; radius: 17
                            color: Qt.alpha("black", 0.55)
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "play_arrow"
                                iconSize: 22
                                fill: 1
                                color: "white"
                            }
                        }

                        TapHandler {
                            onTapped: {
                                if (parent.active) root.applyWallpaper(parent.parent.modelData)
                                else carousel.currentIndex = parent.parent.index
                            }
                        }
                        // Middle-click → apply this one straight away without focusing it first.
                        TapHandler {
                            acceptedButtons: Qt.MiddleButton
                            onTapped: {
                                const md = parent.parent.modelData
                                if (!md) return
                                carousel.currentIndex = parent.parent.index
                                root.applyWallpaper(md)
                            }
                        }
                        // Right-click → context menu (apply / adjust / copy).
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: (eventPoint) => {
                                const md = parent.parent.modelData
                                if (!md) return
                                carousel.currentIndex = parent.parent.index
                                const g = parent.mapToItem(root, eventPoint.position.x, eventPoint.position.y)
                                skwdCtxMenu.popup(g.x, g.y, root.menuForCarouselItem(md))
                            }
                        }
                    }

                    // ── Palette strip under the focused item ────────────
                    // Click a swatch to add it to the colour filter and re-search.
                    Row {
                        anchors.top: parent.verticalCenter
                        anchors.topMargin: carousel.height * 0.42
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 4
                        visible: index === carousel.currentIndex
                              && root.paletteFor(modelData).length > 0
                        opacity: index === carousel.currentIndex ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Repeater {
                            model: root.paletteFor(modelData)
                            delegate: Rectangle {
                                required property var modelData
                                width: 14; height: 14; radius: 7
                                color: Qt.color(modelData)
                                border.width: 1
                                border.color: Qt.alpha("black", 0.25)
                                HoverHandler { margin: Appearance.sizes.touchSlop; id: palHov }
                                scale: palHov.hovered ? 1.18 : 1
                                Behavior on scale { NumberAnimation { duration: 140 } }
                                TapHandler {
                                    margin: Appearance.sizes.touchSlop
                                    onTapped: {
                                        const want = String(modelData).replace("#", "").toLowerCase()
                                        // Push the raw hex; Wallhaven rounds it to the nearest palette entry.
                                        root.toggleColor(want)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Grid ──────────────────────────────────────────────────────
        Item {
            id: gridArea
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 30
            width: Math.min(parent.width - 80, 1400)
            height: Math.min(parent.height * 0.7, 520)
            visible: root.viewLayout === "grid"

            GridView {
                id: gridView
                anchors.fill: parent
                clip: true
                cellWidth: width / 6
                cellHeight: 110
                model: ScriptModel {
                    values: root.filtered
                    objectProp: "id"
                }
                cacheBuffer: cellHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    width: 6
                    contentItem: Rectangle {
                        radius: 3
                        color: Appearance.colors.colOutline
                        opacity: 0.5
                    }
                }

                delegate: Item {
                    required property var modelData
                    width: GridView.view.cellWidth
                    height: GridView.view.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: 4
                        color: Appearance.colors.colLayer1Base
                        clip: true
                        border.width: gridCardHov.hovered ? 2 : 0
                        border.color: Appearance.m3colors.m3primary
                        Behavior on border.width { NumberAnimation { duration: 100 } }

                        HoverHandler { id: gridCardHov }
                        TapHandler { onTapped: root.applyWallpaper(modelData) }

                        Image {
                            id: gridImg
                            anchors.fill: parent
                            anchors.margins: 1
                            // Wallhaven CDN occasionally 404s a thumb; fall back to the full image URL.
                            property int retries: 0
                            source: modelData.thumb
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            smooth: true
                            // Decode at tile size: Reddit's thumb is the same 4K JPEG as full.
                            sourceSize.width: 480
                            // Invisible until decoded, to avoid partial-JPEG rainbow flashes.
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            onStatusChanged: {
                                if (status !== Image.Error) return
                                if (retries === 0 && modelData.full
                                        && modelData.full !== source) {
                                    retries = 1
                                    source = modelData.full
                                }
                            }
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: gridImg.width
                                    height: gridImg.height
                                    radius: 3
                                }
                            }
                        }
                        // Pulsing loading dot while the tile decodes; auto-hides on Ready or Error.
                        Rectangle {
                            id: gridLoadingDot
                            anchors.centerIn: parent
                            width: 10; height: 10; radius: 5
                            visible: gridImg.status === Image.Loading
                            color: Appearance.m3colors.m3primary
                            opacity: 0.55
                            SequentialAnimation on scale {
                                // An animation's parent is null; reference gridLoadingDot directly.
                                running: gridLoadingDot.visible
                                loops: Animation.Infinite
                                NumberAnimation { from: 0.6; to: 1.2; duration: 700; easing.type: Easing.InOutQuad }
                                NumberAnimation { from: 1.2; to: 0.6; duration: 700; easing.type: Easing.InOutQuad }
                            }
                        }
                        // Error indicator (only when both thumb and full URL fail).
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: 3
                            visible: gridImg.status === Image.Error && gridImg.retries >= 1
                            color: Qt.alpha(Appearance.m3colors.m3error, 0.18)
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "broken_image"
                                iconSize: 18
                                color: Appearance.m3colors.m3error
                            }
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.margins: 4
                            implicitWidth: gridBadge.implicitWidth + 10
                            implicitHeight: 14
                            radius: 3
                            color: Qt.alpha("black", 0.7)
                            StyledText {
                                id: gridBadge
                                anchors.centerIn: parent
                                text: (modelData.kind ?? "pic").toUpperCase()
                                font.pixelSize: 8
                                font.weight: Font.Bold
                                color: "white"
                            }
                        }
                    }
                }
            }
        }

        // Empty state — Reddit gets a "Fetch r/<typed>" CTA, or "Fetching…" while syncing.
        ColumnLayout {
            id: emptyState
            anchors.centerIn: parent
            spacing: 8
            visible: !root.loading && root.filtered.length === 0

            readonly property bool isReddit: root.activeSource === "reddit"
            readonly property string typedSub: {
                if (!isReddit) return ""
                return (root.query || "")
                    .trim()
                    .replace(/^r\//i, "")
                    .replace(/\/.*$/, "")
                    .replace(/[^A-Za-z0-9_+]/g, "")
            }
            readonly property bool busy: redditSyncProc.busy
            readonly property bool offline: root.quarryServes && !Quarry.connected
            // Items exist, the launcher's filters hide them all.
            readonly property bool filteredOut: root.wallpapers.length > 0

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: emptyState.offline ? "cloud_off"
                    : emptyState.filteredOut ? (root.favoritesOnly ? "heart_broken" : "filter_alt_off")
                    : emptyState.busy
                    ? "sync"
                    : (emptyState.isReddit && emptyState.typedSub.length > 0
                        ? "cloud_download"
                        : "image_not_supported")
                iconSize: 36
                color: Appearance.colors.colSubtext
                RotationAnimation on rotation {
                    running: emptyState.busy
                    loops: Animation.Infinite
                    from: 0; to: 360; duration: 1100
                }
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: emptyState.offline ? qsTr("Starting quarry…")
                    : emptyState.filteredOut ? (root.favoritesOnly ? qsTr("No favourites here yet") : qsTr("Nothing matches these filters"))
                    : emptyState.busy
                    ? qsTr("Fetching r/%1…").arg(emptyState.typedSub || "wallpapers")
                    : (emptyState.isReddit && emptyState.typedSub.length > 0
                        ? qsTr("Nothing cached for r/%1").arg(emptyState.typedSub)
                        : qsTr("No wallpapers"))
                color: Appearance.colors.colSubtext
            }
            // CTA: click-to-sync when there's a query and we're idle.
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                visible: emptyState.isReddit && emptyState.typedSub.length > 0 && !emptyState.busy
                    && !emptyState.offline && !emptyState.filteredOut
                implicitHeight: 28
                implicitWidth: ctaRow.implicitWidth + 22
                radius: 14
                color: ctaHov.hovered
                    ? Appearance.colors.colPrimary
                    : Qt.alpha(Appearance.colors.colPrimary, 0.18)
                border.width: 1
                border.color: Qt.alpha(Appearance.colors.colPrimary, 0.4)
                Behavior on color { ColorAnimation { duration: 160 } }
                HoverHandler { id: ctaHov }
                TapHandler { onTapped: root.syncReddit() }
                Row {
                    id: ctaRow
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "download"
                        iconSize: 14
                        color: ctaHov.hovered
                            ? Appearance.m3colors.m3onPrimary
                            : Appearance.colors.colPrimary
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Fetch r/%1").arg(emptyState.typedSub)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: ctaHov.hovered
                            ? Appearance.m3colors.m3onPrimary
                            : Appearance.colors.colPrimary
                    }
                }
            }
        }

        // Publishes the focused item; the launcher's details dropdown draws it.
        Item {
            id: detailRow
            readonly property var md: (root.activeIndex >= 0 && root.activeIndex < root.filtered.length)
                ? root.filtered[root.activeIndex] : null
            readonly property var meta: root.metaFor(md)
            onMdChanged: {
                if (md) focusSettle.restart()
                WallpaperHub.focusedItem = md
                WallpaperHub.focusedTheme = md ? (root.themeByItemId[root._themeKey(md)] ?? null) : null
            }
            onMetaChanged: WallpaperHub.focusedMeta = meta
        }
    }
}
