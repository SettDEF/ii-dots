// Shortcuts — always-loaded GlobalShortcut registrations for popup panels
// that are smart-loaded. Keeping the shortcuts here (instead of inside each
// panel module) means the bindings stay registered with Hyprland even when
// the heavy panel modules themselves are unloaded by LazyPanelLoader.
//
// Each shortcut just toggles a GlobalState flag; the panel reads its own
// GlobalStates.*Open binding to know when to spawn.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common

Scope {
    // ── WallTune ────────────────────────────────────────────────────────
    GlobalShortcut {
        name: "wallTuneToggle"
        description: "Toggle WallTune color panel"
        onPressed: GlobalStates.wallTuneOpen = !GlobalStates.wallTuneOpen
    }

    // ── Per-app colours ─────────────────────────────────────────────────
    GlobalShortcut {
        name: "appColorsToggle"
        description: "Toggle per-application colours panel"
        onPressed: GlobalStates.appColorsOpen = !GlobalStates.appColorsOpen
    }

    // ── ROG power & fan ──────────────────────────────────────────────────
    GlobalShortcut {
        name: "rogPowerToggle"
        description: "Toggle the ROG control panel"
        onPressed: GlobalStates.rogPowerOpen = !GlobalStates.rogPowerOpen
    }
    IpcHandler {
        target: "wallpaperRotation"
        function next(): void { WallpaperRotation.next() }
    }

    // The settings and welcome apps are separate processes, so they cannot set
    // GlobalStates themselves. This is how they reach the XKB layout picker,
    // which until now could only be opened from the on-screen keyboard's chips
    // — a path nobody finds who is not already using the OSK.
    IpcHandler {
        target: "keyboardLayout"
        function pick(): void { GlobalStates.kbPickerOpen = true }
        function current(): string { return KeyboardLayout.effectiveLayout }
        function configured(): string { return (KeyboardLayout.availableLayouts ?? []).join(",") }
    }

    IpcHandler {
        target: "gameMode"
        function toggle(): void { GameMode.toggle() }
        function status(): string { return GameMode.active ? "on" : "off" }
    }

    IpcHandler {
        target: "rog"
        function toggle(): void { GlobalStates.rogPowerOpen = !GlobalStates.rogPowerOpen }
        function open(): void   { GlobalStates.rogPowerOpen = true }
        function close(): void  { GlobalStates.rogPowerOpen = false }
    }

    // ── WallpaperSelector ───────────────────────────────────────────────
    GlobalShortcut {
        name: "wallpaperSelectorToggle"
        description: "Toggle wallpaper selector"
        onPressed: {
            if (Config.options.wallpaperSelector.useSystemFileDialog) {
                Wallpapers.openFallbackPicker(Appearance.m3colors.darkmode);
                return;
            }
            GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen
        }
    }
    GlobalShortcut {
        name: "wallpaperSelectorRandom"
        description: "Select random wallpaper in current folder"
        onPressed: Wallpapers.randomFromCurrentFolder()
    }
    IpcHandler {
        target: "wallpaperSelector"
        function toggle(): void {
            if (Config.options.wallpaperSelector.useSystemFileDialog) {
                Wallpapers.openFallbackPicker(Appearance.m3colors.darkmode);
                return;
            }
            GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen
        }
        function random(): void {
            Wallpapers.randomFromCurrentFolder();
        }
    }

    // ── skwd-wall hub ───────────────────────────────────────────────────
    GlobalShortcut {
        name: "skwdWallToggle"
        description: "Toggle skwd-wall (extended wallpaper picker)"
        onPressed: GlobalStates.skwdWallOpen = !GlobalStates.skwdWallOpen
    }
    IpcHandler {
        target: "skwdWall"
        function toggle(): void { GlobalStates.skwdWallOpen = !GlobalStates.skwdWallOpen }
        function open(): void   { GlobalStates.skwdWallOpen = true }
        function close(): void  { GlobalStates.skwdWallOpen = false }
    }

    // ── ScreenDraw ──────────────────────────────────────────────────────
    // Sidebar draw lives inside the left sidebar's Draw tab now — Super+Shift+D
    // opens the sidebar and switches to the Draw tab.
    GlobalShortcut {
        name: "screenDrawToggle"
        description: "Toggle left sidebar Draw tab"
        onPressed: {
            if (GlobalStates.sidebarLeftOpen && GlobalStates.sidebarLeftActiveTab === "draw") {
                GlobalStates.sidebarLeftOpen = false
            } else {
                GlobalStates.sidebarLeftFocusDraw = true
                GlobalStates.sidebarLeftOpen = true
                GlobalStates.requestSidebarLeftTab("draw")
            }
        }
    }
    GlobalShortcut {
        name: "screenDrawFullToggle"
        description: "Toggle fullscreen screen-draw overlay"
        onPressed: GlobalStates.screenDrawFullOpen = !GlobalStates.screenDrawFullOpen
    }

    // ── Audio recording ─────────────────────────────────────────────────
    // Lives here, not in AudioSettings.qml: the panel is unloaded while
    // closed, and a recording toggle has to work without it on screen.
    GlobalShortcut {
        name: "audioRecordToggle"
        description: "Start/stop recording system audio"
        onPressed: AudioRecorder.toggle()
    }

    // ── CornerPopup (media) ─────────────────────────────────────────────
    GlobalShortcut {
        name: "cornerPopupToggle"
        description: "Toggles the corner popup"
        onPressed: GlobalStates.cornerPopupOpen = !GlobalStates.cornerPopupOpen
    }
    GlobalShortcut {
        name: "playerNext"
        description: "Switch to next MPRIS player"
        onPressed: {
            if (PlayerService.players.length > 0)
                PlayerService.activeIndex = (PlayerService.activeIndex + 1) % PlayerService.players.length
        }
    }
    GlobalShortcut {
        name: "playerPrev"
        description: "Switch to previous MPRIS player"
        onPressed: {
            if (PlayerService.players.length > 0)
                PlayerService.activeIndex = (PlayerService.activeIndex - 1 + PlayerService.players.length) % PlayerService.players.length
        }
    }
    GlobalShortcut {
        name: "playerSkipNext"
        description: "Skip to next track on active player"
        onPressed: PlayerService.activePlayer?.next()
    }
    GlobalShortcut {
        name: "playerSkipPrev"
        description: "Skip to previous track on active player"
        onPressed: PlayerService.activePlayer?.previous()
    }

    // ── Tablet mode toggle ──────────────────────────────────────────────
    GlobalShortcut {
        name: "tabletModeToggle"
        description: "Toggle tablet mode (larger bar, auto-OSK in launcher)"
        onPressed: Config.options.tabletMode = !Config.options.tabletMode
    }
    IpcHandler {
        target: "tablet"
        function toggle(): void { Config.options.tabletMode = !Config.options.tabletMode }
        function on():     void { Config.options.tabletMode = true }
        function off():    void { Config.options.tabletMode = false }
    }

    // While in tablet mode, opening the overview search auto-shows the
    // on-screen keyboard, and hides it again on close.
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (!Config.options.tabletMode) return
            GlobalStates.oskOpen = GlobalStates.overviewOpen
        }
    }

    // (Auto-enable on touch removed — was getting stuck on without an easy
    // way to flip back. Tablet mode is now manual: shortcut, IPC, or the
    // quick toggle in the right sidebar.)

    // ── On-screen touchpad ──────────────────────────────────────────────
    GlobalShortcut {
        name: "touchpadToggle"
        description: "Toggle on-screen virtual touchpad"
        onPressed: GlobalStates.touchpadOpen = !GlobalStates.touchpadOpen
    }
    IpcHandler {
        target: "touchpad"
        function toggle(): void { GlobalStates.touchpadOpen = !GlobalStates.touchpadOpen }
        function open(): void   { GlobalStates.touchpadOpen = true }
        function close(): void  { GlobalStates.touchpadOpen = false }
    }

    // ── HUD ─────────────────────────────────────────────────────────────
    GlobalShortcut {
        name: "hudToggle"
        description: "Toggle HUD panel"
        onPressed: GlobalStates.hudOpen = !GlobalStates.hudOpen
    }
    IpcHandler {
        target: "hud"
        function toggle(): void { GlobalStates.hudOpen = !GlobalStates.hudOpen }
        function open(): void   { GlobalStates.hudOpen = true }
        function close(): void  { GlobalStates.hudOpen = false }
    }

    // ── Start Menu (modules/ii/startMenu/) ────────────────────────────────
    // Registered here rather than inside the module itself: it's loaded by a
    // LazyPanelLoader, and commit b7c8ffd found out the hard way that a
    // keybind living inside a lazily-unloaded panel stops firing once the
    // panel unloads. Keeping it here means Super+Space and the IPC target
    // stay live even while the menu itself is not instantiated.
    GlobalShortcut {
        name: "startMenuToggle"
        description: "Toggle the Start Menu"
        onPressed: GlobalStates.startMenuOpen = !GlobalStates.startMenuOpen
    }
    IpcHandler {
        target: "startMenu"
        function toggle(): void { GlobalStates.startMenuOpen = !GlobalStates.startMenuOpen }
        function open(): void   { GlobalStates.startMenuOpen = true }
        function close(): void  { GlobalStates.startMenuOpen = false }
    }

    // ── Shelf — the working shortcut + IpcHandler live in modules/ii/bar/Bar.qml
    //     because Bar renders the shelf inline. Don't add a duplicate here:
    //     duplicate GlobalShortcut names get shadowed by Hyprland.

    // ── SidebarRight ────────────────────────────────────────────────────
    GlobalShortcut {
        name: "sidebarRightToggle"
        description: "Toggles right sidebar on press"
        onPressed: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
    }
    GlobalShortcut {
        name: "sidebarRightOpen"
        description: "Opens right sidebar on press"
        onPressed: GlobalStates.sidebarRightOpen = true
    }
    GlobalShortcut {
        name: "sidebarRightClose"
        description: "Closes right sidebar on press"
        onPressed: GlobalStates.sidebarRightOpen = false
    }
    IpcHandler {
        target: "sidebarRight"
        function toggle(): void { GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen }
        function close(): void  { GlobalStates.sidebarRightOpen = false }
        function open(): void   { GlobalStates.sidebarRightOpen = true }
    }

    // ── Devices ─────────────────────────────────────────────────────────
    // Lives here rather than next to the dialogs it opens: those are children
    // of SidebarRightContent, which is behind a Loader, and a handler that only
    // exists while its panel is open is a handler that can never open it.
    IpcHandler {
        target: "devices"
        function open(): void {
            GlobalStates.sidebarRightOpen = true
            GlobalStates.openDevicesDialogRequest++
        }
        /// Straight to one device's controls, by name as the list shows it.
        function controls(name: string): void {
            GlobalStates.sidebarRightOpen = true
            GlobalStates.openDevicesDialogRequest++
            GlobalStates.deviceControlsName = name
            GlobalStates.openDeviceControlsRequest++
        }
    }

    // ── MouseMenu ───────────────────────────────────────────────────────
    GlobalShortcut {
        name: "mouseMenuToggle"
        description: "Toggle mouse settings menu"
        onPressed: GlobalStates.mouseMenuOpen = !GlobalStates.mouseMenuOpen
    }
    IpcHandler {
        target: "mouseMenu"
        function toggle(): void { GlobalStates.mouseMenuOpen = !GlobalStates.mouseMenuOpen }
        function open(): void   { GlobalStates.mouseMenuOpen = true }
        function close(): void  { GlobalStates.mouseMenuOpen = false }
    }
    IpcHandler {
        target: "kinetix"
        function toggle(): void { GlobalStates.kinetixOpen = !GlobalStates.kinetixOpen }
        function open(): void   { GlobalStates.kinetixOpen = true }
        function close(): void  { GlobalStates.kinetixOpen = false }

        // Mid-game you cannot open a panel. Bind `raw` to a key and the whole
        // physics engine flattens to 1:1 and back on one press, restoring the
        // exact settings you had rather than a preset approximating them.
        function raw(): void { KinetixProfiles.toggleRaw() }
        function preset(name: string): void { KinetixProfiles.applyPreset(name) }
        /// Pin a preset to the focused window's app, so it engages by itself
        /// every time that app is in front. Run it once with the game focused.
        function pin(name: string): void { KinetixProfiles.pinPresetToFocusedApp(name) }
        function status(): string {
            return KinetixProfiles.rawActive ? "raw" : (KinetixProfiles.activeLabel || "base")
        }
    }
    IpcHandler {
        target: "display"
        function toggle(): void { GlobalStates.displayOpen = !GlobalStates.displayOpen }
        function open(): void   { GlobalStates.displayOpen = true }
        function close(): void  { GlobalStates.displayOpen = false }
    }
    IpcHandler {
        target: "settings"
        function toggle(): void { SettingsApp.toggle() }
        function open(): void   { SettingsApp.open() }
        function close(): void  { SettingsApp.close() }
    }
    GlobalShortcut {
        name: "settingsToggle"
        description: "Toggle the settings window"
        onPressed: SettingsApp.toggle()
    }
    GlobalShortcut {
        name: "displayToggle"
        description: "Toggle display settings panel"
        onPressed: GlobalStates.displayOpen = !GlobalStates.displayOpen
    }
    GlobalShortcut {
        name: "kinetixToggle"
        description: "Toggle KinetiX mouse menu"
        onPressed: GlobalStates.kinetixOpen = !GlobalStates.kinetixOpen
    }

    // Lock + suspend (with the suspending popup) lives in modules/ii/lock/Lock.qml.
}
