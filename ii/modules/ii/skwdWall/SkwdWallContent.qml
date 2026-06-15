pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtMultimedia
import Quickshell
import Quickshell.Io
import Qt5Compat.GraphicalEffects

Item {
    id: root
    signal close()

    readonly property string home: "/home/caesar"
    property string activeSource: "local"          // local | wallhaven | reddit | videos
    // Default subreddit(s) for the Videos tab — multireddit syntax
    // (a+b+c). Both verified live and carrying playable v.redd.it
    // videos with poster previews.
    readonly property string videoSubs: "LivelyWallpaper+wallpaperengine"
    property string activeMediaType: "all"         // all | pic | vid | we
    property string viewLayout: "carousel"         // carousel | grid | hex
    property int activeIndex: 0
    property string query: ""
    property string activeHue: ""                  // "" | "red" | "orange" | ...
    property bool favoritesOnly: false
    property var wallpapers: []
    property bool loading: false

    // ── Wallhaven filters ─────────────────────────────────────────────
    // Tri-state binary strings.  100 = G only / SFW only, 111 = all, etc.
    property string whCategories: "111"   // General / Anime / People
    property string whPurity:     "100"   // SFW / Sketchy / NSFW
    property string whSorting:    "toplist" // relevance|date_added|favorites|toplist|views|random
    property string whTopRange:   "1M"    // 1d 3d 1w 1M 3M 6M 1y
    property string whRatio:      ""      // 16x9 | 16x10 | 21x9 | 9x16 | …
    property string whAtleast:    ""      // 1920x1080 | 2560x1440 | 3840x2160 | …
    property bool   whFilterOpen: false
    // Reddit filter panel — manual override for the auto-advanced sort
    // cycle. "" = let the auto-cycle pick (hot → top?t=all → … → new).
    property bool   redditFilterOpen: false
    property string redditForcedSort: ""   // "" = auto; else sort path key e.g. "top?t=all"

    readonly property var whSortings: [
        { id: "toplist",    label: "TOP"   },
        { id: "relevance",  label: "REL"   },
        { id: "date_added", label: "NEW"   },
        { id: "favorites",  label: "FAV"   },
        { id: "views",      label: "VIEW"  },
        { id: "random",     label: "RAND"  },
    ]
    readonly property var whTopRanges: [ "1d", "3d", "1w", "1M", "3M", "6M", "1y" ]
    readonly property var whRatios:    [ "",  "16x9", "16x10", "21x9", "9x16", "1x1" ]
    readonly property var whAtleasts:  [
        { id: "",         label: "any" },
        { id: "1920x1080", label: "FHD"  },
        { id: "2560x1440", label: "QHD"  },
        { id: "3840x2160", label: "4K"   },
    ]

    // Wallhaven API key — required for sketchy/NSFW results.  Read from
    // ~/.secure/apikeys (WALLHAVEN_API_KEY), the one place all keys live.
    readonly property string whApiKey: ApiKeys.get("WALLHAVEN_API_KEY")

    function _buildWallhavenUrl(q, page) {
        const parts = []
        if (q) parts.push("q=" + encodeURIComponent(q))
        parts.push("categories=" + whCategories)
        parts.push("purity=" + whPurity)
        parts.push("sorting=" + whSorting)
        if (whSorting === "toplist") parts.push("topRange=" + whTopRange)
        if (whRatio !== "")   parts.push("ratios="   + whRatio)
        if (whAtleast !== "") parts.push("atleast="  + whAtleast)
        if (whColors !== "")  parts.push("colors="   + whColors)
        if (whApiKey !== "")  parts.push("apikey="   + encodeURIComponent(whApiKey))
        if (page && page > 1) parts.push("page=" + page)
        return "https://wallhaven.cc/api/v1/search?" + parts.join("&")
    }

    // ── Pagination state for the active source ────────────────────────
    property int  whPage:        1
    property bool whHasMore:     true
    property bool whLoadingMore: false
    // How close (ratio of list length) we have to be to the end before
    // auto-fetching the next page.
    // Trigger a pre-fetch as soon as the carousel is past 50 % of the
    // loaded set — gallery-dl takes 5-10 s to complete a sync, so firing
    // earlier means new posts are already on disk by the time the user
    // reaches the end. Combined with redditDrySubs, repeated pre-fetches
    // are still cheap because a dry sub aborts immediately.
    // Fire the next page when activeIndex / filtered.length crosses this.
    // 0.35 with OAuth's <1 s pages = the user never sees the end of
    // the loaded list under any reasonable scroll speed. Was 0.5 with
    // slower gallery-dl batches.
    readonly property real loadMoreThreshold: 0.35
    // Always prefetch when this many items (or fewer) remain ahead.
    // Combined with the ratio threshold above, this keeps the chain
    // alive on long lists: after a prefetch lands, ratio drops below
    // 0.35 but n - activeIndex stays small, so the next page still
    // fires.
    readonly property int prefetchHeadroom: 20

    // Hue palette — 13 buckets. `swatch` is what we draw in the UI;
    // `wh` is the Wallhaven API color code (https://wallhaven.cc/help/api
    // — `colors` parameter only accepts their fixed 27-colour palette).
    readonly property var hues: [
        { id: "red",    swatch: "#e34d4d", wh: "cc0000" },
        { id: "orange", swatch: "#e58a3d", wh: "cc9933" },
        { id: "amber",  swatch: "#e6b840", wh: "996633" },
        { id: "yellow", swatch: "#e9d635", wh: "cccc33" },
        { id: "lime",   swatch: "#9bd64b", wh: "77cc33" },
        { id: "green",  swatch: "#3fc06d", wh: "336600" },
        { id: "teal",   swatch: "#3fc0a8", wh: "66cccc" },
        { id: "cyan",   swatch: "#3fb8c7", wh: "0099cc" },
        { id: "blue",   swatch: "#4d84e0", wh: "0066cc" },
        { id: "indigo", swatch: "#6a55d6", wh: "333399" },
        { id: "purple", swatch: "#9a4de0", wh: "663399" },
        { id: "pink",   swatch: "#e34da8", wh: "ea4c88" },
        { id: "mono",   swatch: "#9aa0a6", wh: "999999" },
    ]
    // ── Client-side palette extraction (for Reddit + local items) ─────
    // Wallhaven sends a 5-color palette in its API response. For other
    // sources we run `magick … -colors 5 txt:-` against the thumbnail and
    // cache the result here, keyed by item id. The carousel reads either
    // the API-provided `.palette` OR this fallback.
    property var palettesByItemId: ({})

    function paletteFor(item) {
        if (!item) return []
        if (Array.isArray(item.palette) && item.palette.length > 0) return item.palette
        return palettesByItemId[item.id] ?? []
    }

    // Pick which image we hand to magick — prefer a thumb if any.
    function _palImageFor(item) {
        if (!item) return ""
        return item.thumb || item.full || item.path || ""
    }

    function _ensurePaletteFor(item) {
        if (!item || !item.id) return
        if (palettesByItemId[item.id] !== undefined) return                   // already done
        if (Array.isArray(item.palette) && item.palette.length > 0) return    // wallhaven already gave us one
        const img = _palImageFor(item)
        if (!img) return
        // Local file or remote? magick can read both, but remote pulls down
        // the bytes — skip remote unless it's already in the freedesktop
        // thumbnail cache (which is the same path we use for previews).
        paletteExtractProc.itemId = item.id
        // Heredoc-safe escaping
        const safe = String(img).replace(/'/g, "'\\''")
        paletteExtractProc.command = ["bash", "-c",
            // Sample 80x80, quantise to 5 buckets, dump as "#hex" lines
            // sorted by frequency (most-common first). Limit runtime.
            `timeout 4 magick '${safe}' -resize 80x80\\! +dither -colors 5 -unique-colors txt:- 2>/dev/null \\
              | awk 'match($0,/#[0-9A-Fa-f]{6}/){print substr($0, RSTART, 7)}' \\
              | head -5`
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

    // Comma-separated list of Wallhaven hex codes (no `#`). Empty = no
    // colour filter. Multi-select.
    property string whColors: ""
    function toggleColor(wh) {
        const arr = whColors.length > 0 ? whColors.split(",") : []
        const idx = arr.indexOf(wh)
        if (idx >= 0) arr.splice(idx, 1)
        else arr.push(wh)
        whColors = arr.join(",")
        refresh()
    }

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
        // Videos tab pre-filters to video kind regardless of the ALL/PIC/VID
        // media-type chip selection.
        if (activeSource === "videos")
            list = list.filter(w => (w.kind ?? "pic") === "vid")
        if (activeMediaType !== "all")
            list = list.filter(w => (w.kind ?? "pic") === activeMediaType)
        // In the Reddit and Videos tabs the query input filters by FILENAME /
        // SUBREDDIT / TITLE (the cached files are local, so a live API query
        // is meaningless). For wallhaven / local, query is consumed by the
        // fetcher and shouldn't double-filter here.
        if (activeSource === "reddit" || activeSource === "videos") {
            let q = (root.query || "").trim().toLowerCase()
            q = q.replace(/^r\//, "")
            if (q.length > 0) {
                list = list.filter(w =>
                    (w.subreddit || "").toLowerCase().includes(q)
                 || (w.title     || "").toLowerCase().includes(q)
                 || (w.id        || "").toLowerCase().includes(q))
            }
        }
        return list
    }

    // ── Sources ───────────────────────────────────────────────────────
    Process {
        id: localScanProc
        // Scans both images AND videos. For each video, a poster frame
        // is extracted with ffmpeg into a cache (once) so the carousel
        // has something to display — the carousel's Image can't render
        // an mp4. Output lines: `kind|thumbpath|realpath`.
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
                        kind: kind,           // "pic" or "vid"
                        // `path` is the REAL file — switchwall.sh's
                        // is_video() detects the .mp4 and runs mpvpaper.
                        path: real,
                    }
                })
                root.loading = false
            }
        }
    }

    Process {
        id: wallhavenProc
        command: ["bash", "-c", "echo '{}'"]
        // Whether this fetch is page 1 (replace results) or a follow-up
        // page (append).  Set by refresh() / loadMoreWallhaven().
        property bool appendMode: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    const fresh = (data.data || []).map(w => ({
                        id: w.id,
                        title: w.id,
                        thumb: w.thumbs?.small ?? w.thumbs?.original ?? w.path,
                        full:  w.path,
                        source: "wallhaven",
                        kind: "pic",
                        path: w.path,
                        // 5-color dominant palette from the Wallhaven API.
                        // Used to render the colored glow + swatch strip
                        // around the focused carousel item.
                        palette: Array.isArray(w.colors) ? w.colors.slice(0, 5) : [],
                    }))
                    const meta = data.meta ?? {}
                    const lastPage = meta.last_page ?? 1
                    root.whHasMore = (root.whPage < lastPage) && fresh.length > 0
                    if (wallhavenProc.appendMode) {
                        // Dedupe by id to avoid showing the same image twice
                        // if the API returned overlap.
                        const seen = new Set(root.wallpapers.map(w => w.id))
                        const keepIdx = root.activeIndex
                        root.wallpapers = root.wallpapers.concat(
                            fresh.filter(w => !seen.has(w.id)))
                        // ListView resets currentIndex to 0 when the model
                        // array reference flips.  Restore the user's spot
                        // after the binding storm settles.
                        Qt.callLater(() => {
                            if (keepIdx >= 0 && keepIdx < root.filtered.length
                                    && root.activeIndex !== keepIdx)
                                root.activeIndex = keepIdx
                        })
                    } else {
                        root.wallpapers = fresh
                    }
                } catch (e) {
                    if (!wallhavenProc.appendMode) root.wallpapers = []
                    root.whHasMore = false
                }
                root.loading = false
                root.whLoadingMore = false
            }
        }
    }
    function loadMoreWallhaven() {
        if (root.activeSource !== "wallhaven") return
        if (root.loading || root.whLoadingMore || !root.whHasMore) return
        root.whLoadingMore = true
        root.whPage += 1
        const url = root._buildWallhavenUrl(root.query.trim(), root.whPage)
        wallhavenProc.appendMode = true
        wallhavenProc.command = ["bash", "-c", `curl -s --max-time 12 '${url}'`]
        wallhavenProc.running = true
    }

    // Reddit pagination cursor — last response's `after` token; "" when
    // exhausted. Only used by the Videos tab now; the Reddit tab proper
    // reads gallery-dl's local cache (see redditScanProc) because Reddit
    // 403s every unauthenticated JSON request as of 2024.
    property string redditAfter: ""
    property bool   redditHasMore: true
    property bool   redditLoadingMore: false

    // ── Reddit (cached via gallery-dl) ────────────────────────────────
    // Scans the gallery-dl download dir for previously-fetched Reddit
    // posts. Filenames look like "<id> <title> [WxH].ext"; the id is
    // the leading non-space token.
    Process {
        id: redditScanProc
        // Scan BOTH the new (under ~/Pictures/Wallpapers/skwd) and the
        // legacy (~/.config/gallery-dl) download roots, AND video files
        // alongside images. For each video, the first frame is extracted
        // once into ~/.cache/quickshell/skwd-posters/<md5>.jpg so the
        // carousel has something to paint until VideoOutput kicks in.
        // Output lines: `<kind>|<posterpath>|<realpath>`.
        command: ["bash", "-c",
            `postdir="$HOME/.cache/quickshell/skwd-posters"; mkdir -p "$postdir"; \\
             roots=(\\
                "$HOME/Pictures/Wallpapers/skwd/reddit" \\
                "$HOME/Pictures/Wallpapers/skwd/redgifs" \\
                "$HOME/.config/gallery-dl/reddit" \\
                "$HOME/.config/gallery-dl/redgifs"); \\
             exist=(); for r in "\${roots[@]}"; do [ -d "$r" ] && exist+=("$r"); done; \\
             [ \${#exist[@]} -eq 0 ] && exit 0; \\
             find "\${exist[@]}" -maxdepth 2 -type f \\
                \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \\
                   -o -iname '*.webp' -o -iname '*.gif' \\
                   -o -iname '*.mp4' -o -iname '*.webm' \\
                   -o -iname '*.m4v' -o -iname '*.mkv' -o -iname '*.mov' \\) \\
                -printf '%T@\\t%p\\n' 2>/dev/null \\
             | sort -rn | cut -f2- | head -200 \\
             | while IFS= read -r f; do \\
                 case "\${f,,}" in \\
                   *.mp4|*.webm|*.m4v|*.mkv|*.mov|*.gif) \\
                     h=$(printf '%s' "$f" | md5sum | cut -d' ' -f1); \\
                     p="$postdir/$h.jpg"; \\
                     [ -f "$p" ] || ffmpeg -nostdin -y -loglevel quiet \\
                         -i "$f" -vf 'scale=480:-2' -vframes 1 "$p" 2>/dev/null; \\
                     echo "vid|$p|$f" ;; \\
                   *) echo "pic|$f|$f" ;; \\
                 esac; \\
               done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l.length > 0)
                root.wallpapers = lines.map(line => {
                    const cols  = line.split("|")
                    const kind  = cols[0] || "pic"
                    const thumb = cols[1] || cols[2]
                    const real  = cols[2] || cols[1]
                    const parts = real.split("/")
                    const name  = parts[parts.length - 1]
                    // Subreddit = parent dir name (gallery-dl convention:
                    // .../reddit/<SUB>/<file>). Falls back to "" for legacy
                    // flat layouts.
                    const subreddit = parts[parts.length - 2] || ""
                    // Filename pattern: "<postid> <title…> [WxH].ext"
                    const idMatch = name.match(/^(\w+)\s+/)
                    const id = idMatch ? idMatch[1] : name
                    // file:// URLs must URL-encode spaces (%20), `#`, and other
                    // reserved chars or Qt's Image refuses with "Cannot open".
                    const encUrl = function(p) {
                        return "file://" + p.split("/").map(encodeURIComponent).join("/")
                    }
                    return {
                        id: id,
                        title: name.replace(/^\w+\s+/, "").replace(/\.[a-z0-9]+$/i, ""),
                        subreddit: subreddit,
                        thumb:  encUrl(thumb),
                        full:   encUrl(thumb),
                        source: "reddit",
                        kind:   kind,                 // "pic" or "vid"
                        path:   real,                 // raw real path → fast apply
                        videoUrl: kind === "vid" ? encUrl(real) : "",
                    }
                })
                root.loading = false
                // Now that wallpapers reflects the just-arrived files, check
                // whether the previous sync grew anything. If it didn't,
                // advance the per-sub sort cursor so the NEXT loadMore hits
                // /top?t=all (or the next sort), instead of replaying /hot.
                if (redditSyncProc._checkSortAdvanceAfterScan) {
                    redditSyncProc._checkSortAdvanceAfterScan = false
                    const sub = redditSyncProc._targetSub
                    const counterKey = redditSyncProc._counterKey || ""
                    // Two signals that the current sort is exhausted:
                    //   1. The fetcher returned AFTER="" (Reddit told us
                    //      there are no more pages in this listing)
                    //   2. The disk count didn't grow (we got the same
                    //      already-downloaded items again — happens at
                    //      lower sort caps before AFTER goes empty)
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
    // Re-syncs the Reddit cache via gallery-dl. Reddit currently 403s
    // unauthenticated requests so this *may* fail — but the moment Reddit
    // either eases up or OAuth gets configured in ~/.config/gallery-dl/
    // config.json, this button starts pulling new posts. After the run
    // we always re-scan whatever's on disk, so partial fetches still
    // surface.
    Process {
        id: redditSyncProc
        property bool busy: false
        // Sub the most recent sync was targeting + the wallpaper count BEFORE
        // it started. Used to detect a "dry" page: same wallpapers count
        // after the post-sync scan finishes → advance to next sort order.
        property string _targetSub: ""
        property string _counterKey: ""
        property int _preCount: 0
        property int _sortIdx: 0
        property bool _checkSortAdvanceAfterScan: false
        // Capture stderr for "setup required" notifications. The
        // fetcher writes "Missing $ENV_FILE — run reddit_oauth_setup.sh
        // first." to stderr and exits with code 5 when the OAuth env
        // hasn't been set up. Surface that as a notification once per
        // session so the user knows what to do instead of seeing
        // silent failure.
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
        // Parse the fetcher's stdout. First line is "AFTER=<token>"
        // (the cursor for the NEXT page in this sort) — we capture it
        // into redditAfterBySub. Empty token = sort exhausted; the
        // sort-advance check in redditScanProc will flip us to the
        // next sort on the next loadMore call.
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
            redditScanProc.running = true
        }
    }
    // (Dry-sub detection removed — gallery-dl re-downloading already
    // cached posts gave no growth, which permanently flagged the sub as
    // dry and blocked all future auto-loads. The user's actual end-of-
    // carousel "load more" is the more important behaviour.)
    // Per-subreddit page counter. Each syncReddit() call against a sub
    // advances the gallery-dl --range window further, so scrolling to the
    // end of the carousel really does pull in fresh posts (not just
    // re-verify the first page). Typing a different sub resets it.
    property var redditPageBySub: ({})
    // Per-sub sort-cycle index — once one sort dries up, advance to the
    // next. Each sort gets its own page counter and contributes up to
    // Reddit's per-sort cap (~1000 items). 10 sorts ≈ a few thousand
    // unique items per sub. After the cycle exhausts, the user has more
    // than they'll ever scroll through.
    property var redditSortBySub: ({})
    readonly property var redditSorts: [
        { path: "hot",          q: ""           },
        { path: "top",          q: "?t=all"     },
        { path: "top",          q: "?t=year"    },
        { path: "top",          q: "?t=month"   },
        { path: "top",          q: "?t=week"    },
        { path: "top",          q: "?t=day"     },
        { path: "new",          q: ""           },
        { path: "rising",       q: ""           },
        { path: "controversial",q: "?t=all"     },
        { path: "controversial",q: "?t=year"    },
    ]
    property string redditLastSub: ""

    // Per-(sub,sort) `after` cursors. Reddit's OAuth API returns an
    // opaque `after` token in each response; passing it on the next
    // request walks forward through the listing. We persist these per
    // (sub, sort) so each combo paginates independently — switching to
    // a different sort doesn't lose where we were in the previous one.
    property var redditAfterBySub: ({})
    // One-shot guard so the "setup required" notification only fires
    // once per session instead of on every retry while auth is missing.
    property bool _redditAuthWarned: false
    Process { id: notifyAuthSetupProc }

    function syncReddit() {
        // Robustify input: strip "r/", "/r/", "https://reddit.com/r/", quotes,
        // trailing slashes, surrounding whitespace.
        let sub = (root.query || "")
            .trim()
            .replace(/^https?:\/\/(www\.|old\.)?reddit\.com\//i, "")
            .replace(/^\/+/, "")
            .replace(/^r\//i, "")
            .replace(/\/.*$/, "")
            .replace(/[^A-Za-z0-9_+]/g, "")
        if (sub === "") sub = "wallpapers"

        // Sort selection: forced override (filter panel) wins, else
        // the auto-advancing cursor that flips to the next sort when
        // the current one runs dry.
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

        // The fetcher does ~all the heavy lifting:
        //   * Uses OAuth (oauth.reddit.com) — Reddit blocks unauth .json
        //     for browser-shaped UAs since 2024+. Token is cached for
        //     ~50 min, refreshed automatically from ~/.secure/reddit-app.env.
        //   * limit=100 per page (gallery-dl's --range 1-15 was the old
        //     bottleneck).
        //   * Walks via `after` cursor → effectively unlimited within a
        //     sort, then we cycle sort and reset the cursor.
        //   * Parallel downloads (xargs -P 8).
        //   * Stdout: first line "AFTER=<token>", then file paths.
        //
        // The script lives next to switchwall.sh; user runs
        // reddit_oauth_setup.sh once before first use.
        const scriptDir = `${root.home}/.config/quickshell/ii/scripts/colors`
        redditSyncProc.command = ["bash", "-c",
            `export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:/usr/bin:$PATH"
             mkdir -p "$HOME/Pictures/Wallpapers/skwd"
             timeout 30 '${scriptDir}/fetch_reddit.sh' '${sub}' '${sortDef.path}${sortDef.q}' '${afterToken}' "$HOME/Pictures/Wallpapers/skwd" 2>>"$HOME/.cache/quickshell/skwd-reddit-sync.log"
             exit 0`]
        redditSyncProc.running = true
    }
    // Reset pagination when the user types a different subreddit so the
    // next sync starts at page 1 again. Also schedules a save so the typed
    // query survives a close/reopen.
    onQueryChanged: {
        skwdSaveDebounce.restart()
        if (root.activeSource !== "reddit") return
        const cleaned = (root.query || "")
            .trim().replace(/^r\//i, "").toLowerCase()
        if (cleaned !== (root.redditLastSub || "").toLowerCase()) {
            // Wipe ALL sort-variant counters for this sub so the next sync
            // starts fresh at /hot page 1.
            const map = Object.assign({}, root.redditPageBySub)
            for (let k of Object.keys(map)) {
                if (k === cleaned || k.startsWith(cleaned + "|")) delete map[k]
            }
            root.redditPageBySub = map
            // Also reset the sort-cycle index — back to /hot.
            const sm = Object.assign({}, root.redditSortBySub)
            delete sm[cleaned]
            root.redditSortBySub = sm
            const dry = Object.assign({}, root.redditDrySubs)
            delete dry[cleaned]
            root.redditDrySubs = dry
        }
        // Auto-fire a sync for the typed sub once typing settles. Without
        // this, searching for an un-fetched sub shows an empty carousel
        // and end-of-list pagination never kicks in (it needs at least
        // one visible item before activeIndex / filtered.length crosses
        // the threshold).
        if (cleaned.length >= 2) redditSearchKick.restart()
    }
    Timer {
        id: redditSearchKick
        interval: 450      // wait for the user to stop typing
        repeat: false
        onTriggered: {
            if (root.activeSource !== "reddit") return
            if (redditSyncProc.busy) return
            root.syncReddit()
        }
    }
    // Rescan the on-disk reddit dirs every 800 ms while a sync is
    // running so the carousel populates as files land. Was 2.5 s for
    // the old gallery-dl path where 5-10 s per batch meant a slow tick
    // was fine; with OAuth + xargs -P 8 each file lands within the
    // first second of fetch_reddit.sh, so the tick has to be faster
    // or we miss the live-growth window entirely.
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
            if (!redditScanProc.running) redditScanProc.running = true
        }
    }
    Process {
        id: redditProc
        command: ["bash", "-c", "echo '{}'"]
        property bool appendMode: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    const ch = data.data?.children ?? []
                    // Videos tab keeps only video posts; Reddit tab keeps
                    // both (the pic/vid media-type chips filter further).
                    const videoOnly = (root.activeSource === "videos")
                    const fresh = ch
                        .map(c => root._classifyRedditPost(c.data))
                        .filter(w => w !== null && (!videoOnly || w.kind === "vid"))
                    root.redditAfter = data.data?.after ?? ""
                    // Use raw child count, not `fresh` — a page can yield
                    // zero videos yet still have more pages behind it.
                    root.redditHasMore = root.redditAfter !== "" && ch.length > 0
                    if (redditProc.appendMode) {
                        const seen = new Set(root.wallpapers.map(w => w.id))
                        const keepIdx = root.activeIndex
                        root.wallpapers = root.wallpapers.concat(
                            fresh.filter(w => !seen.has(w.id)))
                        Qt.callLater(() => {
                            if (keepIdx >= 0 && keepIdx < root.filtered.length
                                    && root.activeIndex !== keepIdx)
                                root.activeIndex = keepIdx
                        })
                    } else {
                        root.wallpapers = fresh
                    }
                } catch (e) {
                    if (!redditProc.appendMode) root.wallpapers = []
                    root.redditHasMore = false
                }
                root.loading = false
                root.redditLoadingMore = false
            }
        }
    }
    // Classify one reddit post into a wallpaper entry, or null if it
    // carries no usable image/video. Detects v.redd.it videos, gif/
    // gifv-as-video previews, and direct media links.
    function _classifyRedditPost(p) {
        if (!p || !p.id) return null
        const imgRe = /\.(jpg|jpeg|png|webp)(\?|$)/i
        const vidRe = /\.(mp4|webm|gif|gifv)(\?|$)/i
        let videoUrl = ""
        if (p.is_video && p.media && p.media.reddit_video)
            videoUrl = p.media.reddit_video.fallback_url || ""
        if (!videoUrl && p.preview && p.preview.reddit_video_preview)
            videoUrl = p.preview.reddit_video_preview.fallback_url || ""
        if (!videoUrl && vidRe.test(p.url || ""))
            videoUrl = (p.url || "").replace(/\.gifv(\?|$)/i, ".mp4$1")
        const isVid = videoUrl !== ""
        const prev = p.preview?.images?.[0]
        const thumb = (prev?.resolutions?.[2]?.url
                    ?? prev?.source?.url
                    ?? (isVid ? "" : (p.url ?? ""))).replace(/&amp;/g, "&")
        // Image posts need a real image; video posts need a poster.
        if (!isVid && !imgRe.test(p.url || "") && !prev?.source?.url)
            return null
        if (isVid && thumb === "") return null
        return {
            id: p.id,
            title: p.title,
            thumb: thumb,
            full: isVid ? videoUrl.replace(/&amp;/g, "&")
                        : (p.url ?? "").replace(/&amp;/g, "&"),
            source: "reddit",
            kind: isVid ? "vid" : "pic",
            path: isVid ? videoUrl.replace(/&amp;/g, "&") : (p.url ?? ""),
        }
    }

    // Builds the reddit hot.json URL. The Videos tab points at the
    // video-wallpaper subs; either tab honours a typed subreddit query.
    // Multireddit `+` joins must stay literal, so parts are encoded
    // individually.
    function _buildRedditUrl(after) {
        let sub = root.query.trim()
        if (sub === "")
            sub = (root.activeSource === "videos") ? root.videoSubs : "wallpapers"
        sub = sub.split("+")
            .map(s => encodeURIComponent(s.trim()))
            .filter(s => s.length > 0)
            .join("+")
        let u = `https://www.reddit.com/r/${sub}/hot.json?limit=80`
        if (after) u += `&after=${encodeURIComponent(after)}`
        return u
    }

    // Stub kept so other references don't break.
    property var redditDrySubs: ({})

    function loadMoreReddit() {
        // Each call advances the per-sub page counter inside syncReddit.
        if (root.activeSource === "reddit") {
            if (redditSyncProc.busy) return
            root.syncReddit()
            return
        }
        if (root.activeSource !== "videos") return
        if (root.loading || root.redditLoadingMore || !root.redditHasMore) return
        if (!root.redditAfter) return
        root.redditLoadingMore = true
        redditProc.appendMode = true
        redditProc.command = ["bash", "-c",
            `curl -s --max-time 12 -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36' '${root._buildRedditUrl(root.redditAfter)}'`]
        redditProc.running = true
    }

    function refresh() {
        root.loading = true
        root.wallpapers = []
        root.activeIndex = 0
        root.whPage = 1
        root.whHasMore = true
        root.whLoadingMore = false
        root.redditAfter = ""
        root.redditHasMore = true
        root.redditLoadingMore = false
        if (activeSource === "local") {
            localScanProc.running = true
        } else if (activeSource === "wallhaven") {
            const url = root._buildWallhavenUrl(query.trim(), 1)
            wallhavenProc.appendMode = false
            wallhavenProc.command = ["bash", "-c", `curl -s --max-time 12 '${url}'`]
            wallhavenProc.running = true
        } else if (activeSource === "reddit" || activeSource === "videos") {
            // Read the gallery-dl-populated cache instead of hitting Reddit's
            // 403'd JSON API. The Videos tab uses the same scan + a kind=="vid"
            // filter in `filtered`. The Sync button (UI) triggers a fresh fetch
            // when the user wants new posts.
            redditScanProc.running = true
        }
    }

    // ── Persistence (skwd panel state, restored on lazy reopen) ───────
    // Survives the Loader unloading SkwdWallContent between sessions. We
    // restore activeSource/activeMediaType/query/activeIndex *before* the
    // first refresh() runs so the right tab gets fetched, and we keep
    // saving via a debounce on each property change.
    Timer { id: skwdSaveDebounce; interval: 250; repeat: false; onTriggered: root._savePersistedState() }
    function _savePersistedState() {
        const s = Persistent.states.skwd
        if (!s) return
        s.activeSource    = root.activeSource
        s.activeMediaType = root.activeMediaType
        s.query           = root.query
        s.activeIndex     = root.activeIndex
        try {
            s.redditPageMap = JSON.stringify(root.redditPageBySub || {})
        } catch (e) { /* nothing */ }
    }
    function _restorePersistedState() {
        const s = Persistent.states.skwd
        if (!s) return
        if (s.activeSource    && s.activeSource.length    > 0) root.activeSource    = s.activeSource
        if (s.activeMediaType && s.activeMediaType.length > 0) root.activeMediaType = s.activeMediaType
        if (s.query           !== undefined)                   root.query           = s.query
        if (s.activeIndex     >= 0)                            root.activeIndex     = s.activeIndex
        try {
            const m = JSON.parse(s.redditPageMap || "{}")
            if (m && typeof m === "object") root.redditPageBySub = m
        } catch (e) { /* leave default */ }
    }
    onActiveSourceChanged:    { skwdSaveDebounce.restart(); refresh() }
    onActiveMediaTypeChanged: skwdSaveDebounce.restart()
    Component.onCompleted: {
        _restorePersistedState()
        refresh()
    }
    Component.onDestruction: _savePersistedState()

    // ── Auto-pagination ───────────────────────────────────────────────
    // When the user scrolls / arrows past 80 % of the loaded list,
    // pre-fetch the next wallhaven page so they don't hit a wall.
    // Also schedules a save (debounced) so the cursor position survives a
    // close/reopen.
    onActiveIndexChanged: {
        skwdSaveDebounce.restart()
        const n = root.filtered.length
        if (n === 0) return
        const ratioOk    = activeIndex / n >= loadMoreThreshold
        const headroomOk = (n - activeIndex) <= prefetchHeadroom
        if (!ratioOk && !headroomOk) return
        if (activeSource === "wallhaven") loadMoreWallhaven()
        else if (activeSource === "reddit" || activeSource === "videos") loadMoreReddit()
    }
    // Tracks the previous filtered length so onFilteredChanged can detect
    // "did we actually grow?". Used to chain-fire pagination on Reddit
    // even at high item counts — without this, reaching end-of-list once
    // fires loadMore, the new items arrive, but activeIndex doesn't move
    // so onActiveIndexChanged never re-fires and the chain dies.
    property int _lastFilteredLen: 0
    onFilteredChanged: {
        const n = root.filtered.length
        const grew = n > _lastFilteredLen
        _lastFilteredLen = n
        // Sparse-results case: barely anything on screen, eagerly pull more.
        if (n > 0 && n < 24) {
            if (activeSource === "wallhaven") loadMoreWallhaven()
            else if (activeSource === "reddit" || activeSource === "videos") loadMoreReddit()
            return
        }
        // Infinite-scroll case: user is sitting past the threshold OR
        // within prefetchHeadroom of the end, AND the last fetch DID
        // add items — keep going until the sub goes dry or they
        // navigate back. The headroom check is what keeps the chain
        // alive on long lists: after a prefetch lands, the ratio drops
        // below 0.35 but n - activeIndex stays small.
        const ratioOk    = activeIndex / n >= loadMoreThreshold
        const headroomOk = (n - activeIndex) <= prefetchHeadroom
        if (grew && n > 0 && (ratioOk || headroomOk)) {
            if (activeSource === "wallhaven") loadMoreWallhaven()
            else if (activeSource === "reddit" || activeSource === "videos") loadMoreReddit()
        }
    }

    // ── Apply ─────────────────────────────────────────────────────────
    // After the apply proc finishes, close skwd and open the adjuster so
    // the user can frame the new wallpaper exactly the way they want.
    Process {
        id: applyProc
        onRunningChanged: if (!running) {
            GlobalStates.skwdWallOpen = false
            GlobalStates.requestAdjusterOpen()
        }
    }
    // Right-click menu for a carousel tile.
    function menuForCarouselItem(md) {
        const local = md.path && md.path.startsWith("/")
        const arr = [
            { icon: "wallpaper", label: "Apply wallpaper",
              onTriggered: () => root.applyWallpaper(md) },
            { icon: "crop", label: "Apply & adjust crop…",
              onTriggered: () => root.applyAndAdjust(md) },
        ]
        if (local) {
            arr.push({ separator: true })
            arr.push({ icon: "content_copy", label: "Copy path",
                       onTriggered: () => Quickshell.execDetached(["wl-copy", "--", md.path]) })
            arr.push({ icon: "folder",       label: "Show in files",
                       onTriggered: () => Quickshell.execDetached(["xdg-open", md.path.substring(0, md.path.lastIndexOf("/")) || "/"]) })
        }
        return arr
    }
    function applyAndAdjust(item) {
        applyWallpaper(item)
        GlobalStates.requestAdjusterOpen()
    }
    PopupContextMenu { id: skwdCtxMenu }

    function applyWallpaper(item) {
        if (!item) return
        // Treat any item whose `path` is already a local filesystem path
        // (Reddit cache from gallery-dl, future local pre-downloads) as a
        // direct apply — no curl-download step.
        const isLocalPath = item.path && item.path.startsWith("/")
        if (item.source === "local" || isLocalPath) {
            applyProc.command = ["bash", "-c",
                `${Directories.wallpaperSwitchScriptPath} --image '${item.path.replace(/'/g, "'\\''")}'`]
        } else {
            const targetDir = `${root.home}/Pictures/Wallpapers/skwd`
            let ext = (item.path.match(/\.([a-z0-9]+)(?:\?|$)/i) || [,"jpg"])[1].toLowerCase()
            if (item.kind === "vid" && ext !== "webm" && ext !== "gif") {
                ext = "mp4"
            }
            const target = `${targetDir}/${item.source}_${item.id}.${ext}`
            applyProc.command = ["bash", "-c",
                `mkdir -p '${targetDir}' && \\
                 curl -sL --max-time 30 -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36' -o '${target}' '${item.path}' && \\
                 ${Directories.wallpaperSwitchScriptPath} --image '${target}'`]
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

        // Floating pill toolbar at top
        Rectangle {
            id: toolbar
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 14
            implicitHeight: 36
            implicitWidth: toolbarRow.implicitWidth + 16
            radius: height / 2
            color: Appearance.colors.colLayer1Base
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            z: 10
            // Smooth toolbar resizes when filter button appears/disappears
            // or content reflows.
            Behavior on implicitWidth {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            Behavior on implicitHeight {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            RowLayout {
                id: toolbarRow
                anchors.centerIn: parent
                spacing: 8

                // Source switcher (Local / Wallhaven / Reddit) — rendered as small icon pills
                Repeater {
                    model: root.sources
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: root.activeSource === modelData.id
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 26; implicitHeight: 26
                        radius: height / 2
                        color: active
                            ? Appearance.colors.colSecondaryContainer
                            : (srcHov.hovered ? Appearance.colors.colLayer2Base : "transparent")
                        Behavior on color { ColorAnimation { duration: 140 } }
                        HoverHandler { id: srcHov }
                        TapHandler { onTapped: root.activeSource = modelData.id }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: modelData.icon
                            iconSize: 14
                            color: parent.active
                                ? Appearance.m3colors.m3onSecondaryContainer
                                : Appearance.colors.colOnLayer1
                        }
                    }
                }

                Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 18; color: Appearance.colors.colLayer0Border }

                // Media-type tabs: ALL / PIC / VID / WE
                Repeater {
                    model: root.mediaTypes
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: root.activeMediaType === modelData.id
                        Layout.alignment: Qt.AlignVCenter
                        implicitHeight: 24
                        implicitWidth: typeLabel.implicitWidth + 14
                        radius: 4
                        color: active
                            ? Appearance.m3colors.m3primary
                            : (typeHov.hovered ? Appearance.colors.colLayer2Base : "transparent")
                        Behavior on color { ColorAnimation { duration: 140 } }
                        HoverHandler { id: typeHov }
                        TapHandler { onTapped: root.activeMediaType = modelData.id }
                        StyledText {
                            id: typeLabel
                            anchors.centerIn: parent
                            text: modelData.label
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            font.letterSpacing: 0.5
                            color: parent.active
                                ? Appearance.colors.colOnPrimary
                                : Appearance.colors.colOnLayer1
                        }
                    }
                }

                Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 18; color: Appearance.colors.colLayer0Border }

                // View switcher
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 26; implicitHeight: 26
                    radius: height / 2
                    color: viewHov.hovered ? Appearance.colors.colLayer2Base : "transparent"
                    Behavior on color { ColorAnimation { duration: 140 } }
                    HoverHandler { id: viewHov }
                    TapHandler {
                        onTapped: root.viewLayout =
                            root.viewLayout === "carousel" ? "grid" :
                            root.viewLayout === "grid"     ? "hex"  : "carousel"
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.viewLayout === "carousel"
                            ? "view_carousel"
                            : root.viewLayout === "grid" ? "grid_view" : "hexagon"
                        iconSize: 14
                        color: Appearance.colors.colOnLayer1
                    }
                }

                // Favorites toggle
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 26; implicitHeight: 26
                    radius: height / 2
                    color: root.favoritesOnly
                        ? Qt.alpha(Appearance.m3colors.m3primary, 0.18)
                        : (favHov.hovered ? Appearance.colors.colLayer2Base : "transparent")
                    Behavior on color { ColorAnimation { duration: 140 } }
                    HoverHandler { id: favHov }
                    TapHandler { onTapped: root.favoritesOnly = !root.favoritesOnly }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.favoritesOnly ? "favorite" : "favorite_border"
                        iconSize: 14
                        color: root.favoritesOnly
                            ? Appearance.m3colors.m3primary
                            : Appearance.colors.colOnLayer1
                    }
                }

                Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 18; color: Appearance.colors.colLayer0Border }

                // Hue swatches — quick-pick row in the toolbar. Tap to
                // add the hue to the active Wallhaven `colors=` filter and
                // re-search. Multi-select; the same swatch tapped again
                // removes it.
                Row {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2
                    visible: root.activeSource === "wallhaven"
                    Repeater {
                        model: root.hues
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool active:
                                root.whColors.split(",").indexOf(modelData.wh) >= 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14; height: active ? 22 : 16
                            radius: 3
                            color: Qt.color(modelData.swatch)
                            border.width: active ? 2 : 0
                            border.color: Appearance.m3colors.m3onSurface
                            Behavior on height { NumberAnimation { duration: 120 } }
                            HoverHandler { id: hueHov }
                            TapHandler { onTapped: root.toggleColor(modelData.wh) }
                            scale: hueHov.hovered ? 1.15 : 1
                            Behavior on scale { NumberAnimation { duration: 100 } }
                        }
                    }
                }

                Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 18; color: Appearance.colors.colLayer0Border }

                // Refresh / Tune / Settings / Count
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 26; implicitHeight: 26
                    radius: height / 2
                    color: refreshHov.hovered ? Appearance.colors.colLayer2Base : "transparent"
                    HoverHandler { id: refreshHov }
                    TapHandler { onTapped: root.refresh() }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "refresh"
                        iconSize: 14
                        color: Appearance.colors.colOnLayer1
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 26; implicitHeight: 26
                    radius: height / 2
                    color: tuneHov.hovered ? Appearance.colors.colLayer2Base : "transparent"
                    HoverHandler { id: tuneHov }
                    TapHandler { onTapped: root.openWallTune() }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "tune"
                        iconSize: 14
                        color: Appearance.m3colors.m3primary
                    }
                }

                // Wallhaven filter button — toggles a panel below
                Rectangle {
                    visible: root.activeSource === "wallhaven"
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 26; implicitHeight: 26
                    radius: height / 2
                    color: root.whFilterOpen
                        ? Qt.alpha(Appearance.m3colors.m3primary, 0.18)
                        : (filtHov.hovered ? Appearance.colors.colLayer2Base : "transparent")
                    Behavior on color { ColorAnimation { duration: 140 } }
                    HoverHandler { id: filtHov }
                    TapHandler { onTapped: root.whFilterOpen = !root.whFilterOpen }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "filter_list"
                        iconSize: 14
                        color: root.whFilterOpen
                            ? Appearance.m3colors.m3primary
                            : Appearance.colors.colOnLayer1
                    }
                }

                // Reddit filter button — same pattern as Wallhaven's, opens
                // the sort/listing override panel.
                Rectangle {
                    visible: root.activeSource === "reddit" || root.activeSource === "videos"
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 26; implicitHeight: 26
                    radius: height / 2
                    color: root.redditFilterOpen
                        ? Qt.alpha(Appearance.m3colors.m3primary, 0.18)
                        : (redFiltHov.hovered ? Appearance.colors.colLayer2Base : "transparent")
                    Behavior on color { ColorAnimation { duration: 140 } }
                    HoverHandler { id: redFiltHov }
                    TapHandler { onTapped: root.redditFilterOpen = !root.redditFilterOpen }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "filter_list"
                        iconSize: 14
                        color: root.redditFilterOpen
                            ? Appearance.m3colors.m3primary
                            : Appearance.colors.colOnLayer1
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: root.filtered.length
                    font.pixelSize: 10
                    color: Appearance.colors.colSubtext
                    Layout.leftMargin: 2
                    Layout.rightMargin: 2
                }
            }
        }

        // ── Wallhaven filters panel ──────────────────────────────────
        Rectangle {
            id: whFilters
            visible: root.activeSource === "wallhaven" && root.whFilterOpen
            anchors.top: toolbar.bottom
            anchors.topMargin: 4
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: Math.min(toolbar.width, whFilterCol.implicitWidth + 24)
            implicitHeight: whFilterCol.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1Base
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            z: 9

            ColumnLayout {
                id: whFilterCol
                anchors.centerIn: parent
                spacing: 8

                // Categories: General / Anime / People
                RowLayout {
                    spacing: 6
                    StyledText {
                        text: qsTr("Cat"); font.pixelSize: 10
                        color: Appearance.colors.colSubtext
                        Layout.preferredWidth: 32
                    }
                    Repeater {
                        model: [
                            { i: 0, label: "G" },
                            { i: 1, label: "A" },
                            { i: 2, label: "P" },
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool on: root.whCategories[modelData.i] === "1"
                            implicitWidth: 26; implicitHeight: 22
                            radius: 4
                            color: on ? Appearance.m3colors.m3primary
                                      : Appearance.colors.colLayer2Base
                            Behavior on color { ColorAnimation { duration: 140 } }
                            TapHandler {
                                onTapped: {
                                    const arr = root.whCategories.split("")
                                    arr[modelData.i] = (arr[modelData.i] === "1") ? "0" : "1"
                                    if (arr.indexOf("1") < 0) arr[modelData.i] = "1"   // can't all be off
                                    root.whCategories = arr.join("")
                                    root.refresh()
                                }
                            }
                            StyledText {
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: 10; font.weight: Font.Medium
                                color: parent.on ? Appearance.colors.colOnPrimary
                                                  : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }

                // Purity: SFW / Sketchy / NSFW
                RowLayout {
                    spacing: 6
                    StyledText {
                        text: qsTr("Pure"); font.pixelSize: 10
                        color: Appearance.colors.colSubtext
                        Layout.preferredWidth: 32
                    }
                    Repeater {
                        model: [
                            { i: 0, label: "SFW", danger: false, needKey: false },
                            { i: 1, label: "SKE", danger: false, needKey: true  },
                            { i: 2, label: "NSF", danger: true,  needKey: true  },
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool on: root.whPurity[modelData.i] === "1"
                            implicitWidth: 32; implicitHeight: 22
                            radius: 4
                            color: on
                                ? (modelData.danger ? Appearance.m3colors.m3error : Appearance.m3colors.m3primary)
                                : Appearance.colors.colLayer2Base
                            Behavior on color { ColorAnimation { duration: 140 } }
                            TapHandler {
                                onTapped: {
                                    const arr = root.whPurity.split("")
                                    arr[modelData.i] = (arr[modelData.i] === "1") ? "0" : "1"
                                    if (arr.indexOf("1") < 0) arr[modelData.i] = "1"
                                    root.whPurity = arr.join("")
                                    root.refresh()
                                }
                            }
                            StyledText {
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: 9; font.weight: Font.Medium
                                color: parent.on ? Appearance.colors.colOnPrimary
                                                  : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }

                // API-key hint: shown when Sketchy/NSFW is on but no key
                StyledText {
                    visible: (root.whPurity[1] === "1" || root.whPurity[2] === "1")
                             && root.whApiKey === ""
                    text: qsTr("Sketchy / NSFW need an API key — paste yours into ~/.config/wallhaven/apikey")
                    font.pixelSize: 9
                    color: Appearance.m3colors.m3error
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                // Sorting
                RowLayout {
                    spacing: 6
                    StyledText {
                        text: qsTr("Sort"); font.pixelSize: 10
                        color: Appearance.colors.colSubtext
                        Layout.preferredWidth: 32
                    }
                    Repeater {
                        model: root.whSortings
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool on: root.whSorting === modelData.id
                            implicitWidth: 36; implicitHeight: 22
                            radius: 4
                            color: on ? Appearance.m3colors.m3primary
                                      : Appearance.colors.colLayer2Base
                            Behavior on color { ColorAnimation { duration: 140 } }
                            TapHandler {
                                onTapped: { root.whSorting = modelData.id; root.refresh() }
                            }
                            StyledText {
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: 9; font.weight: Font.Medium
                                font.letterSpacing: 0.4
                                color: parent.on ? Appearance.colors.colOnPrimary
                                                  : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }

                // Top-range (only meaningful with sorting=toplist)
                RowLayout {
                    visible: root.whSorting === "toplist"
                    spacing: 6
                    StyledText {
                        text: qsTr("Top"); font.pixelSize: 10
                        color: Appearance.colors.colSubtext
                        Layout.preferredWidth: 32
                    }
                    Repeater {
                        model: root.whTopRanges
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool on: root.whTopRange === modelData
                            implicitWidth: 26; implicitHeight: 22
                            radius: 4
                            color: on ? Appearance.m3colors.m3primary
                                      : Appearance.colors.colLayer2Base
                            Behavior on color { ColorAnimation { duration: 140 } }
                            TapHandler {
                                onTapped: { root.whTopRange = modelData; root.refresh() }
                            }
                            StyledText {
                                anchors.centerIn: parent
                                text: modelData
                                font.pixelSize: 9; font.weight: Font.Medium
                                color: parent.on ? Appearance.colors.colOnPrimary
                                                  : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }

                // Aspect ratio
                RowLayout {
                    spacing: 6
                    StyledText {
                        text: qsTr("Ratio"); font.pixelSize: 10
                        color: Appearance.colors.colSubtext
                        Layout.preferredWidth: 32
                    }
                    Repeater {
                        model: root.whRatios
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool on: root.whRatio === modelData
                            implicitWidth: 36; implicitHeight: 22
                            radius: 4
                            color: on ? Appearance.m3colors.m3primary
                                      : Appearance.colors.colLayer2Base
                            Behavior on color { ColorAnimation { duration: 140 } }
                            TapHandler {
                                onTapped: { root.whRatio = modelData; root.refresh() }
                            }
                            StyledText {
                                anchors.centerIn: parent
                                text: modelData === "" ? qsTr("any") : modelData
                                font.pixelSize: 9; font.weight: Font.Medium
                                color: parent.on ? Appearance.colors.colOnPrimary
                                                  : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }

                // Min resolution
                RowLayout {
                    spacing: 6
                    StyledText {
                        text: qsTr("Min")
                        font.pixelSize: 10
                        color: Appearance.colors.colSubtext
                        Layout.preferredWidth: 32
                    }
                    Repeater {
                        model: root.whAtleasts
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool on: root.whAtleast === modelData.id
                            implicitWidth: 36; implicitHeight: 22
                            radius: 4
                            color: on ? Appearance.m3colors.m3primary
                                      : Appearance.colors.colLayer2Base
                            Behavior on color { ColorAnimation { duration: 140 } }
                            TapHandler {
                                onTapped: { root.whAtleast = modelData.id; root.refresh() }
                            }
                            StyledText {
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: 9; font.weight: Font.Medium
                                color: parent.on ? Appearance.colors.colOnPrimary
                                                  : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }

                // Colors — multi-select hue swatches. Empty selection means
                // no `colors=` filter. Each circle is the visual swatch; the
                // API receives Wallhaven's fixed palette code via `.wh`.
                RowLayout {
                    spacing: 6
                    StyledText {
                        text: qsTr("Hue"); font.pixelSize: 10
                        color: Appearance.colors.colSubtext
                        Layout.preferredWidth: 32
                    }
                    Repeater {
                        model: root.hues
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool on:
                                root.whColors.split(",").indexOf(modelData.wh) >= 0
                            implicitWidth: 22; implicitHeight: 22
                            radius: 11
                            // Coerce explicitly — `Rectangle.color` doesn't always
                            // pick up a `var`-typed JS string as a colour.
                            color: Qt.color(modelData.swatch)
                            border.width: on ? 2 : 0
                            border.color: Appearance.m3colors.m3onSurface
                            Behavior on border.width { NumberAnimation { duration: 140 } }
                            scale: on ? 1.15 : (hueHov.hovered ? 1.08 : 1)
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            HoverHandler { id: hueHov }
                            TapHandler { onTapped: root.toggleColor(modelData.wh) }
                            // Tiny check mark when selected.
                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: parent.on
                                text: "check"
                                iconSize: 13
                                color: Appearance.m3colors.m3onSurface
                            }
                        }
                    }
                    // Clear-colors X — only when at least one is picked.
                    Rectangle {
                        visible: root.whColors !== ""
                        implicitWidth: 18; implicitHeight: 18; radius: 9
                        color: Appearance.colors.colLayer2Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        TapHandler { onTapped: { root.whColors = ""; root.refresh() } }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"; iconSize: 12
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }

                // Reset everything to defaults.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 6
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        implicitWidth: resetRow.implicitWidth + 16
                        implicitHeight: 22
                        radius: 11
                        color: resetHov.hovered
                            ? Appearance.colors.colLayer2Hover
                            : Appearance.colors.colLayer2Base
                        Behavior on color { ColorAnimation { duration: 120 } }
                        HoverHandler { id: resetHov }
                        TapHandler {
                            onTapped: {
                                root.whCategories = "111"
                                root.whPurity     = "100"
                                root.whSorting    = "toplist"
                                root.whTopRange   = "1M"
                                root.whRatio      = ""
                                root.whAtleast    = ""
                                root.whColors     = ""
                                root.refresh()
                            }
                        }
                        Row {
                            id: resetRow
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "refresh"; iconSize: 12
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("Reset filters")
                                font.pixelSize: 10
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }

        // ── Reddit filters panel ─────────────────────────────────────
        Rectangle {
            id: redditFilters
            visible: (root.activeSource === "reddit" || root.activeSource === "videos")
                     && root.redditFilterOpen
            anchors.top: toolbar.bottom
            anchors.topMargin: 4
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: Math.min(toolbar.width, redditFilterCol.implicitWidth + 24)
            implicitHeight: redditFilterCol.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1Base
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            z: 9

            ColumnLayout {
                id: redditFilterCol
                anchors.centerIn: parent
                spacing: 6

                StyledText {
                    text: qsTr("Sort")
                    font.pixelSize: 10
                    color: Appearance.colors.colSubtext
                    Layout.alignment: Qt.AlignHCenter
                }

                Flow {
                    Layout.preferredWidth: Math.min(440, toolbar.width - 48)
                    spacing: 4
                    Repeater {
                        // "Auto" plus every sort defined in redditSorts.
                        model: [{ id: "", label: "AUTO" }].concat(
                            root.redditSorts.map(s => ({
                                id: s.path + s.q,
                                // Compact label: HOT, TOP·all, TOP·1y, NEW, RIS, CTL·all
                                label: (s.path === "top" ? "TOP·" + s.q.replace("?t=", "") :
                                        s.path === "controversial" ? "CTL·" + s.q.replace("?t=", "") :
                                        s.path === "rising" ? "RIS" :
                                        s.path.toUpperCase())
                            })))
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool on: root.redditForcedSort === modelData.id
                            implicitWidth: lbl.implicitWidth + 14
                            implicitHeight: 22
                            radius: height / 2
                            color: on
                                ? Appearance.m3colors.m3primary
                                : (sHov.hovered ? Appearance.colors.colLayer2Base : "transparent")
                            border.width: on ? 0 : 1
                            border.color: Appearance.colors.colLayer0Border
                            HoverHandler { id: sHov }
                            TapHandler {
                                onTapped: {
                                    root.redditForcedSort = modelData.id
                                    // Reset all per-sub counters so the next
                                    // sync runs against the freshly-chosen sort.
                                    if (modelData.id !== "") {
                                        const sub = (root.query || "wallpapers")
                                            .trim().replace(/^r\//i, "").toLowerCase()
                                        const sm = Object.assign({}, root.redditSortBySub)
                                        delete sm[sub]
                                        root.redditSortBySub = sm
                                    }
                                    if (!redditSyncProc.busy) root.syncReddit()
                                }
                            }
                            StyledText {
                                id: lbl
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                color: parent.on
                                    ? Appearance.m3colors.m3onPrimary
                                    : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }


        // ── Carousel (parallelogram) ──────────────────────────────────
        Item {
            id: carouselArea
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 30
            width: Math.min(parent.width - 80, 1400)
            height: Math.min(parent.height * 0.55, 360)
            visible: root.viewLayout === "carousel"

            ListView {
                id: carousel
                anchors.fill: parent
                orientation: ListView.Horizontal
                // ScriptModel diffs by stable id, so appending pages
                // doesn't reset the carousel — currentIndex stays put.
                model: ScriptModel {
                    values: root.filtered
                    objectProp: "id"
                }
                spacing: 8
                clip: true
                cacheBuffer: 400  // was 1200 — keeps ~1 card off-screen each side
                preferredHighlightBegin: width / 2 - 220
                preferredHighlightEnd:   width / 2 + 220
                highlightRangeMode: ListView.StrictlyEnforceRange
                highlightFollowsCurrentItem: true
                snapMode: ListView.SnapOneItem
                keyNavigationWraps: false
                // Two-way binding without the snap-back loop:
                // - on model growth, ListView briefly resets currentIndex
                //   to 0 internally before settling, which previously wrote
                //   that 0 back to root.activeIndex.  We guard with a flag.
                property bool _syncingFromRoot: false
                Component.onCompleted: currentIndex = root.activeIndex
                onCurrentIndexChanged: {
                    if (_syncingFromRoot) return
                    if (currentIndex !== root.activeIndex && currentIndex >= 0)
                        root.activeIndex = currentIndex
                    // Kick off client-side palette extraction for items
                    // without a Wallhaven-provided palette (Reddit/local).
                    if (currentIndex >= 0 && currentIndex < root.filtered.length)
                        root._ensurePaletteFor(root.filtered[currentIndex])
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
                // When the model array is appended, restore currentIndex
                // (it briefly drops to 0 inside ListView during the reflow).
                onCountChanged: {
                    if (currentIndex !== root.activeIndex
                            && root.activeIndex < count) {
                        _syncingFromRoot = true
                        currentIndex = root.activeIndex
                        _syncingFromRoot = false
                    }
                }
                boundsBehavior: Flickable.StopAtBounds
                // Phone-style inertial flick: low deceleration → long
                // glide that gradually fades, snap settles on whichever
                // item the cursor lands on after coast.
                flickDeceleration: 800
                maximumFlickVelocity: 6000

                // Touchpad / wheel → kinetic flick.  Each wheel event
                // contributes to a velocity accumulator; when a brief
                // gap appears in the wheel stream we hand the
                // accumulated velocity to Flickable.flick(), which then
                // decelerates naturally — scroll keeps gliding after
                // the user lifts their fingers like on a phone.
                WheelHandler {
                    id: carouselWheel
                    target: null
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    property real velocityX: 0
                    onWheel: (event) => {
                        event.accepted = true
                        const delta = event.angleDelta.y + event.angleDelta.x
                        // 8 px / wheel-unit feels like a phone swipe.
                        velocityX -= delta * 8
                        flickGap.restart()
                    }
                }
                Timer {
                    id: flickGap
                    // Short window; once no new wheel events come in,
                    // hand the accumulated velocity to Flickable.flick.
                    interval: 60
                    repeat: false
                    onTriggered: {
                        if (Math.abs(carouselWheel.velocityX) > 80)
                            carousel.flick(carouselWheel.velocityX, 0)
                        carouselWheel.velocityX = 0
                    }
                }

                delegate: Item {
                    required property var modelData
                    required property int index
                    width: 120
                    height: carousel.height
                    z: index === carousel.currentIndex ? 10 : 1

                    // (Colored aura blob removed at user request — was three
                    // overlapping circles behind the focused parallelogram.)

                    Item {
                        anchors.centerIn: parent
                        readonly property bool active: parent.index === carousel.currentIndex
                        width: active ? 440 : 110
                        height: carousel.height * 0.78
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
                                cache: false
                                smooth: true
                                // Carousel tiles are larger than grid — give
                                // them more pixels but still cap below 4K.
                                sourceSize.width: 1280
                                // Hide until fully decoded to avoid showing
                                // partial-JPEG rainbow during the load window.
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

                            // Auto-play the focused video; Loader unloads
                            // when focus leaves to release the decoder.
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
                    // Five small swatches from the wallhaven palette,
                    // floating right below the parallelogram. Click one
                    // to add it to the colour filter and re-search.
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
                                HoverHandler { id: palHov }
                                scale: palHov.hovered ? 1.18 : 1
                                Behavior on scale { NumberAnimation { duration: 140 } }
                                TapHandler {
                                    onTapped: {
                                        // Snap to nearest wallhaven palette
                                        // code and append to the filter.
                                        const want = String(modelData).replace("#", "").toLowerCase()
                                        // wallhaven only accepts its fixed
                                        // palette, so just push the raw hex
                                        // — Wallhaven will round-down.
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
                cacheBuffer: cellHeight   // was cellHeight*3
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
                            // Wallhaven CDN occasionally 404s a thumb;
                            // fall back to the full image URL before giving up.
                            property int retries: 0
                            source: modelData.thumb
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            smooth: true
                            // Decode at tile size, not source size. Reddit's
                            // `thumb` is the same local 4K JPEG as `full`, so
                            // without this QML loads a ~5MB decoded texture
                            // per tile and the grid feels glued. width-only
                            // preserves aspect.
                            sourceSize.width: 480
                            // Stay invisible until the decoder is fully done.
                            // This prevents partial-JPEG rainbow flashes if a
                            // file becomes visible mid-write (fetcher race) or
                            // during the brief decode window on slow disks.
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
                        // Loading indicator while the tile decodes. Subtle
                        // pulsing dot — keeps the grid feeling alive without
                        // hijacking attention. Auto-hides on Ready or Error.
                        Rectangle {
                            anchors.centerIn: parent
                            width: 10; height: 10; radius: 5
                            visible: gridImg.status === Image.Loading
                            color: Appearance.m3colors.m3primary
                            opacity: 0.55
                            SequentialAnimation on scale {
                                running: parent.visible
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

        // ── Hex (placeholder — falls through to grid for now) ─────────
        Item {
            anchors.fill: parent
            anchors.topMargin: 80
            anchors.bottomMargin: 30
            visible: root.viewLayout === "hex"
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "hexagon"
                    iconSize: 36
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Hex layout coming soon")
                    color: Appearance.colors.colSubtext
                }
            }
        }

        // Empty state
        // Reddit tab gets a context-aware variant: when you've typed a sub
        // name that isn't cached, surface a "Fetch r/<typed>" button so
        // it's obvious Enter (or this click) triggers the gallery-dl sync.
        // While a sync is in flight, swap to a "Fetching…" indicator.
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

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: emptyState.busy
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
                text: emptyState.busy
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

        // Search input (bottom, only for wallhaven / reddit)
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 8
            visible: root.activeSource !== "local"
            implicitHeight: 28
            implicitWidth: 280
            radius: height / 2
            color: Appearance.colors.colLayer1Base
            border.width: 1
            border.color: searchInput.activeFocus
                ? Appearance.m3colors.m3primary
                : Appearance.colors.colLayer0Border
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 6
                MaterialSymbol {
                    text: "search"
                    iconSize: 12
                    color: Appearance.colors.colSubtext
                }
                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: 11
                    selectByMouse: true
                    text: root.query
                    onTextChanged: root.query = text
                    Keys.onReturnPressed: {
                        // On the Reddit tab, Enter triggers a gallery-dl
                        // fetch for r/<typed>. Other tabs just refresh.
                        if (root.activeSource === "reddit") root.syncReddit()
                        else                                root.refresh()
                    }
                    Keys.onEscapePressed: root.close()
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: root.activeSource === "reddit"
                            ? qsTr("filter or type r/sub + Enter to fetch…")
                            : qsTr("search wallhaven…")
                        color: Appearance.colors.colSubtext
                        font: parent.font
                        visible: parent.text.length === 0
                    }
                }
            }
        }
    }
}
