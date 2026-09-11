pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.ii.display
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import qs.modules.ii.background.widgets
import qs.modules.ii.background.widgets.clock
import qs.modules.ii.background.widgets.weather
import qs.modules.ii.background.widgets.resources
import qs.modules.ii.background.widgets.timers
import qs.modules.ii.background.widgets.calendar
import qs.modules.ii.background.widgets.todo
import qs.modules.ii.background.widgets.usercard
import qs.modules.ii.background.widgets.images
import qs.modules.ii.background.widgets.visualizer
import qs.modules.ii.background.widgets.worldclock

Variants {
    id: root
    model: Quickshell.screens

    PanelWindow {
        id: bgRoot

        required property var modelData

        // Hide when fullscreen
        property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
        property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
        visible: GlobalStates.screenLocked || (!(activeWorkspaceWithFullscreen != undefined)) || !Config?.options.background.hideWhenFullscreen

        // Workspaces
        property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
        property list<var> relevantWindows: HyprlandData.windowList.filter(win => win.monitor == monitor?.id && win.workspace.id >= 0).sort((a, b) => a.workspace.id - b.workspace.id)
        property int firstWorkspaceId: relevantWindows[0]?.workspace.id || 1
        property int lastWorkspaceId: relevantWindows[relevantWindows.length - 1]?.workspace.id || 10
        // Wallpaper
        property bool wallpaperIsVideo: {
            const p = Config.options.background.wallpaperPath.toLowerCase()
            return [".mp4", ".webm", ".mkv", ".avi", ".mov", ".m4v", ".gif"]
                .some(ext => p.endsWith(ext))
        }
        property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
        property bool wallpaperSafetyTriggered: {
            const enabled = Config.options.workSafety.enable.wallpaper;
            const sensitiveWallpaper = (CF.StringUtils.stringListContainsSubstring(wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords));
            const sensitiveNetwork = (CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
            return enabled && sensitiveWallpaper && sensitiveNetwork;
        }
        property real wallpaperToScreenRatio: Math.min(wallpaperWidth / screen.width, wallpaperHeight / screen.height)
        // User-set crop for the current wallpaper. Looked up from the
        // perFile JSON map keyed on wallpaperPath, falling back to the
        // top-level offsetX/Y/scale if no per-file entry.
        // Crop entries are keyed by the ORIGINAL source file, not the
        // currently-displayed wallpaperPath. Walltune outputs alternate
        // between processed-a.png / processed-b.png on each apply, so
        // keying by wallpaperPath would pick up the WRONG entry (or none)
        // on the next walltune cycle.
        readonly property string _cropKey: {
            const src = Config.options.background.wallpaperSourcePath || ""
            return src.length > 0 ? src : wallpaperPath
        }
        readonly property var _userCrop: {
            // Touch `rev` so the binding re-evaluates on Save — JsonObject's
            // string propertyChanged isn't always reliable.
            const _ = Config.options.background.crop.rev
            try {
                const m = JSON.parse(Config.options.background.crop.perFile || "{}")
                if (m && m[_cropKey]) return m[_cropKey]
            } catch (e) {}
            const c = Config.options.background.crop
            return { offsetX: c.offsetX, offsetY: c.offsetY, scale: c.scale }
        }
        property real userOffsetX: _userCrop.offsetX || 0
        property real userOffsetY: _userCrop.offsetY || 0
        property real userScale:   _userCrop.scale   || 1
        property bool userFit:     _userCrop.fit     === true
        // Fit mode = "show the entire image" — applying the workspace
        // parallax zoom (1.07× by default) would re-crop the edges, so
        // the bg wouldn't match the adjuster's preview. Skip it when
        // userFit is on.
        property real preferredWallpaperScale: userFit
            ? userScale
            : Config.options.background.parallax.workspaceZoom * userScale
        // effectiveWallpaperScale must be a BINDING — not a one-shot
        // imperative assignment — so it re-evaluates when the user saves a
        // new crop (changes userScale via preferredWallpaperScale). Before:
        // saving a new scale silently did nothing because the proc only
        // ran on wallpaperPathChanged.
        property real effectiveWallpaperScale: {
            const w = wallpaperWidth, h = wallpaperHeight
            const sw = screen.width, sh = screen.height
            if (!w || !h || !sw || !sh) return 1
            if (w <= sw || h <= sh) {
                // Undersized → must fit; can't go below the cover scale.
                return Math.max(sw / w, sh / h)
            }
            // Oversized → free to honour user zoom, capped by what the
            // image can supply without stretching past native pixels.
            return Math.min(preferredWallpaperScale, w / sw, h / sh)
        }
        property int wallpaperWidth: modelData.width // Some reasonable init value, to be updated
        property int wallpaperHeight: modelData.height // Some reasonable init value, to be updated
        property real movableXSpace: ((wallpaperWidth / wallpaperToScreenRatio * effectiveWallpaperScale) - screen.width) / 2
        property real movableYSpace: ((wallpaperHeight / wallpaperToScreenRatio * effectiveWallpaperScale) - screen.height) / 2
        readonly property bool verticalParallax: (Config.options.background.parallax.autoVertical && wallpaperHeight > wallpaperWidth) || Config.options.background.parallax.vertical
        // Colors
        property bool shouldBlur: (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        property color dominantColor: Appearance.colors.colPrimary // Default, to be changed
        property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
        property color colText: {
            if (wallpaperSafetyTriggered)
                return CF.ColorUtils.mix(Appearance.colors.colOnLayer0, Appearance.colors.colPrimary, 0.75);
            return (GlobalStates.screenLocked && shouldBlur) ? Appearance.colors.colOnLayer0 : CF.ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12));
        }
        Behavior on colText {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // Layer props
        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: (GlobalStates.screenLocked && !scaleAnim.running) ? WlrLayer.Overlay : WlrLayer.Background
        // WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "quickshell:background"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Feeds InputMode. Without a probe instantiated SOMEWHERE, InputMode
        // never leaves "mouse" — which meant every touch adaptation in the
        // shell (and TouchEdges' whole input region, which gates on isTouch)
        // was dead code. Passive: HoverHandler does not block, and the
        // TapHandler uses DragThreshold so it never takes an exclusive grab.
        // z below the desktop widgets: at the component default (999) this
        // filled the window above them and swallowed every press, so no
        // widget could be dragged. It still sees anything that reaches the
        // wallpaper, which is all the touch probe needs.
        InputModeProbe { z: -1 }
        color: {
            if (!bgRoot.wallpaperSafetyTriggered || bgRoot.wallpaperIsVideo)
                return "transparent";
            return CF.ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colPrimary, 0.75);
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        onWallpaperPathChanged: {
            bgRoot.updateZoomScale();
            // Clock position gets updated after zoom scale is updated
        }

        // Wallpaper zoom scale
        function updateZoomScale() {
            getWallpaperSizeProc.path = bgRoot.wallpaperPath;
            getWallpaperSizeProc.running = true;
        }
        Process {
            id: getWallpaperSizeProc
            property string path: bgRoot.wallpaperPath
            command: ["magick", "identify", "-ping", "-format", "%w %h", path]
            stdout: StdioCollector {
                id: wallpaperSizeOutputCollector
                onStreamFinished: {
                    const output = wallpaperSizeOutputCollector.text;
                    const [width, height] = output.split(" ").map(Number);
                    if (!width || !height) return;
                    bgRoot.wallpaperWidth = width;
                    bgRoot.wallpaperHeight = height;
                    // effectiveWallpaperScale is now a pure binding above —
                    // it picks up the new sizes (and any userScale change)
                    // automatically.
                }
            }
        }

        // For video wallpapers, the actual renderer is mpvpaper (external
        // process), not the QML Image. Updating userOffsetX/Y/scale in QML
        // therefore does nothing visually until mpvpaper is restarted with
        // the new --video-zoom / --video-pan-x / --video-pan-y options.
        // Restart it on every crop save (rev bump).
        Process {
            id: videoCropRestartProc
            command: ["bash", "-c", "true"]
        }
        Connections {
            target: Config.options.background.crop
            function onRevChanged() {
                if (!bgRoot.wallpaperIsVideo) return
                // Re-run switchwall (which now reads the saved crop and
                // launches mpvpaper with the matching mpv options).
                const sw = Quickshell.shellPath("scripts/colors/switchwall.sh")
                const vid = Config.options.background.wallpaperPath
                if (!vid || vid.length === 0) return
                videoCropRestartProc.command = [
                    "bash", "-c",
                    `'${sw}' --image '${vid.replace(/'/g, "'\\''")}' --no-wallpaper-update`
                ]
                videoCropRestartProc.running = false
                videoCropRestartProc.running = true
            }
        }

        // Wallpaper transition preview logic
        Timer {
            id: previewTimer
            interval: 250 // Brief delay to simulate loading time
            repeat: false
            onTriggered: {
                wallpaper.previewOpacityMultiplier = 1
                wallpaper.state = "active"
                wallpaperPrevContainer.state = "hidden"
            }
        }

        function triggerTransitionPreview() {
            if (wallpaper.status !== Image.Ready || bgRoot.wallpaperIsVideo) return
            previewTimer.stop()
            
            // 1. Reset main wallpaper's preview opacity multiplier so it's fully opaque initially
            wallpaper.previewOpacityMultiplier = 1
            wallpaper.state = "active"
            
            // 2. Setup the previous wallpaper copy
            wallpaperPrev.source = wallpaper.source
            wallpaperPrevContainer.state = "visible"
            
            // 3. Force main wallpaper to fade out (revealing wallpaperPrev)
            // Need a tiny delay before setting to 0 so QML processes the source update of wallpaperPrev
            Qt.callLater(() => {
                wallpaper.previewOpacityMultiplier = 0
                wallpaper.state = "loading"
                previewTimer.start()
            })
        }

        Connections {
            target: GlobalStates
            function onWallTransitionChanged() {
                bgRoot.triggerTransitionPreview()
            }
        }

        Item {
            anchors.fill: parent
            clip: true

            // ── Wallpaper effect ────────────────────────────────────
            // A pack effect running on the wallpaper itself. Sampling effects
            // (the warps) get the wallpaper image directly as their source,
            // so they distort the picture with no screen capture involved.
            Loader {
                id: bgEffect
                anchors.fill: parent
                z: 1
                readonly property var fx:
                    AppDisplay.effectByPath(Config.options.background.effect ?? "")
                active: !!fx
                sourceComponent: EffectRenderer {
                    fx: bgEffect.fx
                    rounding: 0
                    // Warps read the wallpaper directly; overlay kinds ignore it.
                    sourceItem: bgEffect.fx?.samples === true ? wallpaper : null
                    // Merge the user's per-effect variable overrides on top of
                    // the legacy single strength value. Empty map → renderer
                    // falls back to each param's declared default.
                    values: {
                        let v = {};
                        try {
                            const all = JSON.parse(Config.options.background.effectParams || "{}");
                            const mine = all[Config.options.background.effect ?? ""];
                            if (mine) v = Object.assign(v, mine);
                        } catch (e) {}
                        const s = Config.options.background.effectStrength;
                        if (s >= 0 && v.strength === undefined) v.strength = s;
                        return Object.keys(v).length > 0 ? v : null;
                    }
                }
            }

            // Wallpaper
            StyledImage {
                id: wallpaper
                visible: opacity > 0 && !blurLoader.active
                property real previewOpacityMultiplier: 1
                opacity: ((status === Image.Ready && !bgRoot.wallpaperIsVideo) ? 1 : 0) * previewOpacityMultiplier
                // cache=false: walltune slot alternation can land on the
                // same path twice (apply→reprocess→apply same image); Qt's
                // cached pixels then linger and the old wallpaper stays.
                cache: false
                smooth: false

                // Entry animation based on transition type
                property real entryScale: 1
                property real entryX: 0
                scale: entryScale
                transformOrigin: Item.Center
                Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

                onStatusChanged: {
                    if (status === Image.Ready) {
                        wallpaper.state = "active"
                        wallpaperPrevContainer.state = "hidden"
                    }
                }

                onSourceChanged: {
                    if (previousSource !== "" && previousSource !== source) {
                        wallpaperPrev.source = previousSource
                        wallpaperPrevContainer.state = "visible"
                        wallpaper.state = "loading"

                        if (status === Image.Ready) {
                            Qt.callLater(() => {
                                if (status === Image.Ready) {
                                    wallpaper.state = "active"
                                    wallpaperPrevContainer.state = "hidden"
                                }
                            })
                        }
                    }
                    previousSource = source
                }

                state: "active"
                states: [
                    State {
                        name: "active"
                        PropertyChanges {
                            target: wallpaper
                            entryScale: 1
                            entryX: 0
                        }
                    },
                    State {
                        name: "loading"
                        PropertyChanges {
                            target: wallpaper
                            entryScale: GlobalStates.wallTransition === "zoom" ? 1.08 : 1
                            entryX: GlobalStates.wallTransition === "slide" ? 1 : 0
                        }
                    }
                ]

                transitions: [
                    Transition {
                        id: activeTransition
                        from: "loading"; to: "active"
                        ParallelAnimation {
                            NumberAnimation {
                                properties: "entryScale"
                                duration: 700
                                easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                properties: "entryX"
                                duration: 700
                                easing.type: Easing.OutCubic
                            }
                        }
                    },
                    Transition {
                        from: "active"; to: "loading"
                        PropertyAction { target: wallpaper; properties: "entryScale,entryX" }
                    }
                ]

                // NB: must NOT be a binding (`: source`). A binding would
                // auto-update previousSource as soon as source changes —
                // so by the time onSourceChanged runs, previousSource is
                // already == source and the if-guard above always fails,
                // killing every transition (fade / slide / zoom / wipe).
                // Capture the initial value once via Component.onCompleted.
                property string previousSource: ""
                Component.onCompleted: previousSource = source
                // Range = groups that workspaces span on
                property int chunkSize: Config?.options.bar.workspaces.shown ?? 10
                property int lower: Math.floor(bgRoot.firstWorkspaceId / chunkSize) * chunkSize
                property int upper: Math.ceil(bgRoot.lastWorkspaceId / chunkSize) * chunkSize
                property int range: upper - lower
                property real valueX: {
                    let result = 0.5;
                    // While the user is framing in the adjuster, hold the
                    // parallax at center so what they see is what the bg
                    // paints. Parallax resumes once the adjuster closes.
                    if (GlobalStates.wallpaperAdjusterOpen) return 0.5
                    if (Config.options.background.parallax.enableWorkspace && !bgRoot.verticalParallax) {
                        result = ((bgRoot.monitor.activeWorkspace?.id - lower) / range);
                    }
                    if (Config.options.background.parallax.enableSidebar) {
                        result += (0.15 * GlobalStates.sidebarRightOpen - 0.15 * GlobalStates.sidebarLeftOpen);
                    }
                    return result;
                }
                property real valueY: {
                    let result = 0.5;
                    if (GlobalStates.wallpaperAdjusterOpen) return 0.5
                    if (Config.options.background.parallax.enableWorkspace && bgRoot.verticalParallax) {
                        result = ((bgRoot.monitor.activeWorkspace?.id - lower) / range);
                    }
                    return result;
                }
                property real effectiveValueX: Math.max(0, Math.min(1, valueX))
                property real effectiveValueY: Math.max(0, Math.min(1, valueY))
                x: -(bgRoot.movableXSpace) - (effectiveValueX - 0.5) * 2 * bgRoot.movableXSpace + bgRoot.userOffsetX * bgRoot.movableXSpace + (GlobalStates.wallTransition === "slide" ? entryX * parent.width : 0)
                y: -(bgRoot.movableYSpace) - (effectiveValueY - 0.5) * 2 * bgRoot.movableYSpace + bgRoot.userOffsetY * bgRoot.movableYSpace
                source: bgRoot.wallpaperSafetyTriggered ? "" : bgRoot.wallpaperPath
                fillMode: bgRoot.userFit ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                Behavior on x {
                    enabled: wallpaper.state === "active" && !activeTransition.running
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    enabled: wallpaper.state === "active" && !activeTransition.running
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                sourceSize {
                    width: bgRoot.screen.width * bgRoot.effectiveWallpaperScale * bgRoot.monitor.scale
                    height: bgRoot.screen.height * bgRoot.effectiveWallpaperScale * bgRoot.monitor.scale
                }
                width: bgRoot.wallpaperWidth / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
                height: bgRoot.wallpaperHeight / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
            }

            // Previous Wallpaper Container (handles clipping for Wipe, and sliding for Slide)
            Item {
                id: wallpaperPrevContainer
                
                // Position and size match wallpaper exactly to preserve parallax
                property real slideOffset: 0
                property real wipeProgress: 1
                
                readonly property real baseWallpaperX: -(bgRoot.movableXSpace) - (wallpaper.effectiveValueX - 0.5) * 2 * bgRoot.movableXSpace
                readonly property real baseWallpaperY: -(bgRoot.movableYSpace) - (wallpaper.effectiveValueY - 0.5) * 2 * bgRoot.movableYSpace
                readonly property real wallpaperWidthVal: bgRoot.wallpaperWidth / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
                readonly property real wallpaperHeightVal: bgRoot.wallpaperHeight / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
                
                x: baseWallpaperX + (GlobalStates.wallTransition === "slide" ? slideOffset * parent.width : 0)
                y: baseWallpaperY
                width: wallpaperWidthVal * (GlobalStates.wallTransition === "wipe" ? wipeProgress : 1)
                height: wallpaperHeightVal
                clip: true
                visible: opacity > 0 && !blurLoader.active
                
                opacity: 0
                scale: 1
                transformOrigin: Item.Center

                Image {
                    id: wallpaperPrev
                    x: 0
                    y: 0
                    width: wallpaperPrevContainer.wallpaperWidthVal
                    height: wallpaperPrevContainer.wallpaperHeightVal
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize {
                        width: bgRoot.screen.width * bgRoot.effectiveWallpaperScale * bgRoot.monitor.scale
                        height: bgRoot.screen.height * bgRoot.effectiveWallpaperScale * bgRoot.monitor.scale
                    }
                }

                state: "hidden"
                states: [
                    State {
                        name: "visible"
                        PropertyChanges {
                            target: wallpaperPrevContainer
                            opacity: 1
                            scale: 1
                            slideOffset: 0
                            wipeProgress: 1
                        }
                    },
                    State {
                        name: "hidden"
                        PropertyChanges {
                            target: wallpaperPrevContainer
                            opacity: 0
                            scale: GlobalStates.wallTransition === "zoom" ? 1.08 : 1
                            slideOffset: GlobalStates.wallTransition === "slide" ? -1 : 0
                            wipeProgress: GlobalStates.wallTransition === "wipe" ? 0 : 1
                        }
                    }
                ]

                transitions: [
                    Transition {
                        from: "visible"; to: "hidden"
                        ParallelAnimation {
                            NumberAnimation {
                                properties: "opacity"
                                duration: 700
                                easing.type: Easing.InOutCubic
                            }
                            NumberAnimation {
                                properties: "scale"
                                duration: 700
                                easing.type: Easing.InCubic
                            }
                            NumberAnimation {
                                properties: "slideOffset"
                                duration: 700
                                easing.type: Easing.InOutCubic
                            }
                            NumberAnimation {
                                properties: "wipeProgress"
                                duration: 700
                                easing.type: Easing.InOutCubic
                            }
                        }
                    },
                    Transition {
                        from: "hidden"; to: "visible"
                        PropertyAction { target: wallpaperPrevContainer; properties: "opacity,scale,slideOffset,wipeProgress" }
                    }
                ]
                
                onOpacityChanged: {
                    if (opacity === 0) {
                        wallpaperPrev.source = ""
                    }
                }
            }

            Loader {
                id: blurLoader
                active: Config.options.lock.blur.enable && (GlobalStates.screenLocked || scaleAnim.running)
                anchors.fill: wallpaper
                scale: GlobalStates.screenLocked ? Config.options.lock.blur.extraZoom : 1
                Behavior on scale {
                    NumberAnimation {
                        id: scaleAnim
                        duration: 400
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                    }
                }
                sourceComponent: GaussianBlur {
                    source: wallpaper
                    radius: GlobalStates.screenLocked ? Config.options.lock.blur.radius : 0
                    samples: radius * 2 + 1

                    Rectangle {
                        opacity: GlobalStates.screenLocked ? 1 : 0
                        anchors.fill: parent
                        color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                    }
                }
            }

            WidgetCanvas {
                id: widgetCanvas
                anchors {
                    left: wallpaper.left
                    right: wallpaper.right
                    top: wallpaper.top
                    bottom: wallpaper.bottom
                    horizontalCenter: undefined
                    verticalCenter: undefined
                    readonly property real parallaxFactor: Config.options.background.parallax.widgetsFactor
                    leftMargin: {
                        const xOnWallpaper = bgRoot.movableXSpace;
                        const extraMove = (wallpaper.effectiveValueX * 2 * bgRoot.movableXSpace) * (parallaxFactor - 1);
                        // Counter the user-crop pan applied to the wallpaper
                        // image — otherwise widgetCanvas drifts off-screen
                        // with the wallpaper and the clock lands outside the
                        // visible region.
                        const userPan = bgRoot.userOffsetX * bgRoot.movableXSpace;
                        return xOnWallpaper - extraMove - userPan;
                    }
                    topMargin: {
                        const yOnWallpaper = bgRoot.movableYSpace;
                        const extraMove = (wallpaper.effectiveValueY * 2 * bgRoot.movableYSpace) * (parallaxFactor - 1);
                        const userPan = bgRoot.userOffsetY * bgRoot.movableYSpace;
                        return yOnWallpaper - extraMove - userPan;
                    }
                    Behavior on leftMargin {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    Behavior on topMargin {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
                width: wallpaper.width
                height: wallpaper.height
                states: State {
                    name: "centered"
                    when: GlobalStates.screenLocked || bgRoot.wallpaperSafetyTriggered
                    PropertyChanges {
                        target: widgetCanvas
                        width: parent.width
                        height: parent.height
                    }
                    AnchorChanges {
                        target: widgetCanvas
                        anchors {
                            left: undefined
                            right: undefined
                            top: undefined
                            bottom: undefined
                            horizontalCenter: parent.horizontalCenter
                            verticalCenter: parent.verticalCenter
                        }
                    }
                }
                transitions: Transition {
                    PropertyAnimation {
                        properties: "width,height"
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                    AnchorAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.weather.enable
                    sourceComponent: WeatherWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                        wallpaperScale: bgRoot.effectiveWallpaperScale
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.clock.enable
                    sourceComponent: ClockWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                        wallpaperScale: bgRoot.effectiveWallpaperScale
                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                    }
                }

                // Every desktop widget wants the same five geometry values.
                // Written once here so adding one is a single line below.
                QtObject {
                    id: geo
                    readonly property real w: bgRoot.screen.width
                    readonly property real h: bgRoot.screen.height
                    readonly property real sw: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                    readonly property real sh: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                    readonly property real scale: bgRoot.effectiveWallpaperScale
                }

                component Slot: FadeLoader {
                    required property string key
                    shown: Config.options.background.widgets[key].enable
                }

                Slot { key: "resources"; sourceComponent: ResourcesWidget {
                    screenWidth: geo.w; screenHeight: geo.h; scaledScreenWidth: geo.sw
                    scaledScreenHeight: geo.sh; wallpaperScale: geo.scale } }

                Slot { key: "timers"; sourceComponent: TimerWidget {
                    screenWidth: geo.w; screenHeight: geo.h; scaledScreenWidth: geo.sw
                    scaledScreenHeight: geo.sh; wallpaperScale: geo.scale } }

                Slot { key: "calendar"; sourceComponent: CalendarWidget {
                    screenWidth: geo.w; screenHeight: geo.h; scaledScreenWidth: geo.sw
                    scaledScreenHeight: geo.sh; wallpaperScale: geo.scale } }

                Slot { key: "todo"; sourceComponent: TodoWidget {
                    screenWidth: geo.w; screenHeight: geo.h; scaledScreenWidth: geo.sw
                    scaledScreenHeight: geo.sh; wallpaperScale: geo.scale } }

                Slot { key: "userCard"; sourceComponent: UserCardWidget {
                    screenWidth: geo.w; screenHeight: geo.h; scaledScreenWidth: geo.sw
                    scaledScreenHeight: geo.sh; wallpaperScale: geo.scale } }

                Slot { key: "customImage"; sourceComponent: CustomImage {
                    screenWidth: geo.w; screenHeight: geo.h; scaledScreenWidth: geo.sw
                    scaledScreenHeight: geo.sh; wallpaperScale: geo.scale } }

                Slot { key: "visualizer"; sourceComponent: VisualizerWidget {
                    screenWidth: geo.w; screenHeight: geo.h; scaledScreenWidth: geo.sw
                    scaledScreenHeight: geo.sh; wallpaperScale: geo.scale } }

                Slot { key: "worldClock"; sourceComponent: WorldClockWidget {
                    screenWidth: geo.w; screenHeight: geo.h; scaledScreenWidth: geo.sw
                    scaledScreenHeight: geo.sh; wallpaperScale: geo.scale } }
            }
        }
    }
}

