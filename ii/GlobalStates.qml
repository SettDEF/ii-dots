import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    property bool barOpen: true
    property bool crosshairOpen: false
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    property bool mediaControlsOpen: false
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool oskOpen: false
    property bool touchpadOpen: false
    property var oskWindow: null
    property var touchpadWindow: null
    // Force the dock to reveal even when it would otherwise be hidden.
    // Toggled by the bottom-edge gesture.
    property bool dockOpen: false
    // Tablet mode lives in Config.options.tabletMode (persisted across reloads).
    // This is a read-only mirror so existing GlobalStates consumers keep working.
    readonly property bool tabletMode: Config.options?.tabletMode ?? false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool sessionOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool wallpaperSelectorOpen: false
    property bool workspaceShowNumbers: false
    property bool hudOpen: false
    // Active HUD main tab (0..4). Lifted out of HudContent so the bar
    // can host the tab selector externally — while the HUD is open the
    // bar swaps its Workspaces widget for a HUD-tab PillTabBar.
    property int hudActiveTab: 0
    // Per-main-tab sub-tab indices — also lifted out so the bar can
    // render the sub-tab selector as a blob tray fused below the bar.
    property int hudPerfTab: 0
    property int hudGamingTab: 0
    property int hudMediaTab: 0
    property int hudScreenTab: 0
    // Essentials-tab connectivity radar overlay + its mode.
    property bool essentialsRadarOpen: false
    property string essentialsRadarMode: "bt" // "bt" | "wifi"
    property bool cornerPopupOpen: false
    property bool shelfOpen: false
    property string shelfTab: "files" // "files" | "battle" | "media"
    // Active Battle sub-tab path index. -1 = "Manage". Lifted from
    // ShelfContent so the bar can render the sub-tabs externally.
    property int shelfBattleIndex: 0
    // Active Files sub-tab id (explorer | recent | torrents). Lifted from
    // ShelfContent so the choice persists across shelf open/close cycles
    // (ShelfContent is recreated per-monitor on visibility transitions).
    property string shelfFilesSubTab: "explorer"
    // Active filter for the Torrents sub-tab (lifted from ShelfTorrents.qml
    // so the bar can render the filter chips on its right cluster the same
    // way it does for Battle).
    property string shelfTorrentsFilter: "all"  // all | active | seeding | paused | error
    // Cross-module triggers — the bar's Wi-Fi / Bluetooth indicator icons
    // increment these to ask the right sidebar to open its respective
    // popup. The sidebar treats a value change as a one-shot signal.
    property int openWifiDialogRequest: 0
    property int openBluetoothDialogRequest: 0
    // Floating connectivity radars. Bluetooth pins to the left, Wi-Fi to
    // the right, both can be open at once. The tab strip at the top of
    // the popup PanelWindow toggles each one independently.
    property bool connectivityBluetoothOpen: false
    property bool connectivityWifiOpen: false
    // Aggregate kept for backward-compat with anything else that watches
    // a single "any-popup" flag.
    readonly property bool connectivityPopupOpen:
        connectivityBluetoothOpen || connectivityWifiOpen
    property string connectivityPopupMode: "bt"   // "wifi" | "bt" (legacy)
    property bool kbPickerOpen: false        // XKB layout picker (opened from the OSK chips)
    property bool kbSettingsOpen: false      // Keyboard settings popup (repeat rate, etc — opened from the OSK)
    property bool wallTuneOpen: false
    property bool skwdWallOpen: false
    property bool wallpaperAdjusterOpen: false
    // Schedule the adjuster to open after a short delay (lets switchwall
    // push the new wallpaperPath into Config first). Lives on the
    // GlobalStates singleton so panel teardowns can't kill the timer.
    function requestAdjusterOpen(delayMs) {
        _adjusterRequestTimer.interval = delayMs || 700
        _adjusterRequestTimer.restart()
    }
    Timer {
        id: _adjusterRequestTimer
        interval: 700
        repeat: false
        onTriggered: root.wallpaperAdjusterOpen = true
    }
    property bool screenDrawOpen: false      // legacy — kept so any stale binding still resolves
    property bool screenDrawFullOpen: false  // fullscreen drawing overlay
    // Set by the screenDrawToggle shortcut to ask SidebarLeft to switch
    // to the Draw tab the next time it opens. Cleared after consumption.
    property bool sidebarLeftFocusDraw: false
    property bool sidebarLeftFocusAi: false
    property string sidebarLeftActiveTab: "intelligence"
    signal requestSidebarLeftTab(string tabId)
    // Shared drawing state — owned here so the sidebar toolbar and the
    // fullscreen overlay write/read the same tool & color.
    property string drawTool: "pen"          // pen | brush | highlighter | eraser | cursor
    property color  drawColor: "#ff5a5a"
    // Pulsed signals from the sidebar toolbar — ScreenDrawContent listens
    // for these and forwards them to its canvas while the overlay is open.
    signal drawUndo()
    signal drawRedo()
    signal drawClear()
    signal drawSave()
    property bool suspendingOpen: false      // suspend-in-progress popup
    property bool screenshotEditorOpen: false
    property string screenshotEditorPath: "" // image to load when opened
    property string wallTransition: "slide" // "fade" | "slide" | "zoom" | "wipe"

    // ── Exclusive popup manager ───────────────────────────────────────
    // Names of properties that represent main popups which should never
    // overlap. Opening any of these auto-closes the others.
    // Excluded on purpose: bar, OSDs (volume/brightness), regionSelector,
    // OSK, screen lock state, modifier state — these are transient feedback,
    // overlays, or system layers that legitimately coexist.
    readonly property var _exclusivePopups: [
        "sidebarLeftOpen",
        "sidebarRightOpen",
        "mediaControlsOpen",
        "overviewOpen",
        "searchOpen",
        "sessionOpen",
        "shelfOpen",
        "wallpaperSelectorOpen",
        "wallTuneOpen",
        "skwdWallOpen",
        "wallpaperAdjusterOpen",
        "overlayOpen",
        "crosshairOpen",
        "cornerPopupOpen",
        "hudOpen",
    ]

    // Reentry guard so closing siblings doesn't recurse.
    property bool _enforcing: false

    function closeOthers(opened) {
        if (root._enforcing) return
        root._enforcing = true
        for (let i = 0; i < root._exclusivePopups.length; i++) {
            const name = root._exclusivePopups[i]
            if (name !== opened && root[name] === true) {
                root[name] = false
            }
        }
        root._enforcing = false
    }

    Timer {
        id: selectorToHubTimer
        interval: 200
        repeat: false
        onTriggered: {
            console.log("[GlobalStates] selectorToHubTimer triggered, setting skwdWallOpen = true");
            root.skwdWallOpen = true
        }
    }

    function openHubFromSelector() {
        console.log("[GlobalStates] openHubFromSelector called, setting wallpaperSelectorOpen = false and starting timer");
        root.wallpaperSelectorOpen = false
        selectorToHubTimer.start()
    }

    onSidebarLeftOpenChanged:        if (sidebarLeftOpen)        closeOthers("sidebarLeftOpen")
    onMediaControlsOpenChanged:      if (mediaControlsOpen)      closeOthers("mediaControlsOpen")
    onOverviewOpenChanged:           if (overviewOpen)           closeOthers("overviewOpen")
    onSearchOpenChanged:             if (searchOpen)             closeOthers("searchOpen")
    onSessionOpenChanged:            if (sessionOpen)            closeOthers("sessionOpen")
    onShelfOpenChanged:              if (shelfOpen)              closeOthers("shelfOpen")
    onWallpaperSelectorOpenChanged:  if (wallpaperSelectorOpen)  closeOthers("wallpaperSelectorOpen")
    onWallTuneOpenChanged:           if (wallTuneOpen)           closeOthers("wallTuneOpen")
    onSkwdWallOpenChanged: {
        console.log("[GlobalStates] skwdWallOpen changed to: " + skwdWallOpen + "\nStack trace:\n" + new Error().stack);
        if (skwdWallOpen) closeOthers("skwdWallOpen")
    }
    onOverlayOpenChanged:            if (overlayOpen)            closeOthers("overlayOpen")
    onCrosshairOpenChanged:          if (crosshairOpen)          closeOthers("crosshairOpen")
    onCornerPopupOpenChanged:        if (cornerPopupOpen)        closeOthers("cornerPopupOpen")
    onHudOpenChanged: {
        if (hudOpen) {
            closeOthers("hudOpen")
            // Every tab opens on its first sub-tab (Screen Time → Today,
            // Gaming → Overview, Media → Overview), like the repo popup.
            hudScreenTab = 0
            hudGamingTab = 0
            hudMediaTab = 0
        } else {
            essentialsRadarOpen = false
        }
    }

    onSidebarRightOpenChanged: {
        if (GlobalStates.sidebarRightOpen) {
            closeOthers("sidebarRightOpen")
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }

    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"

        onPressed: {
            root.superDown = true
        }
        onReleased: {
            root.superDown = false
        }
    }
}
