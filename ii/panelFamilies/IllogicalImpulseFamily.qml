import QtQuick
import Quickshell

import qs
import qs.modules.common
import qs.modules.ii.background
import qs.modules.ii.bar
import qs.modules.ii.cheatsheet
import qs.modules.ii.display
import qs.modules.ii.statsHud
import qs.modules.ii.audio
import qs.modules.ii.clipboardToast
import qs.modules.ii.iris
import qs.modules.ii.walltune
import qs.modules.ii.dock
import qs.modules.ii.lock
import qs.modules.ii.mediaControls
import qs.modules.ii.notificationPopup
import qs.modules.ii.onScreenDisplay
import qs.modules.ii.onScreenKeyboard
import qs.modules.ii.onScreenTouchpad
import qs.modules.ii.overview
import qs.modules.ii.polkit
import qs.modules.ii.regionSelector
import qs.modules.ii.rog
import qs.modules.ii.screenCorners
import qs.modules.ii.sessionScreen
import qs.modules.ii.sidebarLeft
import qs.modules.ii.sidebarRight
import qs.modules.ii.overlay
import qs.modules.ii.verticalBar
import qs.modules.ii.wallpaperSelector
import qs.modules.ii.hud
import qs.modules.ii.connectivityPopup
import qs.modules.ii.cornerPopup
import qs.modules.ii.shelf
import qs.modules.ii.keybindsHint
import qs.modules.ii.skwdWall
import qs.modules.ii.wallpaperAdjuster
import qs.modules.ii.desktopIcons
import qs.modules.ii.mouseMenu
import qs.modules.ii.kinetix
import qs.modules.ii.systemHub
import qs.modules.ii.screenDraw
import qs.modules.ii.screenshotEditor
import qs.modules.ii.mouseMenu
import qs.modules.ii.touchEdges
// import qs.modules.ii.touchGestures

