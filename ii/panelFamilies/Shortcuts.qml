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

    // Lock + suspend (with the suspending popup) lives in modules/ii/lock/Lock.qml.
}
