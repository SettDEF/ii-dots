pragma Singleton

import QtQuick
import Quickshell

/**
 * Shared state for the launcher's wallpaper-hub mode (the skwd controls that
 * get pulled into the search bar and the SearchWallpapers grid below it).
 * Kept tiny and separate from SkwdWallContent so the launcher never has to
 * instantiate that whole fullscreen component.
 */
Singleton {
    id: root

    // Last search text and the sub actually opened, so reopening the launcher
    // restores both.
    property string lastQuery: ""
    property string lastSub: ""

    // reddit | local | wallhaven | videos
    property string source: "reddit"
    // all | pic | vid | we
    property string mediaType: "all"
    // Favourites-only filter.
    property bool favoritesOnly: false
    // Wallhaven palette codes, comma separated. "" = no filter. The same
    // string skwd's filter panel edits.
    property string colors: ""
    function toggleColor(wh) {
        const arr = root.colors.length > 0 ? root.colors.split(",") : []
        const i = arr.indexOf(wh)
        if (i >= 0) arr.splice(i, 1)
        else arr.push(wh)
        root.colors = arr.join(",")
    }
    function colorSelected(wh) {
        return root.colors.split(",").indexOf(wh) >= 0
    }

    // Favourites by absolute path, shared by the bar, the cards and the filter.
    property var favoritePaths: ({})
    function isFavorite(path) {
        return !!(path && root.favoritePaths[path])
    }
    function toggleFavorite(path) {
        if (!path) return
        const m = Object.assign({}, root.favoritePaths)
        if (m[path]) delete m[path]
        else m[path] = true
        root.favoritePaths = m
    }

    // Navigate an ALREADY-open skwd to a sub (Persistent restore only runs on
    // a fresh open).
    signal navigate(string sub)

    // Enter in the launcher's skwd search: open the highlighted entry, or the
    // typed text.
    signal submit()

    // Dropdown keyboard nav. -1 = nothing highlighted, so Enter uses the typed
    // text. SearchWallpapers clamps against the live result count.
    property int completionIndex: -1
    signal selectNext()
    signal selectPrev()

    // ←/→ from the launcher (which holds keyboard focus) step skwd's carousel.
    signal carouselStep(int delta)

    // Runtime controls from the launcher bar → the open skwd window.
    signal reload()        // re-fetch / refresh the current sub

    // ── Filter / sort ────────────────────────────────────────────────
    // One state, two renderings: the launcher's dropdown and skwd's panel.
    property bool filterOpen: false

    // The wallpaper skwd currently has focused, and whatever has been
    // resolved about it. Published here so the launcher's details dropdown
    // can render the same panel skwd does without reaching into skwd.
    property var focusedItem: null
    property var focusedMeta: null

    // Details drawer — the image-info and post panels in skwd's carousel.
    // Kept here rather than in SkwdWallContent so the launcher bar and skwd's
    // own toolbar drive one state instead of each owning a copy.
    property bool detailsOpen: false

    // How much vertical room the launcher's details dropdown is taking right
    // now. skwd sits directly under the launcher and adds this to its top
    // margin, so opening the dropdown pushes the wallpapers down instead of
    // the panel landing on top of them. Animated by the launcher, so skwd's
    // binding follows it smoothly for free.
    property real detailsHeight: 0
    // "" = AUTO: skwd cycles to the next sort as each one dries up. Otherwise
    // the id (path + query) of a forced listing.
    property string forcedSort: ""
    // Emitted after a chip is picked so skwd re-syncs on the new sort.
    signal sortPicked(string id)

    // Listing sorts, shared by skwd's fetcher (path + q) and both filter UIs.
    readonly property var redditSorts: [
        { path: "hot",           q: "",         label: "HOT"      },
        { path: "top",           q: "?t=all",   label: "TOP·all"  },
        { path: "top",           q: "?t=year",  label: "TOP·year" },
        { path: "top",           q: "?t=month", label: "TOP·mo"   },
        { path: "top",           q: "?t=week",  label: "TOP·week" },
        { path: "top",           q: "?t=day",   label: "TOP·day"  },
        { path: "new",           q: "",         label: "NEW"      },
        { path: "rising",        q: "",         label: "RISING"   },
        { path: "controversial", q: "?t=all",   label: "CTRL·all" },
        { path: "controversial", q: "?t=year",  label: "CTRL·year"},
    ]
    // AUTO + every sort, in the shape the chip rows render.
    readonly property var sortChips: [{ id: "", label: "AUTO" }].concat(
        root.redditSorts.map(s => ({ id: s.path + s.q, label: s.label })))

    // Apply the focused wallpaper (Enter).
    signal applyFocused()
    // Set by SearchWallpapers so the launcher's Enter knows whether the dropdown
    // is up (pick a sub) or dismissed (apply the focused wallpaper).
    property bool dropdownVisible: false
    // The dropdown covers skwd's carousel and would swallow its scroll, so it
    // only opens once you actually TYPE: set true when the field is filled
    // programmatically, cleared by textEdited (user input only).
    property bool dropdownSuppressed: true

    readonly property var mediaTypes: [
        { id: "all", label: "ALL" },
        { id: "pic", label: "PIC" },
        { id: "vid", label: "VID" },
        { id: "we",  label: "WE"  },
    ]

    // The same colour columns skwd draws in its top bar. `swatch` is the dot
    // colour; `wh` is the Wallhaven query code (used once wallhaven search is
    // wired — reddit/local filtering by hue is a later pass).
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

    readonly property var sources: [
        { id: "local",     icon: "folder", label: "Local"     },
        { id: "wallhaven", icon: "public", label: "Wallhaven" },
        { id: "reddit",    icon: "forum",  label: "Reddit"    },
        { id: "videos",    icon: "movie",  label: "Videos"    },
    ]
}
