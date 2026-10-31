// WallpaperShortcuts — the wallpaper picker's and the wallpaper hub's shortcuts
// (Ctrl+Super+T, Ctrl+Super+Alt+T, Ctrl+Super+Shift+T) and IPC, for every panel
// family: waffle loads it too, so its wallpaper picker opens (it did not: these
// lived in Shortcuts.qml, which only the ii family loads).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common

Scope {
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
}
