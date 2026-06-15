// Tracks which container tile is currently "open" — its expanded
// content renders in the panel-wide drawer below the toggle grid,
// not inline within the grid. Click a container tile to open or
// close it; only one drawer is open at a time per panel.
pragma Singleton
import QtQuick
import Quickshell
import qs
import qs.modules.common

Singleton {
    id: root
    property bool   isOpen:    false
    property string type:      ""    // "rog" / "sliders" / etc.
    property int    tabIndex:  -1    // legacy single-list = -1
    property int    buttonIndex: -1  // index into cfg.tabs[tabIndex].toggles
    // True when the container tile was added implicitly (by long-press
    // on a tray icon).  On close() we remove it again so the user's
    // grid isn't polluted just because they peeked at the container.
    property bool   isTransient: false

    function open(t, type_, idx, transientFlag) {
        tabIndex    = t
        type        = type_
        buttonIndex = idx
        isTransient = transientFlag ?? false
        isOpen      = true
    }
    function close() {
        // If the container was opened isTransiently (long-press from tray),
        // remove its tile from the user's tab on close so the grid isn't
        // polluted by a brief preview.
        if (isTransient && tabIndex >= 0 && buttonIndex >= 0 && Config.ready) {
            const cfg = Config.options.sidebar.quickToggles.android
            if (tabIndex < (cfg.tabs?.length ?? 0)) {
                const tabs = cfg.tabs.slice()
                const tab = tabs[tabIndex]
                if (tab) {
                    const list = (tab.toggles ?? []).slice()
                    if (buttonIndex < list.length
                        && list[buttonIndex]?.type === type) {
                        list.splice(buttonIndex, 1)
                        tabs[tabIndex] = Object.assign({}, tab, { toggles: list })
                        cfg.tabs = tabs
                    }
                }
            }
        }
        isOpen      = false
        tabIndex    = -1
        type        = ""
        buttonIndex = -1
        isTransient   = false
    }
    function toggle(t, type_, idx) {
        // Same container? close. Otherwise open (replacing any other open one).
        if (isOpen && tabIndex === t && buttonIndex === idx) close()
        else                                                  open(t, type_, idx)
    }
    // When a tab is removed/recreated or a container index shifts, the
    // open state can point at a stale entry — call this to clear if needed.
    function clearIfStale(maxToggles) {
        if (isOpen && (buttonIndex < 0 || buttonIndex >= maxToggles)) close()
    }
}
