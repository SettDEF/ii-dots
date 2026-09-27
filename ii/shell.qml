//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Remove two slashes below and adjust the value to change the UI scale
////@ pragma Env QT_SCALE_FACTOR=1

import "modules/common"
import "services"
import "panelFamilies"

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    // Stuff for every panel family
    ReloadPopup {}

    // QML singletons are lazy: they don't actually instantiate until something
    // reads a property. Services that own timers, event listeners, or IPC
    // handlers and need to run from boot must be "touched" at startup. List
    // them here — adding a new eager service is one line, not a bespoke
    // void(X.y) comment block. Each entry is { service, prop } where reading
    // `service[prop]` forces instantiation.
    readonly property var eagerSingletons: [
        { service: LayoutService,         prop: "defaultLayout",
          why: "registers the IpcHandler exposing layout cycle commands" },
        { service: PlayerService,         prop: "contextIcon",
          why: "starts the mute-poll Process; otherwise the Timer never runs" },
        { service: AppUsage,              prop: "todayTotal",
          why: "kicks off screen-time tracking before the HUD tab is opened" },
        { service: FollowEmptyWorkspace,  prop: "enabled",
          why: "wires the Hyprland event listener that auto-follows orphaned monitors" },
        { service: BitwigAudioRouter,     prop: "enabled",
          why: "wires the Toplevel listener that swaps the default sink when Bitwig is focused" },
        { service: WallpaperRotation,     prop: "enabled",
          why: "starts the wallpaper rotation Timer" },
        { service: Qbt,                   prop: "baseUrl",
          why: "starts the 2s polling Timer feeding the Torrents shelf sub-tab" },
        { service: MouseService,          prop: "enabled",
          why: "monitors mouse status and gesture active/direction state" },
        { service: AppLaunch,             prop: "claimWindowMs",
          why: "wires the openwindow listener that returns a launched app's windows to the workspace it was launched from" },
    ]

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Hyprsunset.load()
        FirstRunExperience.load()
        ConflictKiller.load()
        Cliphist.refresh()
        Wallpapers.load()
        Updates.load()
        // Instantiate every eager singleton declared above.
        for (let i = 0; i < eagerSingletons.length; ++i) {
            const e = eagerSingletons[i]
            void(e.service[e.prop])
        }
        // Self-heal the wallpaper-recents file on startup: relocate stale
        // paths via basename search and drop unrecoverable entries.
        recentsRepairProc.running = true
    }

    Process {
        id: recentsRepairProc
        command: ["bash", Quickshell.shellPath("scripts") + "/colors/wallpaper-recents.sh", "repair"]
    }

    // A qs reload churns layer-shell surfaces and can leave keyboard focus
    // dropped (can't type until switching workspaces). Re-assert focus to the
    // active window once the surfaces have settled after each (re)load.
    Process {
        id: refocusProc
        command: ["bash", Quickshell.env("HOME") + "/.config/hypr/hyprland/scripts/refocus.sh"]
    }
    Timer {
        // Delay so the layer surfaces have finished settling before refocus.
        interval: 500
        running: true
        repeat: false
        onTriggered: refocusProc.running = true
    }


    // Panel families
    property list<string> families: ["ii", "waffle"]
    function cyclePanelFamily() {
        const currentIndex = families.indexOf(Config.options.panelFamily)
        const nextIndex = (currentIndex + 1) % families.length
        Config.options.panelFamily = families[nextIndex]
    }

    component PanelFamilyLoader: LazyLoader {
        required property string identifier
        property bool extraCondition: true
        active: Config.ready && Config.options.panelFamily === identifier && extraCondition
    }
    
    PanelFamilyLoader {
        identifier: "ii"
        component: IllogicalImpulseFamily {}
    }

    PanelFamilyLoader {
        identifier: "waffle"
        component: WaffleFamily {}
    }


    // Shortcuts
    IpcHandler {
        target: "panelFamily"

        function cycle(): void {
            root.cyclePanelFamily()
        }
    }

    GlobalShortcut {
        name: "panelFamilyCycle"
        description: "Cycles panel family"

        onPressed: root.cyclePanelFamily()
    }
}














































































































































































