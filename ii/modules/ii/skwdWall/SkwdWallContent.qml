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

    // Embedded mode: the launcher search morphs into skwd and drives `query`
    // itself, so we hide skwd's own SEARCH panel and skip state persistence
    // (the windowed instance owns that).
    property bool embedded: false

    // Gap between the centered metadata+search panel and the post panel.
    readonly property real pairGap: 12

    readonly property string home: "/home/caesar"
    // local | wallhaven | reddit | videos — owned by WallpaperHub so the
    // source icons work identically in this toolbar and the launcher's.
    readonly property string activeSource: WallpaperHub.source
    // Default subreddit(s) for the Videos tab — multireddit syntax
    // (a+b+c). Both verified live and carrying playable v.redd.it
    // videos with poster previews.
    // Media type and the favourites filter live in WallpaperHub: the launcher
    // bar shows the same chips, and changing them there has to take effect
    // here immediately (they used to apply only at navigation time).
    readonly property string activeMediaType: WallpaperHub.mediaType   // all | pic | vid | we
    readonly property bool favoritesOnly: WallpaperHub.favoritesOnly
    property string viewLayout: "carousel"         // carousel | grid | hex
    property int activeIndex: 0
    property string query: ""
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
    // Both live in WallpaperHub: the launcher draws the same chips in its
    // dropdown, and picking a sort there has to mean the same thing here.
    readonly property bool   redditFilterOpen: WallpaperHub.filterOpen
    readonly property string redditForcedSort: WallpaperHub.forcedSort

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
    // Single source of truth lives in the WallpaperHub singleton so the
    // launcher's wallpaper mode and skwd share the exact same columns.
    readonly property var hues: WallpaperHub.hues
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

    // Palette extraction and metadata both shell out (magick / identify), and
    // a touchpad produces a stream of index changes — running them per step
    // spawned dozens of magick processes on 4K images and froze the shell.
    // Nothing happens until the scroll settles.
    Timer {
        id: focusSettle
        interval: 180
        repeat: false
        onTriggered: {
            if (paletteExtractProc.running || metaProc.running) {
                // Busy from the last settle — come back rather than piling on.
                focusSettle.restart()
                return
            }
            const i = root.activeIndex
            if (i >= 0 && i < root.filtered.length) {
                root._ensurePaletteFor(root.filtered[i])
                root._fetchMetaFor(root.filtered[i])
            }
        }
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
    // colour filter. Multi-select, owned by WallpaperHub so the launcher's
    // swatches and this panel edit ONE selection.
    readonly property string whColors: WallpaperHub.colors
    function toggleColor(wh) {
        WallpaperHub.toggleColor(wh)
    }
    // Re-query Wallhaven whenever the colour selection changes, wherever the
    // change came from.
    onWhColorsChanged: if (root.activeSource === "wallhaven") Qt.callLater(root.refresh)

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
        // Favourites filter — the heart in either toolbar. Was previously a
        // toggle that filtered nothing.
        if (root.favoritesOnly)
            list = list.filter(w => WallpaperHub.isFavorite(w.path))
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
                // Prefer an EXACT subreddit match (so "wallpapers" doesn't also
                // pull in "WallpapersDoA"); fall back to fuzzy title/id/sub
                // matching only when nothing matches the sub exactly.
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

    // Reddit pagination state lives in redditAfterBySub, keyed by (sub, sort),
    // and is fed by the authenticated fetcher. There used to be a second,
    // separate cursor here for an unauthenticated hot.json path — Reddit has
    // 403'd those since 2024, and nothing set the cursor, so the Videos tab
    // that depended on it could never page. Both tabs now share syncReddit().

    // How many cached files the scan loads at once, and when it last ran.
    // Grown in pages as the user reaches the end, so a sub with thousands of
    // cached files is fully reachable without loading them all up front.
    readonly property int scanPageSize: 400
    property int scanLimit: scanPageSize
    property real lastScanTime: 0
    // Run the disk scan. `incremental` only picks up files newer than the last
    // pass and appends them (used by the live rescan during a sync).
    function runScan(incremental) {
        redditScanProc.since = incremental ? root.lastScanTime : 0
        redditScanProc.running = true
    }

    // ── Reddit (cached via gallery-dl) ────────────────────────────────
    // Scans the gallery-dl download dir for previously-fetched Reddit
    // posts. Filenames look like "<id> <title> [WxH].ext"; the id is
    // the leading non-space token.
    Process {
        id: redditScanProc
        // The subreddit whose cache we want. Without this the scan took the
        // globally newest 200 files across ALL subs, so asking for a sub whose
        // files weren't in that window showed "Nothing cached" (even with
        // hundreds on disk), and a sub that was only partly in it showed a
        // handful of cards — which is why the carousel had nothing to scroll.
        readonly property string scanSub: {
            // "videos" too. Excluding it meant the Videos tab scanned the
            // globally newest files across ALL subs and then filtered them down
            // to the typed sub — the exact failure the comment above describes
            // for Reddit, which was fixed there and never extended here. Asking
            // for r/rule34 on the VID tab therefore surfaced only whatever of
            // its videos happened to fall inside that global window.
            if (root.activeSource !== "reddit" && root.activeSource !== "videos")
                return ""
            const q = (root.query || "").trim()
            return q.replace(/^r\//i, "").replace(/[^A-Za-z0-9_]/g, "")
        }
        // > 0 → only list files newer than this epoch time and APPEND them.
        // The 800 ms rescan during a sync used to re-list and re-hash the whole
        // folder and rebuild the model from scratch; now it looks at just the
        // handful of files that landed since the last pass.
        property real since: 0
        readonly property bool appendMode: since > 0
        // Scan BOTH the new (under ~/Pictures/Wallpapers/skwd) and the
        // legacy (~/.config/gallery-dl) download roots, AND video files
        // alongside images. For each video, the first frame is extracted
        // once into ~/.cache/quickshell/skwd-posters/<md5>.jpg so the
        // carousel has something to paint until VideoOutput kicks in.
        // Output lines: `<kind>|<posterpath>|<realpath>`.
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
                 list=$(find "\${sdirs[@]}" -maxdepth 1 -type f "\${newer[@]}" \\( "\${types[@]}" \\) -printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | cut -f2- | head -"$limit")
               fi
             fi
             # No sub (or nothing cached for it) → newest across every sub.
             # Skipped for incremental passes: there we only want new arrivals.
             if [ -z "$list" ] && [ "$since" -eq 0 ]; then
               list=$(find "\${exist[@]}" -maxdepth 2 -type f \\( "\${types[@]}" \\) -printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | cut -f2- | head -200)
             fi
             [ -z "$list" ] && exit 0
             # Phase 1: build any missing thumbnails ACROSS ALL CORES. The
             # jpeg:size hint lets libjpeg downscale while decoding, so a 4K
             # original never fully decodes — this is the whole speed win.
             maxj=$(nproc)
             while IFS= read -r f; do
               [ -z "$f" ] && continue
               h=$(printf '%s' "$f" | md5sum | cut -d' ' -f1); p="$postdir/$h.jpg"
               [ -f "$p" ] && continue
               ( case "\${f,,}" in
                   *.mp4|*.webm|*.m4v|*.mkv|*.mov|*.gif) ffmpeg -nostdin -y -loglevel quiet -i "$f" -vf 'scale=720:-2' -vframes 1 "$p" 2>/dev/null ;;
                   *) magick -define jpeg:size=1024x1024 "$f" -auto-orient -thumbnail '720x>' -quality 80 "$p" 2>/dev/null ;;
                 esac ) &
               while [ "$(jobs -rp | wc -l)" -ge "$maxj" ]; do wait -n; done
             done <<< "$list"
             wait
             # Phase 2: emit model lines (newest first), thumbnail if it exists.
             while IFS= read -r f; do
               [ -z "$f" ] && continue
               h=$(printf '%s' "$f" | md5sum | cut -d' ' -f1); p="$postdir/$h.jpg"
               case "\${f,,}" in
                 *.mp4|*.webm|*.m4v|*.mkv|*.mov|*.gif) [ -f "$p" ] && echo "vid|$p|$f" || echo "vid|$f|$f" ;;
                 *) [ -f "$p" ] && echo "pic|$p|$f" || echo "pic|$f|$f" ;;
               esac
             done <<< "$list"`]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l.length > 0)
                const parsed = lines.map(line => {
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
                        full:   encUrl(real),
                        source: "reddit",
                        kind:   kind,                 // "pic" or "vid"
                        path:   real,                 // raw real path → fast apply
                        videoUrl: kind === "vid" ? encUrl(real) : "",
                    }
                })
                if (redditScanProc.appendMode) {
                    // Incremental pass: keep what's already on screen (and the
                    // user's place in it) and add only genuinely new files at
                    // the END. A full rebuild here would reshuffle the strip
                    // mid-scroll every 800 ms while a sync is running.
                    const seen = {}
                    root.wallpapers.forEach(w => seen[w.path] = true)
                    const fresh = parsed.filter(w => !seen[w.path])
                    if (fresh.length > 0)
                        root.wallpapers = root.wallpapers.concat(fresh)
                } else {
                    root.wallpapers = parsed
                }
                // Stamp slightly in the past: file mtimes and the clock here
                // can disagree by a hair, and missing a file is worse than
                // re-listing one.
                root.lastScanTime = Date.now() / 1000 - 5
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
            // Full pass once the sync finishes, so ordering settles.
            root.runScan(false)
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
    // Defined once in WallpaperHub so the launcher's filter chips and this
    // fetcher always mean the same listing.
    readonly property var redditSorts: WallpaperHub.redditSorts
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

    // ── Subreddit autocomplete ────────────────────────────────────────
    // As the user types a sub name, reddit_complete.sh hits Reddit's
    // autocomplete API and we show a dropdown of matches — each with its
    // subscriber count and an NSFW tag for over-18 subs. Picking one (click
    // or Enter) fills the query and fetches it.
    readonly property string scriptDir: `${root.home}/.config/quickshell/ii/scripts/colors`
    property var redditCompletions: []      // [{ name, nsfw, subs }]
    property int completionIndex: -1
    property bool completionsOpen: false

    Timer {
        id: completionDebounce
        interval: 220
        repeat: false
        onTriggered: {
            if (root.activeSource !== "reddit") { root.completionsOpen = false; return }
            const q = (root.query || "").trim().replace(/^\/?r\//i, "")
            if (q.length < 2) { root.redditCompletions = []; root.completionsOpen = false; return }
            redditCompleteProc.command = ["bash", "-c",
                `'${root.scriptDir}/reddit_complete.sh' '${q.replace(/'/g, "")}'`]
            redditCompleteProc.running = true
        }
    }
    Process {
        id: redditCompleteProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.activeSource !== "reddit") return
                const rows = text.trim().split("\n").filter(l => l.length > 0)
                root.redditCompletions = rows.map(l => {
                    const c = l.split("\t")
                    return { name: c[0] || "", nsfw: c[1] === "1", subs: parseInt(c[2] || "0", 10) }
                }).filter(r => r.name.length > 0)
                root.completionIndex = -1
                root.completionsOpen = root.redditCompletions.length > 0
            }
        }
    }
    function applyCompletion(i) {
        if (i < 0 || i >= root.redditCompletions.length) return
        root.query = root.redditCompletions[i].name
        root.querySubConfirmed = true
        root.completionsOpen = false
        root.redditCompletions = []
        root.syncReddit()
    }

    // ── Only fetch subs the user actually meant ──────────────────────
    // Typing "wallpapers" used to fire a fetch for "w", "wa", "wal", … each
    // creating an empty cache dir and a junk page-map key. A sub counts as
    // real once it's been chosen (launcher pick, completion pick, restored
    // state) or typed out in full so a completion matches it exactly.
    property bool querySubConfirmed: false
    function queryIsRealSub() {
        if (root.querySubConfirmed) return true
        const q = (root.query || "").trim().replace(/^r\//i, "").toLowerCase()
        if (q.length === 0) return false
        return root.redditCompletions.some(c => (c.name || "").toLowerCase() === q)
    }
    // 1_962_009 → "2M", 736_079 → "736k".
    function formatSubs(n) {
        if (n >= 1000000) return (n / 1000000).toFixed(n >= 10000000 ? 0 : 1) + "M"
        if (n >= 1000)    return (n / 1000).toFixed(n >= 100000 ? 0 : 1) + "k"
        return String(n)
    }

    // ── Focused-item metadata ─────────────────────────────────────────
    // dimensions / format / byte size read off the actual file (local &
    // reddit-cached items only — remote URLs would need a download). Keyed
    // by id so re-focusing a seen item doesn't re-run identify.
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
            `d=$(identify -format '%wx%h|%m' "$f" 2>/dev/null | head -1); ` +
            `s=$(stat -c%s "$f" 2>/dev/null || echo 0); echo "$d|$s"`]
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
    function formatBytes(n) {
        if (!n || n <= 0) return "—"
        if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB"
        if (n >= 1024)    return (n / 1024).toFixed(0) + " KB"
        return n + " B"
    }

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
        // Any change re-arms the gate; the paths that KNOW the sub is real
        // (navigate, applyCompletion, restore) set it back right after they
        // assign the query.
        root.querySubConfirmed = false
        if (root.activeSource !== "reddit") return
        // Refresh the autocomplete dropdown as they type. In embedded mode
        // the launcher owns the search UI, so skip completions (and let the
        // auto-fetch below fire, since it waits on !completionsOpen).
        if (!root.embedded) completionDebounce.restart()
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
        // the threshold). Skipped while the completion dropdown is up — the
        // user is picking a sub, so we wait for their choice instead of
        // fetching every half-typed prefix.
        if (cleaned.length >= 2 && !root.completionsOpen) redditSearchKick.restart()
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
            // Incremental while files are still landing — cheap, and it
            // doesn't move anything already on screen.
            if (!redditScanProc.running) root.runScan(true)
        }
    }


    // Stub kept so other references don't break.
    property var redditDrySubs: ({})

    function loadMoreReddit() {
        // Each call advances the per-sub page counter inside syncReddit.
        //
        // The Videos tab goes through the SAME authenticated fetcher. It used
        // to fall through to an unauthenticated curl of reddit's .json, which
        // has 403'd since 2024 (this file says so at redditAfter's declaration)
        // — and it could not even reach that: `redditAfter` is only ever set
        // from that dead request's response, so the `if (!redditAfter) return`
        // above it returned on every single call. The tab could therefore never
        // download anything, and only ever showed videos that some earlier
        // Reddit-tab sync happened to leave on disk. Downloads land in one
        // shared cache and `filtered` selects kind == "vid", so there is no
        // reason for this tab to have its own fetch path at all.
        if (root.activeSource !== "reddit" && root.activeSource !== "videos")
            return
        if (redditSyncProc.busy) return
        root.syncReddit()
    }

    function refresh() {
        root.loading = true
        root.wallpapers = []
        root.activeIndex = 0
        // New query/source → back to the first page of the disk scan.
        root.scanLimit = root.scanPageSize
        root.lastScanTime = 0
        // New sub/source: the Videos chain starts over, otherwise a sub that
        // exhausted the budget leaves the next one unable to page at all.
        root._vidChainTries = 0
        root.whPage = 1
        root.whHasMore = true
        root.whLoadingMore = false
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
            root.runScan(false)
        }
    }

    // ── Persistence (skwd panel state, restored on lazy reopen) ───────
    // Survives the Loader unloading SkwdWallContent between sessions. We
    // restore activeSource/activeMediaType/query/activeIndex *before* the
    // first refresh() runs so the right tab gets fetched, and we keep
    // saving via a debounce on each property change.
    Timer { id: skwdSaveDebounce; interval: 250; repeat: false; onTriggered: root._savePersistedState() }
    function _savePersistedState() {
        if (root.embedded) return
        const s = Persistent.states.skwd
        if (!s) return
        s.activeSource    = root.activeSource
        s.activeMediaType = root.activeMediaType
        s.query           = root.query
        s.activeIndex     = root.activeIndex
        // The forced sort is a deliberate choice — it should still be in
        // effect next time. (filterOpen deliberately isn't saved: the panel
        // always starts closed.)
        s.forcedSort      = WallpaperHub.forcedSort
        try {
            s.redditPageMap = JSON.stringify(root.redditPageBySub || {})
            s.favorites     = JSON.stringify(Object.keys(WallpaperHub.favoritePaths || {}))
        } catch (e) { /* nothing */ }
    }
    function _restorePersistedState() {
        if (root.embedded) return
        const s = Persistent.states.skwd
        if (!s) return
        if (s.activeSource    && s.activeSource.length    > 0) WallpaperHub.source  = s.activeSource
        if (s.activeMediaType && s.activeMediaType.length > 0) WallpaperHub.mediaType = s.activeMediaType
        if (s.query           !== undefined)                 { root.query = s.query
                                                               // Restored from a real session → fetchable.
                                                               root.querySubConfirmed = true }
        if (s.activeIndex     >= 0)                            root.activeIndex     = s.activeIndex
        if (s.forcedSort      !== undefined)                   WallpaperHub.forcedSort = s.forcedSort
        try {
            const m = JSON.parse(s.redditPageMap || "{}")
            if (m && typeof m === "object") root.redditPageBySub = m
        } catch (e) { /* leave default */ }
        try {
            const favs = JSON.parse(s.favorites || "[]")
            if (Array.isArray(favs)) {
                const m = {}
                favs.forEach(p => { if (p) m[p] = true })
                WallpaperHub.favoritePaths = m
            }
        } catch (e) { /* leave default */ }
    }

    // ── Cache hygiene ────────────────────────────────────────────────
    // Removes the empty sub dirs left behind by the old fetch-every-prefix
    // behaviour, then reports what's actually cached so the page/sort/dry
    // counters for subs that never existed can be dropped too.
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
                root.redditDrySubs    = prune(root.redditDrySubs)
                const after = Object.keys(root.redditPageBySub || {}).length
                if (after !== before) {
                    console.log("[skwd] pruned", before - after, "stale page-map entries")
                    skwdSaveDebounce.restart()
                }
            }
        }
    }
    // Qt.callLater: `activeSource` is a binding on WallpaperHub.source, so it
    // is first evaluated lazily — from inside `filtered`'s own evaluation.
    // Refreshing straight away clears `wallpapers` mid-evaluation, which Qt
    // reports as a binding loop and leaves `filtered` empty (nothing to
    // scroll). Deferring by one event-loop turn keeps the two apart.
    onActiveSourceChanged:    { skwdSaveDebounce.restart(); root.completionsOpen = false; root.redditCompletions = []; Qt.callLater(root.refresh) }
    onActiveMediaTypeChanged: skwdSaveDebounce.restart()
    Component.onCompleted: {
        _restorePersistedState()
        refresh()
        if (!root.embedded) cachePruneProc.running = true
    }
    Component.onDestruction: _savePersistedState()

    // Live navigation from the launcher: when skwd is already open and the
    // user picks another subreddit in the launcher, jump to it (a fresh open
    // instead seeds via _restorePersistedState above).
    // Single clamped way to move the selection — wheel, middle-drag, arrow
    // keys and the launcher bar all go through here, so every input steps the
    // carousel identically in BOTH directions.
    // ── Wheel → step the carousel ────────────────────────────────────
    // Lives on root so ANY surface can feed it: the carousel, and the whole
    // skwd area (the metadata/post panels underneath used to swallow the
    // wheel, which read as "scrolling randomly stops working").
    property real _wheelAccum: 0
    property int _wheelBurst: 0
    property real _lastWheelMs: 0
    readonly property real wheelStepUnits: 120
    readonly property int maxWheelStride: 12
    // Finger travel that equals one wallpaper on a touchpad. Tuned against the
    // 120-unit notch below so a mouse click and a short swipe move the same.
    readonly property real wheelPixelsPerStep: 100
    // A gesture that stopped this long ago is over; its leftover fraction must
    // not add itself to the next one and make the first step arrive early.
    readonly property int wheelIdleMs: 400
    // Opt-in delta logging; see the console.log in wheelScroll below.
    readonly property bool _wheelDebug: Quickshell.env("SKWD_WHEEL_DEBUG") === "1"

    /// `axis` is the orientation of the handler that delivered this event.
    /// It matters: the two handlers below both receive a DIAGONAL event, and
    /// this used to add (x + y) on each of them, counting a drifting swipe
    /// twice. Each handler now contributes only its own axis, so the total is
    /// still x + y but each component lands exactly once.
    // Signature of the last event consumed, to drop duplicate deliveries.
    property string _lastWheelSig: ""

    function wheelScroll(event, axis) {
        event.accepted = true
        const now = Date.now()

        // There are TWO sets of handlers: one on the carousel, one on the
        // whole skwd area, which is its ANCESTOR. A comment there claimed the
        // carousel "accepts first, so this never double-steps" — but a
        // WheelHandler takes no exclusive grab, and event.accepted does not
        // stop handlers on ancestor items. Every wheel event over the carousel
        // was therefore counted twice, which is the uneven stepping: scroll
        // over a card and you move 2, scroll over the empty margin and you
        // move 1.
        // Keyed on the deltas alone and cleared on the next event-loop pass,
        // NOT on a millisecond timestamp: both handlers run synchronously
        // within one delivery, so a same-tick repeat is always the duplicate,
        // while a genuine repeat of identical deltas arrives on a later tick
        // and is still counted.
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

        // Both axes are normalised to FRACTIONS OF ONE WALLPAPER and the
        // larger wins.
        //
        // pixelDelta used to be consulted only when angleDelta was exactly
        // zero. A touchpad sends small non-zero angleDelta fragments, so a slow
        // swipe contributed a few units against a 120-unit threshold and moved
        // nothing — "it only scrolls if I swipe fast" was that threshold, not a
        // dropped event.
        //
        // Simply preferring pixelDelta would be wrong in the other direction:
        // where Qt reports a well-scaled angleDelta (30) beside a small
        // pixelDelta (5), that swaps a working path for a 5x slower one. Taking
        // the larger of the two can only ever help, whichever way this
        // compositor and Qt build happen to report a touchpad.
        const fromAngle = ang / root.wheelStepUnits
        const fromPixel = px / root.wheelPixelsPerStep
        const steps = Math.abs(fromPixel) > Math.abs(fromAngle) ? fromPixel : fromAngle

        // What a touchpad actually reports here is compositor- and Qt-build
        // specific, and the two cases need different tuning: plenty of
        // pixelDelta is handled above, whereas tiny angleDelta with NO
        // pixelDelta cannot be fixed without knowing the real magnitudes.
        // `SKWD_WHEEL_DEBUG=1 qs -c ii` prints them instead of guessing.
        if (root._wheelDebug)
            console.log("[skwd wheel]", (axis === Qt.Horizontal ? "h" : "v"),
                        "angle=" + ang, "pixel=" + px,
                        "steps=" + steps.toFixed(3),
                        "accum=" + (root._wheelAccum + steps).toFixed(3))

        if (steps === 0)
            return
        // Gap since the PREVIOUS event, captured before the clock is advanced —
        // the burst detector below compares against it, and updating first made
        // every notch look 0ms apart, i.e. permanently accelerating.
        const sinceLast = now - root._lastWheelMs
        root._lastWheelMs = now

        // A click wheel sends whole ±120 notches; a touchpad sends a stream of
        // small fragments. Only the former accelerates — applying a burst
        // multiplier to a touchpad made one swipe jump dozens of wallpapers.
        // Judged on the RAW angle delta: a fast touchpad swipe can now produce
        // a scaled `d` past 120, and treating that as a notch would bring the
        // acceleration back on exactly the input it was disabled for.
        const notched = px === 0 && Math.abs(ang) >= 120
        let stride = 1
        if (notched) {
            root._wheelBurst = (sinceLast < 180)
                ? Math.min(root._wheelBurst + 1, 24) : 0
            stride = Math.min(root.maxWheelStride, 1 + Math.floor(root._wheelBurst / 3))
        } else {
            root._wheelBurst = 0
        }
        // The accumulator now counts WHOLE WALLPAPERS (1.0 = one), not raw
        // wheel units, because the two input kinds no longer share a unit.
        root._wheelAccum += steps
        while (Math.abs(root._wheelAccum) >= 1) {
            const back = root._wheelAccum > 0
            root._wheelAccum += back ? -1 : 1
            root.stepActive(back ? -stride : stride)
        }
    }

    function setActive(i) {
        if (root.filtered.length === 0) return
        root.activeIndex = Math.max(0, Math.min(i, root.filtered.length - 1))
    }
    function stepActive(delta) {
        root.setActive(root.activeIndex + delta)
    }

    // Force a Reddit listing sort ("" = back to the auto-cycle). Called from
    // skwd's own chips and, via WallpaperHub.sortPicked, from the launcher's.
    function applySort(id) {
        WallpaperHub.forcedSort = id
        skwdSaveDebounce.restart()
        // Reset this sub's counters so the next sync runs against the newly
        // chosen sort instead of resuming the old one's pagination.
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
        enabled: !root.embedded
        function onNavigate(sub) {
            WallpaperHub.source = "reddit"
            root.query = sub
            // Picked in the launcher's dropdown → a real sub, safe to fetch.
            root.querySubConfirmed = true
        }
        function onCarouselStep(delta) {
            root.stepActive(delta)
        }
        function onReload() { root.refresh() }
        function onSortPicked(id) { root.applySort(id) }
        function onApplyFocused() {
            if (root.activeIndex >= 0 && root.activeIndex < root.filtered.length)
                root.applyWallpaper(root.filtered[root.activeIndex])
        }
    }

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
        else if (activeSource === "reddit" || activeSource === "videos") {
            // Before hitting the network, check whether the cap is what's
            // holding us back — a sub with 800 cached files shouldn't stop at
            // the first 400. Grow the page and re-scan disk first.
            if (root.wallpapers.length >= root.scanLimit) {
                // One page at a time: scrolling fast past the end used to fire
                // a fresh disk scan on every step, each one a find + md5sum
                // over hundreds of files.
                if (redditScanProc.running) return
                root.scanLimit += root.scanPageSize
                root.runScan(false)
                return
            }
            loadMoreReddit()
        }
    }
    // Tracks the previous filtered length so onFilteredChanged can detect
    // "did we actually grow?". Used to chain-fire pagination on Reddit
    // even at high item counts — without this, reaching end-of-list once
    // fires loadMore, the new items arrive, but activeIndex doesn't move
    // so onActiveIndexChanged never re-fires and the chain dies.
    property int _lastFilteredLen: 0

    // ── Keeping the chain alive on the Videos tab ─────────────────────
    // The chain below pumps on `filtered`, which on the Videos tab is
    // video-only. A page of 100 Reddit posts commonly contains NO video: it
    // grows `wallpapers` but leaves `filtered` byte-identical, so no change
    // signal fires and pagination stops dead. That is why the tab loaded a
    // handful of items and then nothing, however far you scrolled.
    //
    // So pump on the unfiltered list too, and keep pulling while the visible
    // video count is still sparse. Bounded: without a ceiling a sub with no
    // videos at all would page until it exhausted every sort.
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
            arr.push({ icon: WallpaperHub.isFavorite(md.path) ? "favorite" : "favorite_border",
                       label: WallpaperHub.isFavorite(md.path) ? "Remove from favourites" : "Add to favourites",
                       onTriggered: () => WallpaperHub.toggleFavorite(md.path) })
            // KIO's standalone properties dialog — the same one Dolphin shows,
            // without launching Dolphin.
            arr.push({ icon: "info", label: "Properties…",
                       onTriggered: () => Quickshell.execDetached(["kioclient", "openProperties", md.path]) })
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

        // Wheel anywhere over skwd steps the carousel — over the cards, the
        // info panel, the empty space around them. The carousel's own handlers
        // accept first, so this never double-steps.
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

        // Floating pill toolbar at top.
        // The launcher's search bar IS this bar — when the launcher is up it
        // owns the controls, and this one stays out of the way instead of
        // being a second copy on screen. It only appears as a fallback if
        // skwd somehow ends up open without the launcher.
        Rectangle {
            id: toolbar
            visible: !GlobalStates.overviewOpen
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

                // Shared with the launcher's search bar — one definition in
                // WallpaperControls, one state in WallpaperHub, so this IS
                // the launcher bar rather than a second copy of it.
                WallpaperControls {
                    Layout.alignment: Qt.AlignVCenter
                    compact: true
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

                // Colour filter — same component as the launcher bar.
                WallpaperHueSelector {
                    Layout.alignment: Qt.AlignVCenter
                    compact: true
                    visible: root.activeSource === "wallhaven"
                }

                Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 18; color: Appearance.colors.colLayer0Border }

                // Tune / Settings / Count
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
                            scale: on ? 1.15 : (whHov.hovered ? 1.08 : 1)
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            HoverHandler { id: whHov }
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
                        TapHandler { onTapped: WallpaperHub.colors = "" }
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
                                WallpaperHub.colors = ""
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
            // Hidden while the launcher is open — it draws the same chips in
            // its dropdown, and two copies on screen would just fight.
            visible: (root.activeSource === "reddit" || root.activeSource === "videos")
                     && root.redditFilterOpen
                     && !root.embedded && !GlobalStates.overviewOpen
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
                        // AUTO + every sort, labelled once in WallpaperHub.
                        model: WallpaperHub.sortChips
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool on: root.redditForcedSort === modelData.id
                            implicitWidth: lbl.implicitWidth + 16
                            implicitHeight: 24
                            // Button-shaped, matching the launcher's chips.
                            radius: Appearance.rounding.verysmall
                            color: on
                                ? Appearance.m3colors.m3primary
                                : (sHov.hovered ? Appearance.colors.colLayer2Hover
                                                : Appearance.colors.colLayer2Base)
                            border.width: on ? 0 : 1
                            border.color: Appearance.colors.colLayer0Border
                            HoverHandler { id: sHov }
                            TapHandler { onTapped: root.applySort(modelData.id) }
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
            anchors.top: toolbar.bottom
            anchors.topMargin: 26
            width: Math.min(parent.width - 80, 1400)
            height: 330
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
                // Half-width of the active card's slot (content + skew + pad),
                // so the centering band tracks the same geometry the delegate
                // reserves — the active card stays centered as it grows.
                readonly property real _activeHalf: (440 + 0.18 * (height * 0.78) + 12) / 2
                preferredHighlightBegin: width / 2 - _activeHalf
                preferredHighlightEnd:   width / 2 + _activeHalf
                highlightRangeMode: ListView.StrictlyEnforceRange
                highlightFollowsCurrentItem: true
                snapMode: ListView.SnapOneItem
                keyNavigationWraps: false
                // Jumping many items at once shouldn't crawl across every card
                // in between: a fixed short slide, not a fixed pixel speed.
                highlightMoveVelocity: -1
                highlightMoveDuration: 130
                // Two-way binding without the snap-back loop:
                // - on model growth, ListView briefly resets currentIndex
                //   to 0 internally before settling, which previously wrote
                //   that 0 back to root.activeIndex.  We guard with a flag.
                property bool _syncingFromRoot: false
                Component.onCompleted: currentIndex = root.activeIndex
                onCurrentIndexChanged: {
                    // The _syncingFromRoot guard must cover ONLY the write-back
                    // to root.activeIndex. It used to `return` from the whole
                    // handler, which also skipped focusSettle — and every
                    // wheel/keyboard step arrives through exactly that path
                    // (wheelScroll → stepActive → setActive → activeIndex →
                    // Connections → currentIndex). So the carousel moved while
                    // the info/palette panels kept showing the previous item.
                    // Dragging and tapping set currentIndex directly, without
                    // the flag, which is why it looked intermittent rather
                    // than broken.
                    if (!_syncingFromRoot
                            && currentIndex !== root.activeIndex
                            && currentIndex >= 0)
                        root.activeIndex = currentIndex
                    // Kick off client-side palette extraction + metadata
                    // read for items without a Wallhaven-provided palette
                    // (Reddit/local). Runs however the index changed.
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

                // ── Wheel → step the carousel ─────────────────────────
                // A WheelHandler only ever looks at ONE axis (orientation,
                // default Vertical), so a single handler silently ignored the
                // other wheel — hence "I can only scroll in one direction".
                // Two handlers, one per axis: the vertical (middle) wheel and
                // a horizontal/tilt wheel both drive the same horizontal step.
                //
                // Stepping goes through root.activeIndex (clamped) rather than
                // increment/decrementCurrentIndex so both directions behave
                // identically and the detail panels follow along.
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
                // Middle-click and drag to pan through the wallpapers, with a
                // closed-hand cursor while dragging.
                DragHandler {
                    id: panDrag
                    target: null
                    acceptedButtons: Qt.MiddleButton
                    cursorShape: Qt.ClosedHandCursor
                    property int startIndex: 0
                    // One wallpaper per ~90 px dragged (either axis, so a
                    // vertical drag pans the horizontal strip too).
                    readonly property real pxPerItem: 90
                    onActiveChanged: {
                        // root, not carousel: the accumulator is declared on
                        // root, so this cleared a property the ListView does
                        // not have and the real leftover survived the drag.
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
                    // The slot has to RESERVE the space the content actually
                    // occupies, or the 440-wide active card overflows its old
                    // fixed 120 slot and covers its neighbours. Content width
                    // plus the parallelogram's horizontal skew spread
                    // (0.18 · frameHeight) plus a little breathing room.
                    readonly property real frameHeight: carousel.height * 0.78
                    readonly property real skewPad: 0.18 * frameHeight
                    width: (active ? 440 : 110) + skewPad + 12
                    height: carousel.height
                    z: active ? 10 : 1
                    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                    // (Colored aura blob removed at user request — was three
                    // overlapping circles behind the focused parallelogram.)

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
                                // Thumbs are small now (≤1280px), so caching them
                                // avoids a full re-decode every time a card scrolls
                                // back into view.
                                cache: true
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

                        // Favourite toggle — top-right of the focused card.
                        // Without this the favourites filter had no way to
                        // ever have anything in it.
                        Rectangle {
                            id: favBtn
                            visible: index === carousel.currentIndex
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 6
                            width: 26; height: 26; radius: 13
                            readonly property bool on: WallpaperHub.isFavorite(modelData?.path ?? "")
                            color: Qt.alpha("black", favHov.hovered ? 0.75 : 0.5)
                            HoverHandler { id: favHov }
                            TapHandler {
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
                        // Middle-click → apply this one straight away, without
                        // having to focus it first.
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
                            id: gridLoadingDot
                            anchors.centerIn: parent
                            width: 10; height: 10; radius: 5
                            visible: gridImg.status === Image.Loading
                            color: Appearance.m3colors.m3primary
                            opacity: 0.55
                            SequentialAnimation on scale {
                                // An animation's `parent` is null — this used to
                                // log a TypeError on every evaluation.
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

        // ── Detail row: metadata | search | post ─────────────────────
        // Three equal-height panels in one centered row BELOW the carousel:
        // the focused image's metadata (left), the search field with its
        // completion entries beneath it (middle), and the focused post's
        // swipeable images with dot indicators (right). Each has its own
        // background; they share the same height and gap.
        Item {
            id: detailRow
            readonly property var md: (root.viewLayout === "carousel"
                && root.activeIndex >= 0 && root.activeIndex < root.filtered.length)
                ? root.filtered[root.activeIndex] : null
            readonly property var meta: root.metaFor(md)
            onMdChanged: if (md) focusSettle.restart()
            readonly property bool hasSearch: root.activeSource !== "local"
            // Sized to the launcher's type scale — the old 232/9px
            // panels read as fine print next to the bar above them.
            readonly property real panelH: 286

            visible: root.viewLayout === "carousel"
                     && (root.filtered.length > 0 || md !== null)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            implicitHeight: panelH

            // Slide-down entrance: the search row drops in from above and
            // fades in each time skwd opens (the content reloads per open).
            property real slideY: -46
            opacity: 0
            transform: Translate { y: detailRow.slideY }
            Component.onCompleted: entranceAnim.start()
            ParallelAnimation {
                id: entranceAnim
                NumberAnimation {
                    target: detailRow; property: "slideY"
                    from: -46; to: 0; duration: 440; easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: detailRow; property: "opacity"
                    from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic
                }
            }

            readonly property var rows: {
                const m = detailRow.md
                if (!m) return []
                const meta = detailRow.meta
                const local = (m.path || "").startsWith("/")
                return [
                    { k: qsTr("Title"),      v: m.title || "—" },
                    { k: qsTr("Source"),     v: (m.source || "—")
                        + (m.subreddit ? "  ·  r/" + m.subreddit : "") },
                    { k: qsTr("Type"),       v: (m.kind || "pic").toUpperCase() },
                    { k: qsTr("Resolution"), v: meta && meta.dims ? meta.dims
                        : (local ? "…" : qsTr("(remote)")) },
                    { k: qsTr("Format"),     v: meta && meta.format ? meta.format
                        : (local ? "…" : "—") },
                    { k: qsTr("Size"),       v: meta ? root.formatBytes(meta.bytes)
                        : (local ? "…" : "—") },
                    { k: qsTr("ID"),         v: m.id || "—" },
                    { k: qsTr("Path"),       v: m.path || "—" },
                ]
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.pairGap

                // 1 ── METADATA ─────────────────────────────────────────
                Rectangle {
                    width: 330
                    height: detailRow.panelH
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer0
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    clip: true

                    // Right-click the metadata for the same menu the cards
                    // have — including the KIO properties dialog.
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: (eventPoint) => {
                            const md = detailRow.md
                            if (!md) return
                            const g = parent.mapToItem(root, eventPoint.position.x, eventPoint.position.y)
                            skwdCtxMenu.popup(g.x, g.y, root.menuForCarouselItem(md))
                        }
                    }

                    Column {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 6
                        StyledText {
                            text: qsTr("IMAGE INFO")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2
                            color: Appearance.colors.colPrimary
                        }
                        Rectangle {
                            width: parent.width; height: 1
                            color: Appearance.colors.colLayer0Border
                        }
                        Repeater {
                            model: detailRow.rows
                            delegate: RowLayout {
                                required property var modelData
                                width: parent.width
                                spacing: 8
                                StyledText {
                                    text: modelData.k
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    Layout.preferredWidth: 82
                                    Layout.alignment: Qt.AlignTop
                                }
                                StyledText {
                                    text: modelData.v
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                    elide: Text.ElideMiddle
                                    maximumLineCount: 2
                                    wrapMode: Text.WrapAnywhere
                                    Layout.fillWidth: true
                                }
                            }
                        }
                        StyledText {
                            width: parent.width
                            visible: detailRow.md === null
                            text: qsTr("Focus an image in the carousel.")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // 2 ── SEARCH + entries ─────────────────────────────────
                Rectangle {
                    id: searchPanel
                    width: 360
                    height: detailRow.panelH
                    // Hidden while the launcher is open — the launcher's bar
                    // owns search then (its subreddit dropdown replaces this).
                    visible: detailRow.hasSearch && !root.embedded && !GlobalStates.overviewOpen
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer0
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    clip: true

                    StyledText {
                        id: searchHdr
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 12
                        text: qsTr("SEARCH")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        font.letterSpacing: 1.2
                        color: Appearance.colors.colPrimary
                    }

                    ToolbarTextField {
                        id: searchPill
                        anchors.top: searchHdr.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: 8
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        font.pixelSize: Appearance.font.pixelSize.small
                        placeholderText: root.activeSource === "reddit"
                            ? qsTr("Search or type a subreddit…")
                            : qsTr("Search wallhaven…")

                        // Two-way sync with root.query, guarded to avoid a loop
                        // and to reflect programmatic changes (restore, pick).
                        text: root.query
                        onTextChanged: if (root.query !== text) root.query = text
                        Connections {
                            target: root
                            function onQueryChanged() {
                                if (searchPill.text !== root.query) searchPill.text = root.query
                            }
                        }

                        onAccepted: {
                            if (root.completionsOpen && root.completionIndex >= 0) {
                                root.applyCompletion(root.completionIndex)
                            } else if (root.activeSource === "reddit") {
                                root.completionsOpen = false
                                root.syncReddit()
                            } else {
                                root.refresh()
                            }
                        }
                        Keys.onPressed: event => {
                            const open = root.completionsOpen && root.redditCompletions.length > 0
                            if (event.key === Qt.Key_Down && open) {
                                root.completionIndex =
                                    (root.completionIndex + 1) % root.redditCompletions.length
                                event.accepted = true
                            } else if (event.key === Qt.Key_Up && open) {
                                const n = root.redditCompletions.length
                                root.completionIndex = (root.completionIndex - 1 + n) % n
                                event.accepted = true
                            } else if (event.key === Qt.Key_Escape) {
                                if (root.completionsOpen) root.completionsOpen = false
                                else root.close()
                                event.accepted = true
                            } else {
                                event.accepted = false
                            }
                        }
                    }

                    // Completion entries, inline below the search field.
                    ListView {
                        id: completionList
                        anchors.top: searchPill.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.topMargin: 8
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.bottomMargin: 8
                        visible: root.activeSource === "reddit"
                            && root.completionsOpen && root.redditCompletions.length > 0
                        clip: true
                        model: root.redditCompletions
                        delegate: Rectangle {
                            id: compRow
                            required property var modelData
                            required property int index
                            readonly property bool current: index === root.completionIndex
                            width: completionList.width
                            height: 30
                            radius: Appearance.rounding.small
                            color: current || rowHov.hovered
                                ? Appearance.colors.colLayer2Hover
                                : "transparent"
                            HoverHandler {
                                id: rowHov
                                onHoveredChanged: if (hovered) root.completionIndex = compRow.index
                            }
                            TapHandler { onTapped: root.applyCompletion(compRow.index) }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6
                                MaterialSymbol {
                                    text: "tag"
                                    iconSize: 13
                                    color: Appearance.colors.colSubtext
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                StyledText {
                                    text: compRow.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer1
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Rectangle {
                                    visible: compRow.modelData.nsfw
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitHeight: 15
                                    implicitWidth: nsfwLabel.implicitWidth + 8
                                    radius: 4
                                    color: Qt.alpha(Appearance.m3colors.m3error, 0.18)
                                    StyledText {
                                        id: nsfwLabel
                                        anchors.centerIn: parent
                                        text: "18+"
                                        font.pixelSize: 8
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0.5
                                        color: Appearance.m3colors.m3error
                                    }
                                }
                                StyledText {
                                    text: root.formatSubs(compRow.modelData.subs)
                                    font.pixelSize: 10
                                    color: Appearance.colors.colSubtext
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                        }
                    }

                    // Hint when there are no entries to show.
                    StyledText {
                        anchors.top: searchPill.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: 14
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        visible: !completionList.visible
                        text: root.activeSource === "reddit"
                            ? qsTr("Type a subreddit — matches appear here.")
                            : qsTr("Type to search wallhaven, Enter to run.")
                        font.pixelSize: 10
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // 3 ── POST (swipeable + dots) ──────────────────────────
                Item {
                    id: postPanel
                    width: 400
                    height: detailRow.panelH
                    readonly property var md: detailRow.md
                    readonly property var images: {
                        const m = postPanel.md
                        if (!m) return []
                        if (Array.isArray(m.gallery) && m.gallery.length > 0) return m.gallery
                        const one = m.full || m.thumb || ""
                        return one.length ? [one] : []
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer0
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        clip: true

                        Column {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            StyledText {
                                text: postPanel.images.length > 1
                                    ? qsTr("POST · %1 images").arg(postPanel.images.length)
                                    : qsTr("POST")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Bold
                                font.letterSpacing: 1.2
                                color: Appearance.colors.colPrimary
                            }

                            StyledText {
                                width: parent.width
                                height: parent.height - 42
                                visible: postPanel.images.length === 0
                                text: qsTr("Focus an image to see its post")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                wrapMode: Text.WordWrap
                            }

                            ListView {
                                id: postView
                                visible: postPanel.images.length > 0
                                width: parent.width
                                height: parent.height - 42
                                orientation: ListView.Horizontal
                                snapMode: ListView.SnapOneItem
                                highlightRangeMode: ListView.StrictlyEnforceRange
                                boundsBehavior: Flickable.StopAtBounds
                                clip: true
                                model: postPanel.images
                                Connections {
                                    target: postPanel
                                    function onMdChanged() { postView.currentIndex = 0 }
                                }
                                delegate: Rectangle {
                                    required property var modelData
                                    width: postView.width
                                    height: postView.height
                                    radius: Appearance.rounding.small
                                    color: Appearance.colors.colLayer2
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        source: modelData
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        cache: true
                                        sourceSize.width: 640
                                    }
                                }
                            }

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 5
                                visible: postPanel.images.length > 1
                                Repeater {
                                    model: postPanel.images.length
                                    delegate: Rectangle {
                                        required property int index
                                        readonly property bool current: index === postView.currentIndex
                                        width: current ? 16 : 6
                                        height: 6
                                        radius: 3
                                        color: current ? Appearance.colors.colPrimary
                                                       : Appearance.colors.colLayer2
                                        Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        Behavior on color { ColorAnimation { duration: 130 } }
                                        TapHandler { onTapped: postView.currentIndex = index }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