Scope {
    // Always-loaded GlobalShortcuts for popup panels — registers with Hypr at
    // startup so the keybinds work even when the panels themselves are unloaded.
    Shortcuts {}
    // Always-loaded diagnostic IPC (zero idle cost). See Diagnostics.qml.
    Diagnostics {}

    // ── Always-loaded (visible UI / event-driven, must respond instantly) ──
    // In tablet mode, hide the bar and show the dock instead — touch-first
    // layout. Mouse mode keeps the original bar/dock config.
    PanelLoader {
        extraCondition: !Config.options.bar.vertical && !Config.options.tabletMode
        component: Bar {}
    }
    PanelLoader { component: Background {} }
    // Desktop icons (KDE-style). The inner Loader self-gates on
    // Config.options.desktop.icons.enable, so the PanelWindow stays cheap
    // while the toggle is off (no FolderListModel, no delegates).
    PanelLoader {
        extraCondition: Config.options.desktop.icons.enable
        component: DesktopIcons {}
    }
    PanelLoader {
        extraCondition: Config.options.dock.enable || Config.options.tabletMode
        component: Dock {}
    }
    PanelLoader { component: Lock {} }
    PanelLoader { component: MediaControls {} }
    PanelLoader { component: NotificationPopup {} }
    PanelLoader { component: OnScreenDisplay {} }
    PanelLoader { component: LayoutOsd {} }
    PanelLoader { component: OnScreenKeyboard {} }
    PanelLoader { component: OnScreenTouchpad {} }
    PanelLoader { component: Overlay {} }
    PanelLoader { component: Polkit {} }
    PanelLoader { component: RegionSelector {} }
    PanelLoader { component: ScreenCorners {} }
    PanelLoader { component: SessionScreen {} }
    PanelLoader { extraCondition: Config.options.bar.vertical; component: VerticalBar {} }
    LazyPanelLoader {
        isOpen: GlobalStates.hudOpen
        idleMs: 30 * 1000        // unload 30 s after close
        component: Hud {}
    }
    LazyPanelLoader {
        isOpen: GlobalStates.cornerPopupOpen
        idleMs: 30 * 1000
        component: CornerPopup {}
    }
    LazyPanelLoader {
        isOpen: GlobalStates.connectivityBluetoothOpen
                || GlobalStates.connectivityWifiOpen
        idleMs: 30 * 1000
        component: ConnectivityPopup {}
    }
    PanelLoader { component: KeybindsHint {} }
    // Touch-only edge swipe handles.
    //
    // Twice now this made the bar unclickable, because "off" was implemented
    // as an empty input mask on a live Overlay-layer surface and the off
    // switch was the LATCHING InputMode singleton. Off is now the surface not
    // being created at all — the same shape TouchGestures below already uses,
    // and the one state that cannot eat a click by construction.
    PanelLoader {
        extraCondition: Appearance.touchUi
        component: TouchEdges {}
    }
    // Fullscreen multi-finger / corner gestures — tablet mode only,
    // because its input region covers the whole screen and would block
    // mouse hover otherwise.
    // PanelLoader {
    //     extraCondition: Config.options.tabletMode
    //     component: TouchGestures {}
    // }
    // Cheatsheet has its own internal lazy loader (active=false by default).
    PanelLoader { component: Cheatsheet {} }

    // Nexus, Overview, SidebarLeft still keep internal-state shortcuts → eager.
    // SidebarRight had its IpcHandler/GlobalShortcuts lifted to Shortcuts.qml
    // so it can be smart-loaded.
    PanelLoader { component: Overview {} }
    PanelLoader { component: SidebarLeft {} }
    LazyPanelLoader {
        isOpen: GlobalStates.sidebarRightOpen
        component: SidebarRight {}
    }
    // Smart-loaded popup panels — heavy ones unload aggressively (30 s
    // after close).  Their toggle shortcuts live in Shortcuts.qml so the
    // keybinds stay live and re-instantiate the panel on next open.
    PanelLoader { component: WallpaperSelector {} }
    LazyPanelLoader { isOpen: GlobalStates.kbPickerOpen;          idleMs: 30 * 1000; component: KeyboardLayoutPicker {} }
    LazyPanelLoader { isOpen: GlobalStates.kbSettingsOpen;        idleMs: 30 * 1000; component: KeyboardSettings {} }
    LazyPanelLoader { isOpen: GlobalStates.wallTuneOpen;          idleMs: 30 * 1000; component: WallTune {} }
    // Visibility-driven like the connectivity popup, not gated by a Loader:
    // it drives its own `visible` per screen, so it wants to exist already.
    PanelLoader { component: AppColors {} }
    PanelLoader { component: AudioPluginsDialog {} }
    LazyPanelLoader { isOpen: GlobalStates.rogPowerOpen;          idleMs: 30 * 1000; component: RogPower {} }
    PanelLoader { component: SkwdWall {} }
    LazyPanelLoader { isOpen: GlobalStates.wallpaperAdjusterOpen; idleMs: 30 * 1000; component: WallpaperAdjuster {} }
    PanelLoader { component: MouseMenu {} }
    PanelLoader { component: KinetiX {} }
    PanelLoader { component: DisplaySettings {} }
    PanelLoader { component: MonitorSafetyDialog {} }
    PanelLoader { component: SystemHub {} }
    PanelLoader { component: StatsHud {} }
    PanelLoader { component: StatsHudSettings {} }
    PanelLoader { component: AudioSettings {} }
    PanelLoader { component: IrisSettings {} }
    ClipboardToast {}
    PanelLoader { component: WallEffectPanel {} }
    // Window-scope per-app effects: click-through surfaces over app windows.
    PanelLoader { component: AppDisplayOverlays {} }
    LazyPanelLoader { isOpen: GlobalStates.gestureMenuOpen;           idleMs: 30 * 1000; component: GestureMenu {} }
    // Shelf is rendered inline by Bar.qml — no standalone PanelLoader needed.
    LazyPanelLoader {
        isOpen: GlobalStates.screenDrawFullOpen
        idleMs: 30 * 1000
        component: ScreenDraw {}
    }
    // Stays as PanelLoader so its IpcHandler is always reachable. The heavy
    // PanelWindow inside is still gated on screenshotEditorOpen.
    PanelLoader { component: ScreenshotEditor {} }
}


