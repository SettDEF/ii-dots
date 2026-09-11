import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets.widgetCanvas

AbstractWidget {
    id: root

    required property string configEntryName
    required property int screenWidth
    required property int screenHeight
    required property int scaledScreenWidth
    required property int scaledScreenHeight
    required property real wallpaperScale
    property bool visibleWhenLocked: false
    property var configEntry: Config.options.background.widgets[configEntryName]
    property string placementStrategy: configEntry.placementStrategy
    property real targetX: Math.max(0, Math.min(configEntry.x, scaledScreenWidth - width))
    property real targetY : Math.max(0, Math.min(configEntry.y, scaledScreenHeight - height))
    x: targetX
    y: targetY
    visible: opacity > 0
    opacity: (GlobalStates.screenLocked && !visibleWhenLocked) ? 0 : 1
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    scale: (draggable && containsPress) ? 1.05 : 1
    Behavior on scale {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    // Published so the desktop-icons layer can cut these areas out of its input
    // mask; it sits above this one and would otherwise swallow every drag.
    // Resolves only once the item is parented into its window, which is after
    // Component.onCompleted for anything behind a Loader. Publishing when it
    // changes is what registers statically-placed widgets at all; the clock
    // only worked because its placement animates.
    readonly property string screenName: root.QsWindow.window?.screen?.name ?? ""
    readonly property string regionKey: root.screenName + ":" + root.configEntryName

    function publishRegion() {
        if (root.screenName.length === 0)
            return;
        DesktopWidgetRegions.set(root.regionKey, root.screenName,
            root.x, root.y, root.width, root.height);
    }

    onScreenNameChanged: publishRegion()
    onXChanged: publishRegion()
    onYChanged: publishRegion()
    onWidthChanged: publishRegion()
    onHeightChanged: publishRegion()
    Component.onCompleted: publishRegion()
    Component.onDestruction: DesktopWidgetRegions.clear(root.regionKey)

    draggable: placementStrategy === "free"
    onReleased: {
        root.targetX = root.x;
        root.targetY = root.y;
        configEntry.x = root.targetX;
        configEntry.y = root.targetY;
    }

    property bool needsColText: false
    property color dominantColor: Appearance.colors.colPrimary
    property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
    property color colText: {
        const onNormalBackground = (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        const adaptiveColor = ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12))
        return onNormalBackground ? Appearance.colors.colOnLayer0 : adaptiveColor;
    }

    property bool wallpaperIsVideo: Config.options.background.wallpaperPath.endsWith(".mp4") || Config.options.background.wallpaperPath.endsWith(".webm") || Config.options.background.wallpaperPath.endsWith(".mkv") || Config.options.background.wallpaperPath.endsWith(".avi") || Config.options.background.wallpaperPath.endsWith(".mov")
    property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
    
    onWallpaperPathChanged: refreshPlacementIfNeeded()
    onPlacementStrategyChanged: refreshPlacementIfNeeded()
    // The script is called with --screen-width/--screen-height in
    // wallpaper-px (= screen.width / effectiveWallpaperScale). If the
    // user changes zoom, scaledScreen* shrinks/grows but the SAME
    // center_x is suddenly out-of-range for the new scale, so the clock
    // shoots off-screen. Re-run on either scale or scaled-size change.
    onWallpaperScaleChanged: refreshPlacementIfNeeded()
    onScaledScreenWidthChanged: refreshPlacementIfNeeded()
    onScaledScreenHeightChanged: refreshPlacementIfNeeded()
    Connections {
        target: Config
        function onReadyChanged() { refreshPlacementIfNeeded() }
    }
    // Recompute placement when the user saves a new crop — the visible
    // region of the wallpaper changed, so the "least busy" pocket may
    // have moved.
    Connections {
        target: Config.options.background.crop
        function onRevChanged() { refreshPlacementIfNeeded() }
    }
    function refreshPlacementIfNeeded() {
        if (!Config.ready) return;
        if (root.placementStrategy === "free" && !root.needsColText) return;
        leastBusyRegionProc.wallpaperPath = root.wallpaperPath;
        leastBusyRegionProc.running = false;
        leastBusyRegionProc.running = true;
    }
    Process {
        id: leastBusyRegionProc
        property string wallpaperPath: root.wallpaperPath
        // TODO: make these less arbitrary
        property int contentWidth: 300
        property int contentHeight: 300
        property int horizontalPadding: 200
        property int verticalPadding: 200
        command: [Quickshell.shellPath("scripts/images/least-busy-region-venv.sh") // Comments to force the formatter to break lines
            , "--screen-width", Math.round(root.scaledScreenWidth) //
            , "--screen-height", Math.round(root.scaledScreenHeight) //
            , "--width", contentWidth //
            , "--height", contentHeight //
            , "--horizontal-padding", horizontalPadding //
            , "--vertical-padding", verticalPadding //
            , wallpaperPath //
            , ...(root.placementStrategy === "mostBusy" ? ["--busiest"] : [])
            // "--visual-output",
        ]
        stdout: StdioCollector {
            id: leastBusyRegionOutputCollector
            onStreamFinished: {
                const output = leastBusyRegionOutputCollector.text;
                // console.log("[Background] Least busy region output:", output)
                if (output.length === 0) return;
                const parsedContent = JSON.parse(output);
                root.dominantColor = parsedContent.dominant_color || Appearance.colors.colPrimary;
                if (root.placementStrategy === "free") return;
                // Clamp to screen bounds. Without this, a stale wallpaperScale
                // (from a quick zoom change) or a corner-pocket pick can push
                // the clock past the screen edge and it disappears.
                const rawX = parsedContent.center_x * root.wallpaperScale - root.width / 2;
                const rawY = parsedContent.center_y * root.wallpaperScale - root.height / 2;
                root.targetX = Math.max(0, Math.min(rawX, root.screenWidth  - root.width));
                root.targetY = Math.max(0, Math.min(rawY, root.screenHeight - root.height));
            }
        }
    }
}

