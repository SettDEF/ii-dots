// Always-loaded diagnostic IPC handler.
//
// Lives alongside Shortcuts.qml so it stays available regardless of
// which lazy panels are loaded. Zero idle cost — IpcHandler methods
// only run when invoked via `qs ipc call diag <method>`.
//
// Usage:
//   qs ipc call diag panels        - which lazy panels are loaded right now
//   qs ipc call diag flags         - all GlobalStates booleans (raw)
//   qs ipc call diag mem           - process RSS / threads / uptime hint
//   qs ipc call diag summary       - human-readable one-screen summary

import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.modules.common
import qs.services

Scope {
    // Force eager instantiation of singletons that are otherwise only
    // pulled in by lazy panels. KeyTracker connects to Hyprland events
    // and accumulates XP — it has to be alive *before* the HUD is
    // first opened, otherwise events that happened pre-HUD-open are lost.
    Connections { target: KeyTracker; ignoreUnknownSignals: true }

    IpcHandler {
        target: "diag"

        // Which LAZY-loaded panels are open (and therefore loaded into
        // memory) at this instant. Eager panels are always loaded and
        // not interesting here.
        function panels(): string {
            const state = {
                sidebarRight:      GlobalStates.sidebarRightOpen,
                cornerPopup:       GlobalStates.cornerPopupOpen,
                hud:               GlobalStates.hudOpen,
                wallpaperSelector: GlobalStates.wallpaperSelectorOpen,
                wallTune:          GlobalStates.wallTuneOpen,
                skwdWall:          GlobalStates.skwdWallOpen,
                screenDraw:        GlobalStates.screenDrawOpen,
            }
            return JSON.stringify(state, null, 2)
        }

        // Every GlobalStates bool, sorted, JSON.
        function flags(): string {
            // Pull every property whose value is bool.
            const out = {}
            for (const k in GlobalStates) {
                const v = GlobalStates[k]
                if (typeof v === "boolean") out[k] = v
            }
            return JSON.stringify(out, null, 2)
        }

        // RSS / threads / wall-clock seconds since QML startup.
        // Useful as a quick health probe.
        function mem(): string {
            const o = {
                approxMillisAlive: Date.now() - (GlobalStates._startMs ?? Date.now()),
                qmlEnginesActive: 1,  // we're singletons; one main engine
            }
            return JSON.stringify(o, null, 2)
        }

        // Human-readable one-screen summary.
        function summary(): string {
            const lazy = [
                ["sidebarRight",      GlobalStates.sidebarRightOpen],
                ["cornerPopup",       GlobalStates.cornerPopupOpen],
                ["hud",               GlobalStates.hudOpen],
                ["wallpaperSelector", GlobalStates.wallpaperSelectorOpen],
                ["wallTune",          GlobalStates.wallTuneOpen],
                ["skwdWall",          GlobalStates.skwdWallOpen],
                ["screenDraw",        GlobalStates.screenDrawOpen],
            ]
            const open   = lazy.filter(p => p[1]).map(p => p[0])
            const closed = lazy.filter(p => !p[1]).map(p => p[0])
            return ("Lazy panels currently LOADED:\n  " +
                    (open.length ? open.join(", ") : "(none)") +
                    "\nLazy panels NOT loaded:\n  " +
                    (closed.length ? closed.join(", ") : "(none)"))
        }
    }
}
