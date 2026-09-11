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
    property bool rogPowerOpen: false
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
    // Sort & filter dropdown inside the launcher. Lives here rather than on
    // SearchWidget so the `/sort` command can drive it too, not just the
    // toolbar button.
    property bool launcherSortOpen: false
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool sessionOpen: false
    // Hub of every settings panel, opened from the uptime pill in the right
    // sidebar. Its own flag rather than a sidebar-local one so a keybind and
    // the IPC can reach it without the sidebar being loaded.
    property bool systemHubOpen: false
    // Mirrors Cheatsheet's own `open` (via a Synchronizer there) so the hub and
    // any keybind can reach it without holding a reference to the panel.
    property bool cheatsheetOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    // Timestamp of the last searchToggleRelease press — used to ignore the
    // phantom catchall interrupt Hyprland 0.55.4 fires on the Super press
    // itself (same-instant), while real interrupts (another key pressed
    // while holding Super) arrive later and still veto the toggle.
    property real superPressTime: 0
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
    // Published by CornerPopup so a stacked panel can sit below it instead of
    // underneath it - two surfaces at the same y read as one floating over the
    // other rather than as a stack.
    property int cornerPopupHeight: 0
    // Which corner-popup tab is showing. Lives here rather than on the popup
    // window because the bar renders the tab strip while the popup is open, so
    // both need to read and write the same value.
    property string cornerPopupTab: "media"
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
    property int openDevicesDialogRequest: 0
    // Floating connectivity radars. Bluetooth pins to the left, Wi-Fi to
    // the right, both can be open at once. The tab strip at the top of
    // the popup PanelWindow toggles each one independently.
    property bool connectivityBluetoothOpen: false
    property bool connectivityWifiOpen: false
    property bool connectivityVpnOpen: false
    // Aggregate kept for backward-compat with anything else that watches
    // a single "any-popup" flag.
    readonly property bool connectivityPopupOpen:
        connectivityBluetoothOpen || connectivityWifiOpen || connectivityVpnOpen
    property string connectivityPopupMode: "bt"   // "wifi" | "bt" (legacy)
    property bool kbPickerOpen: false        // XKB layout picker (opened from the OSK chips)
    property bool kbSettingsOpen: false      // Keyboard settings popup (repeat rate, etc — opened from the OSK)
    property bool wallTuneOpen: false
    property bool skwdWallOpen: false
    property bool wallpaperAdjusterOpen: false
    property bool mouseMenuOpen: false
    property bool kinetixOpen: false
    property bool displayOpen: false
    property bool statsHudOpen: false
    property bool statsHudEdit: false
    property bool statsHudSettingsOpen: false
    property bool audioSettingsOpen: false
    property bool irisOpen: false
    property bool wallEffectVarsOpen: false
    // Per-application colours (tinct app). A floating popup opened from
    // WallTune, dismissed by clicking away — the shape the connectivity
    // popup uses — rather than a docked panel in the settings stack.
    property bool appColorsOpen: false
    // Colour-grading values pushed from outside the display panel (the
    // launcher's `/display --saturation=1.4` and friends). The panel owns the
    // real state and watches this, so typed values and slider drags cannot
    // end up disagreeing.
    property var displayGrading: ({})
    property bool gestureMenuOpen: false
    property string gestureDirection: "None"
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
    // Ask the launcher to open with this text already in its search field.
    // skwd uses it so its controls are ALWAYS the launcher's bar — opening
    // skwd brings the launcher up in `r/…` mode rather than drawing a
    // second toolbar of its own.
    signal requestLauncherSearch(string text)
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
    // ── Stacked settings panels ─────────────────────────────────────────
    // These are NOT in _exclusivePopups: they are meant to sit side by side, so
    // opening one must not close the others. But side-by-side has a limit — the
    // screen — and past it panels were running off the left edge and piling up.
    // PanelStack decides when it is out of room and names a panel to close;
    // this maps its id back to the boolean that actually opens it.
    readonly property var _stackedPanels: ({
        "display":          "displayOpen",
        "walltune":         "wallTuneOpen",
        "kinetix":          "kinetixOpen",
        "audio":            "audioSettingsOpen",
        "iris":          "irisOpen",
        "wallEffect":       "wallEffectVarsOpen",
        "statsHudSettings": "statsHudSettingsOpen",
        "rogPower":         "rogPowerOpen"
    })

    Connections {
        target: PanelStack
        function onEvict(id) {
            const prop = root._stackedPanels[id];
            if (prop !== undefined && root[prop] === true) root[prop] = false;
        }
    }

    // True while the left sidebar is detached into a FloatingWindow. A detached
    // sidebar is an ordinary desktop window, not a layer-shell overlay, so the
    // exclusive-popup rule below must not apply to it — see closeOthers().
    property bool sidebarLeftDetached: false

    readonly property var _exclusivePopups: [
        "sidebarLeftOpen",
        "sidebarRightOpen",
        "mediaControlsOpen",
        "overviewOpen",
        "searchOpen",
        "sessionOpen",
        "shelfOpen",
        "wallpaperSelectorOpen",
        // wallTuneOpen deliberately NOT here: it is a stacked settings panel,
        // and being in both lists meant it obeyed two contradictory rules —
        // side-by-side with its neighbours, yet closed by any exclusive popup.
        // That is why it appeared to vanish at random.
        "skwdWallOpen",
        "wallpaperAdjusterOpen",
        "overlayOpen",
        "crosshairOpen",
        "cornerPopupOpen",
        "hudOpen",
    ]

    // Reentry guard so closing siblings doesn't recurse.
    property bool _enforcing: false

    // Popups that are allowed to sit open together instead of closing each
    // other. skwd is launched FROM the launcher search, so the two coexist:
    // you keep the subreddit dropdown up while browsing skwd.
    readonly property var _coexist: ({
        "skwdWallOpen": ["overviewOpen", "searchOpen"],
        "overviewOpen": ["skwdWallOpen"],
        "searchOpen":   ["skwdWallOpen"],
    })

    function closeOthers(opened) {
        if (root._enforcing) return
        root._enforcing = true
        const keep = root._coexist[opened] || []
        for (let i = 0; i < root._exclusivePopups.length; i++) {
            const name = root._exclusivePopups[i]
            // A detached left sidebar is a normal floating window, not an
            // overlay competing for the same screen space. Closing it because
            // the launcher opened made it vanish mid-conversation, which is not
            // what any other window on the desktop does.
            if (name === "sidebarLeftOpen" && root.sidebarLeftDetached) continue
            if (name !== opened && keep.indexOf(name) === -1 && root[name] === true) {
                root[name] = false
            }
        }
        // The stacked settings panels are not in _exclusivePopups, because
        // among THEMSELVES they are meant to sit side by side. But against a
        // main popup they are not special: opening the overview or a sidebar
        // should clear them exactly as it clears everything else, instead of
        // leaving settings panels floating over the thing you just opened.
        //
        // One-directional on purpose — a main popup closes these, but opening
        // one of these does not close the main popups, which is what would
        // make them mutually exclusive and break the stacking.
        for (const id in root._stackedPanels) {
            const prop = root._stackedPanels[id]
            if (prop !== opened && root[prop] === true) {
                root[prop] = false
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
    // The region selector needs the whole screen for pointer input; a stacked
    // settings panel's interactive card would eat the drag over its area.
    // Panels stay OPEN during region selection (so you can screenshot them);
    // they go input-transparent instead — each panel gates its `mask` on
    // regionSelectorOpen, so the selection drag passes straight through.
    onOverviewOpenChanged:           if (overviewOpen)           closeOthers("overviewOpen")
    onSearchOpenChanged:             if (searchOpen)             closeOthers("searchOpen")
    onSessionOpenChanged:            if (sessionOpen)            closeOthers("sessionOpen")
    onShelfOpenChanged:              if (shelfOpen)              closeOthers("shelfOpen")
    onWallpaperSelectorOpenChanged:  if (wallpaperSelectorOpen)  closeOthers("wallpaperSelectorOpen")
    // WallTune stacks now, so it must not close the other popups either.
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
