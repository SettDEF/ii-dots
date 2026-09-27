pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Qt5Compat.GraphicalEffects

Rectangle {
    id: root

    /// A section's own label.
    component SectionLabel: StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 2
        font.pixelSize: Appearance.font.pixelSize.smaller - 1
        font.weight: Font.Medium
        font.letterSpacing: 0.4
        color: Appearance.colors.colOnLayer0
        opacity: 0.45
    }

    /// The two halves of this panel: what the wallpaper does, and what the
    /// colour does. They were interleaved — transition, parallax, effect,
    /// stack, then dark/light, extraction — so neither read as a group.
    component GroupHeading: RowLayout {
        property alias text: groupText.text
        Layout.fillWidth: true
        Layout.topMargin: 10
        spacing: 8
        StyledText {
            id: groupText
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer0
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: 1
            color: Appearance.colors.colOnLayer0
            opacity: 0.12
        }
    }

    readonly property string home: `${Quickshell.env("HOME")}`
    readonly property string blueprintsDir: home + "/.config/aether/blueprints"
    readonly property string stateFile: home + "/.local/state/quickshell/walltune-state.json"
    readonly property string currentWall: Config.options.background.wallpaperPath
    // Track the *source* wallpaper (the un-edited file the user picked from
    // the wallpaper popup). currentWall flips to processed.png after a Both
    // run, so we need this snapshot for the Colors/Wallpaper reset modes.
    property string sourceWall: ""
    // "a" or "b" — which processed-{slot}.png we wrote LAST. Next apply
    // alternates, so wallpaperPath always changes (forces Image reload).
    property string lastProcessedSlot: "a"

    // Video wallpapers can't be tuned frame by frame, so WallTune shows a notice instead.
    readonly property bool sourceIsVideo: {
        const w = (sourceWall && sourceWall !== "") ? sourceWall : currentWall
        return /\.(mp4|webm|mkv|avi|mov|gif)$/i.test(w || "")
    }

    property string selectedMode: ""
    property string selectedTheory:    ""   // "" | mono | analogous | complementary | triadic | split | tetradic
    property string selectedStyle:     ""   // "" | pastel | muted | bright | colorful | material
    property string selectedPractical: ""   // "" | high_contrast | duotone
    property bool darkMode: true
    // Apply mode — controls what reprocess() actually changes:
    //   "both"     = update wallpaper file + re-extract theme (default behaviour)
    //   "colors"   = re-extract theme from the adjusted image, leave wallpaper alone
    //   "wallpaper"= overwrite wallpaper with the adjusted image, keep theme as-is
    property string applyMode: "both"
    readonly property var applyModes: [
        { id: "wallpaper", label: "Wallpaper", icon: "wallpaper" },
        { id: "both",      label: "Both",      icon: "auto_awesome" },
        { id: "colors",    label: "Colors",    icon: "palette" },
    ]
    // Stack mode: every apply chains on top of the previously-processed image
    // instead of starting fresh from the original wallpaper. Off by default —
    // makes each slider read as an *absolute* setting. On = additive: slamming
    // brightness twice with the slider at +20 gives roughly +40 over the
    // source. Useful for film-grain / drift looks; otherwise off.
    property bool stackable: false
    property var blueprints: []

    // ── Phased loading ─────────────────────────────────────────────────────
    // Bash pipeline echoes "WT_PHASE:<name>" before each stage; SplitParser on
    // reprocessProc updates currentPhase. progress is the phase index over the
    // total — drives the indeterminate-but-not-quite top strip and the button
    // label so the user sees the apply moving, not a frozen spinner.
    property string currentPhase: ""
    // "apply" sits before "extract": that's the real step order in the
    // both/wallpaper pipelines (wallpaper switches first, theme follows).
    // colors-mode runs its instant jq snap-back after extract, which briefly
    // steps the bar backward — invisible in practice (<50ms step).
    readonly property var phaseOrder: ["start", "remap", "tune", "apply", "extract", "history", "done"]
    readonly property real progress: {
        if (!processing) return 0
        const i = phaseOrder.indexOf(currentPhase)
        if (i < 0) return 0
        return i / (phaseOrder.length - 1)
    }
    readonly property string phaseLabel: {
        switch (currentPhase) {
            case "start":   return qsTr("Starting")
            case "remap":   return qsTr("Quantising palette")
            case "tune":    return qsTr("Tuning image")
            case "extract": return qsTr("Extracting theme")
            case "apply":   return qsTr("Applying wallpaper")
            case "history": return qsTr("Saving snapshot")
            case "done":    return qsTr("Finalising")
            case "error":   return qsTr("Failed — theme not applied")
            default:        return qsTr("Working")
        }
    }

        GroupHeading { text: qsTr("Recent") }
        // ── History row ─────────────────────────────────────────────────
        // Newest output first. Each chip shows a visual preview of the tuned
        // wallpaper with overlaid primary/secondary/tertiary colors.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: root.history.length > 0

            RowLayout {
                Layout.fillWidth: true; spacing: 4
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Recent Themes")
                    font.pixelSize: Appearance.font.pixelSize.smaller - 1
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0; opacity: 0.5
                }
                StyledText {
                    text: root.history.length + ""
                    font.pixelSize: Appearance.font.pixelSize.smaller - 2
                    color: Appearance.colors.colOnLayer0; opacity: 0.35
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: 48
                clip: true
                ListView {
                    id: walltuneHistList
                    anchors.fill: parent
                    orientation: ListView.Horizontal
                    spacing: 5
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.history

                    delegate: Rectangle {
                        id: histChip
                        required property var modelData
                        required property int index
                        implicitWidth: 64
                        height: ListView.view.height
                        radius: 8
                        color: histChipHov.hovered
                            ? Appearance.colors.colLayer2
                            : Appearance.colors.colLayer1
                        
                        readonly property bool isCurrent: {
                            const cw = modelData.wallpaper
                            if (!cw || cw === "" || cw !== root.sourceWall) return false
                            const s = modelData.state
                            if (!s) return false
                            
                            // Compare core slider states with float tolerance
                            if (Math.abs((s.slVibrance !== undefined ? s.slVibrance : 50) - root.slVibrance) > 0.01) return false
                            if (Math.abs((s.slContrast !== undefined ? s.slContrast : 50) - root.slContrast) > 0.01) return false
                            if (Math.abs((s.slTemperature !== undefined ? s.slTemperature : 50) - root.slTemperature) > 0.01) return false
                            if (Math.abs((s.slBrightness !== undefined ? s.slBrightness : 50) - root.slBrightness) > 0.01) return false
                            if (Math.abs((s.slSaturation !== undefined ? s.slSaturation : 50) - root.slSaturation) > 0.01) return false
                            if (Math.abs((s.slHueShift !== undefined ? s.slHueShift : 50) - root.slHueShift) > 0.01) return false
                            if (Math.abs((s.slHighlight !== undefined ? s.slHighlight : 50) - root.slHighlight) > 0.01) return false
                            if (Math.abs((s.slShadow !== undefined ? s.slShadow : 50) - root.slShadow) > 0.01) return false
                            if (Math.abs((s.slGrain !== undefined ? s.slGrain : 0) - root.slGrain) > 0.01) return false
                            if (Math.abs((s.slSharpness !== undefined ? s.slSharpness : 50) - root.slSharpness) > 0.01) return false
                            
                            // Compare mode and options
                            if ((s.selectedMode !== undefined ? s.selectedMode : "") !== root.selectedMode) return false
                            if ((s.selectedTheory !== undefined ? s.selectedTheory : "") !== root.selectedTheory) return false
                            if ((s.selectedStyle !== undefined ? s.selectedStyle : "") !== root.selectedStyle) return false
                            if ((s.selectedPractical !== undefined ? s.selectedPractical : "") !== root.selectedPractical) return false
                            if ((s.remapPalette !== undefined ? s.remapPalette : "") !== root.remapPalette) return false
                            if ((s.remapColors !== undefined ? s.remapColors : 32) !== root.remapColors) return false
                            if ((s.remapDither !== undefined ? s.remapDither : "FloydSteinberg2x2") !== root.remapDither) return false
                            if ((s.darkMode !== undefined ? s.darkMode : true) !== root.darkMode) return false
                            if ((s.applyMode !== undefined ? s.applyMode : "both") !== root.applyMode) return false
                            
                            // Compare tone curve points
                            if (s.curvePoints && Array.isArray(s.curvePoints)) {
                                if (s.curvePoints.length !== root.curvePoints.length) return false
                                for (let i = 0; i < s.curvePoints.length; i++) {
                                    const p1 = s.curvePoints[i]
                                    const p2 = root.curvePoints[i]
                                    if (!p2 || Math.abs(p1[0] - p2[0]) > 0.001 || Math.abs(p1[1] - p2[1]) > 0.001) return false
                                }
                            } else if (!root.curveIsIdentity()) {
                                return false
                            }
                            
                            return true
                        }
                        
                        border.width: isCurrent ? 2 : 1
                        border.color: isCurrent ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                        Behavior on color { ColorAnimation { duration: 100 } }
                        
                        // Content container for clipping
                        Rectangle {
                            id: innerClipContainer
                            anchors.fill: parent
                            anchors.margins: parent.border.width
                            radius: histChip.radius - parent.border.width
                            color: "transparent"
                            clip: true
                            
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: innerClipContainer.width; height: innerClipContainer.height
                                    radius: innerClipContainer.radius
                                }
                            }
                            
                            // Visual wallpaper thumbnail
                            Image {
                                id: thumbImg
                                anchors.fill: parent
                                source: {
                                    if (modelData.thumbnail && modelData.thumbnail !== "") {
                                        return "file://" + modelData.thumbnail
                                    }
                                    if (modelData.wallpaper && modelData.wallpaper !== "" && !/processed(-[ab])?\.png$/.test(modelData.wallpaper)) {
                                        return "file://" + modelData.wallpaper
                                    }
                                    return ""
                                }
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                asynchronous: true
                                visible: source != ""
                            }
                            
                            // Fallback stripes if no visual thumbnail is available
                            Row {
                                anchors.fill: parent
                                anchors.margins: 4
                                spacing: 2
                                visible: thumbImg.source == ""
                                
                                Rectangle {
                                    width: (parent.width - 4) / 3; height: parent.height
                                    radius: 4
                                    color: modelData.primary || "#444"
                                }
                                Rectangle {
                                    width: (parent.width - 4) / 3; height: parent.height
                                    radius: 4
                                    color: modelData.secondary || "#444"
                                }
                                Rectangle {
                                    width: (parent.width - 4) / 3; height: parent.height
                                    radius: 4
                                    color: modelData.tertiary || "#444"
                                }
                            }
                            
                            // Subtle bottom overlay for dots on visual thumbnail
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: 18
                                color: Qt.rgba(0, 0, 0, 0.6)
                                visible: thumbImg.source != ""
                                
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Rectangle {
                                        width: 10; height: 10; radius: 5
                                        color: modelData.primary || "transparent"
                                        border.width: modelData.primary ? 1 : 0
                                        border.color: "#ffffff"
                                    }
                                    Rectangle {
                                        width: 10; height: 10; radius: 5
                                        color: modelData.secondary || "transparent"
                                        border.width: modelData.secondary ? 1 : 0
                                        border.color: "#ffffff"
                                    }
                                    Rectangle {
                                        width: 10; height: 10; radius: 5
                                        color: modelData.tertiary || "transparent"
                                        border.width: modelData.tertiary ? 1 : 0
                                        border.color: "#ffffff"
                                    }
                                }
                            }
                        }

                        HoverHandler { margin: Appearance.sizes.touchSlop; id: histChipHov }
                        TapHandler { margin: Appearance.sizes.touchSlop; onTapped: root.applyHistoryEntry(modelData) }
                    }
                }
            }
        }

    // ── Active mix summary ─────────────────────────────────────────────────
    // Surfaces every non-default section choice as a dismissable chip so the
    // user can see (and undo) the full stack at a glance, even when every
    // section dropdown is collapsed.
    // Draggable order of the "Active mix" chips. The relative order of
    // theory/style/practical/remap is passed to switchwall.sh as --mix-order
    // and drives the order palette_transform.py applies them (the result
    // genuinely differs by order). "mode" (matugen extraction) and "curve"
    // (image-stage LUT) run at fixed pipeline stages, so they can be dragged
    // for tidiness but don't change the palette-transform order.
    property var mixOrder: ["mode", "theory", "style", "practical", "remap", "curve"]

    readonly property var activeMix: {
        const out = []
        if (selectedMode !== "") {
            const m = extractModes.find(x => x.id === selectedMode)
            out.push({ section: qsTr("Mode"), label: m ? m.label : selectedMode,
                       color: m ? m.color : Appearance.colors.colPrimary, key: "mode" })
        }
        if (selectedTheory !== "") {
            const m = theoryModes.find(x => x.id === selectedTheory)
            out.push({ section: qsTr("Theory"), label: m ? m.label : selectedTheory,
                       color: m ? m.color : Appearance.colors.colPrimary, key: "theory" })
        }
        if (selectedStyle !== "") {
            const m = styleModes.find(x => x.id === selectedStyle)
            out.push({ section: qsTr("Style"), label: m ? m.label : selectedStyle,
                       color: m ? m.color : Appearance.colors.colPrimary, key: "style" })
        }
        if (selectedPractical !== "") {
            const m = practicalModes.find(x => x.id === selectedPractical)
            out.push({ section: qsTr("Practical"), label: m ? m.label : selectedPractical,
                       color: m ? m.color : Appearance.colors.colPrimary, key: "practical" })
        }
        if (remapPalette !== "") {
            const m = remapPalettes.find(x => x.id === remapPalette)
            out.push({ section: qsTr("Remap"), label: m ? m.label : remapPalette,
                       color: m ? m.color : Appearance.colors.colPrimary, key: "remap" })
        }
        if (!curveIsIdentity()) {
            out.push({ section: qsTr("Curve"), label: qsTr("Custom"),
                       color: Appearance.colors.colPrimary, key: "curve" })
        }
        // Order the visible chips by the user's dragged mixOrder. Keys not in
        // mixOrder (shouldn't happen) sort to the end.
        const ord = root.mixOrder
        out.sort((a, b) => {
            const ia = ord.indexOf(a.key), ib = ord.indexOf(b.key)
            return (ia < 0 ? 999 : ia) - (ib < 0 ? 999 : ib)
        })
        return out
    }

    // Move `srcKey` to sit immediately before `dstKey` in mixOrder, then persist.
    function moveMixBefore(srcKey, dstKey) {
        if (!srcKey || srcKey === dstKey) return
        const arr = root.mixOrder.slice()
        const from = arr.indexOf(srcKey)
        if (from < 0) return
        arr.splice(from, 1)
        let to = arr.indexOf(dstKey)
        if (to < 0) to = arr.length
        arr.splice(to, 0, srcKey)
        root.mixOrder = arr
        saveState()
    }

    // CSV of just the palette-transform chips, in their current order, for
    // switchwall.sh --mix-order. mode/curve are excluded (fixed stages).
    function mixOrderArg() {
        const steps = ["theory", "style", "practical", "remap"]
        return root.mixOrder.filter(k => steps.indexOf(k) >= 0).join(",")
    }

    function clearMix(key) {
        switch (key) {
            case "mode":      selectedMode = ""; break
            case "theory":    selectedTheory = ""; break
            case "style":     selectedStyle = ""; break
            case "practical": selectedPractical = ""; break
            case "remap":     remapPalette = ""; break
            case "curve":     resetCurve(); break
        }
    }
    function openMixSection(key) {
        switch (key) {
            case "theory":    theoryOpen = true; break
            case "style":     styleOpen = true; break
            case "practical": practicalOpen = true; break
            case "remap":     remapOpen = true; break
            case "curve":     curveOpen = true; break
        }
    }

    property bool parallaxOpen:  false

    // Section dropdowns (default closed)
    property bool theoryOpen:    false
    property bool styleOpen:     false
    property bool practicalOpen: false
    property bool curveOpen:     false
    property bool remapOpen:     false
    // Adjustments was the one section here with no disclosure: ten full-width
    // sliders, always expanded, directly above Reprocess. Every peer section
    // collapses, so it now does too — and the header carries a count so a
    // closed section can still say that something inside it is set.
    property bool adjustOpen:    false
    readonly property int adjustChangedCount: {
        let n = 0
        for (const d of root.sliderDefs)
            if (Math.round(root[d.prop] - 50) !== 0) n++
        return n
    }

    // Palette remap (post-process via rdmcpape)
    property string remapPalette: ""        // "" = off, "matugen", or named ("pastel", etc.)
    property int    remapColors:  32        // 8|16|32|64|128
    property string remapDither:  "FloydSteinberg2x2"  // none|2x2|8x8|16x16

    // Tone curve — list of [x,y] pairs in [0,1]. Identity by default.
    property var curvePoints: [[0, 0], [1, 1]]
    // Histogram of current wallpaper (256 bins). Refetched on wallpaper change.
    property var histogram: []
    function curveIsIdentity() {
        if (curvePoints.length !== 2) return false
        const [a, b] = curvePoints
        return a[0] === 0 && a[1] === 0 && b[0] === 1 && b[1] === 1
    }
    function resetCurve() { curvePoints = [[0, 0], [1, 1]] }

    // Hard cap so the panel doesn't push past the screen.
    readonly property int maxContentHeight: 640

    // Sliders 0..100, neutral = 50
    property real slVibrance:    50
    property real slContrast:    50
    property real slTemperature: 50
    property real slBrightness:  50
    property real slSaturation:  50
    property real slHueShift:    50
    property real slHighlight:   50
    property real slShadow:      50
    property real slGrain:       0
    property real slSharpness:   50

    // Live color pairs — direct bindings to m3colors, fully reactive
    // QML tracks each property access here as a binding dependency
    readonly property color c0a: Qt.hsla(Appearance.m3colors.m3primary.hslHue, 0.15, 0.18, 1)
    readonly property color c0b: Appearance.m3colors.m3primary
    readonly property color c1a: Appearance.colors.colLayer1
    readonly property color c1b: Appearance.colors.colOnLayer0
    readonly property color c2a: Appearance.m3colors.m3tertiary
    readonly property color c2b: Appearance.m3colors.m3secondary
    readonly property color c3a: Qt.hsla(Appearance.m3colors.m3primary.hslHue, 0.25, 0.10, 1)
    readonly property color c3b: Qt.hsla(Appearance.m3colors.m3primary.hslHue, 0.85, 0.82, 1)
    readonly property color c4a: Qt.hsla(Appearance.m3colors.m3primary.hslHue, 0.0, 0.45, 1)
    readonly property color c4b: Appearance.m3colors.m3primary
    readonly property color c5a: Appearance.m3colors.m3secondaryContainer
    readonly property color c5b: Appearance.m3colors.m3tertiaryContainer
    readonly property color c6a: Appearance.colors.colLayer2
    readonly property color c6b: Qt.hsla(Appearance.m3colors.m3primary.hslHue, 0.80, 0.72, 1)
    readonly property color c7a: Qt.hsla(Appearance.m3colors.m3primary.hslHue, 0.20, 0.08, 1)
    readonly property color c7b: Appearance.m3colors.m3primaryContainer
    readonly property color c8a: Appearance.colors.colLayer0
    readonly property color c8b: Appearance.colors.colLayer2
    readonly property color c9a: Appearance.colors.colLayer1
    readonly property color c9b: Appearance.m3colors.m3primary

    readonly property var sliderDefs: [
        { label: "Vibrance",    prop: "slVibrance",    ai: "c0a", bi: "c0b" },
        { label: "Contrast",    prop: "slContrast",    ai: "c1a", bi: "c1b" },
        { label: "Temperature", prop: "slTemperature", ai: "c2a", bi: "c2b" },
        { label: "Brightness",  prop: "slBrightness",  ai: "c3a", bi: "c3b" },
        { label: "Saturation",  prop: "slSaturation",  ai: "c4a", bi: "c4b" },
        { label: "Hue Shift",   prop: "slHueShift",    ai: "c5a", bi: "c5b" },
        { label: "Highlight",   prop: "slHighlight",   ai: "c6a", bi: "c6b" },
        { label: "Shadow",      prop: "slShadow",      ai: "c7a", bi: "c7b" },
        { label: "Grain",       prop: "slGrain",       ai: "c8a", bi: "c8b" },
        { label: "Sharpness",   prop: "slSharpness",   ai: "c9a", bi: "c9b" },
    ]

    readonly property var extractModes: [
        { id: "",                    label: "Auto",       color: "#7c8af7" },
        { id: "scheme-content",      label: "Content",    color: "#4caf7d" },
        { id: "scheme-expressive",   label: "Expressive", color: "#f7a8c4" },
        { id: "scheme-fidelity",     label: "Fidelity",   color: "#f7c55a" },
        { id: "scheme-fruit-salad",  label: "Fruit Salad",color: "#f76c6c" },
        { id: "scheme-monochrome",   label: "Monochrome", color: "#a0a0b0" },
        { id: "scheme-neutral",      label: "Neutral",    color: "#9e8fb2" },
        { id: "scheme-rainbow",      label: "Rainbow",    color: "#5ab8f7" },
        { id: "scheme-tonal-spot",   label: "Tonal Spot", color: "#c4a4f7" },
    ]

    // Color Theory — post-extraction palette rotation
    readonly property var theoryModes: [
        { id: "",              label: "Off",           color: "#666876" },
        { id: "mono",          label: "Mono",          color: "#a8a8b8" },
        { id: "analogous",     label: "Analogous",     color: "#5ab8f7" },
        { id: "complementary", label: "Complement",    color: "#f7a85a" },
        { id: "triadic",       label: "Triadic",       color: "#c7f75a" },
        { id: "split",         label: "Split-Comp",    color: "#f75ac7" },
        { id: "tetradic",      label: "Tetradic",      color: "#5af7a8" },
    ]

    // Style — HSL filter on accents
    readonly property var styleModes: [
        { id: "",          label: "Off",      color: "#666876" },
        { id: "pastel",    label: "Pastel",   color: "#f7c5d8" },
        { id: "muted",     label: "Muted",    color: "#9aa1ae" },
        { id: "bright",    label: "Bright",   color: "#ffd400" },
        { id: "colorful",  label: "Colorful", color: "#ff5a5a" },
        { id: "material",  label: "Material", color: "#7c8af7" },
    ]

    // Practical — usability passes
    readonly property var practicalModes: [
        { id: "",              label: "Off",           color: "#666876" },
        { id: "high_contrast", label: "High Contrast", color: "#ffffff" },
        { id: "duotone",       label: "Duotone",       color: "#f76ca8" },
    ]

    // Palette Remap — names match rdmcpape's --palette / --matugen flags
    // and resolve via ~/.config/quickshell/ii/scripts/colors/palettes.json.
    readonly property var remapPalettes: [
        { id: "",            label: "Off",        color: "#666876" },
        { id: "matugen",     label: "Matugen",    color: "#7c8af7" },

        // — In-house —
        { id: "pastel",      label: "Pastel",     color: "#e0d8f5" },
        { id: "accent",      label: "Accent",     color: "#ff9aa2" },
        { id: "base",        label: "Base",       color: "#7d83a0" },
        { id: "sec",         label: "Sec",        color: "#ffc64b" },
        { id: "default",     label: "Default",    color: "#82aaff" },
        { id: "tone",        label: "Tone",       color: "#89dceb" },
        { id: "hue",         label: "Hue",        color: "#c8ff9c" },
        { id: "extra",       label: "Extra",      color: "#b090ff" },
        { id: "fruit_base",  label: "Fruit Base", color: "#f5e0d0" },
        { id: "fruit_soft",  label: "Fruit Soft", color: "#e8c0a8" },
        { id: "fruit_dim",   label: "Fruit Dim",  color: "#7a4a60" },

        // — Popular themes —
        { id: "catppuccin_mocha",     label: "Catppuccin Mocha",     color: "#cba6f7" },
        { id: "catppuccin_macchiato", label: "Catppuccin Macchiato", color: "#c6a0f6" },
        { id: "catppuccin_frappe",    label: "Catppuccin Frappé",    color: "#ca9ee6" },
        { id: "catppuccin_latte",     label: "Catppuccin Latte",     color: "#8839ef" },
        { id: "gruvbox_dark",         label: "Gruvbox Dark",         color: "#fabd2f" },
        { id: "gruvbox_light",        label: "Gruvbox Light",        color: "#d79921" },
        { id: "gruvbox_material_dark",label: "Gruvbox Material",     color: "#d8a657" },
        { id: "nord",                 label: "Nord",                 color: "#88c0d0" },
        { id: "nordic",               label: "Nordic",               color: "#81a1c1" },
        { id: "dracula",              label: "Dracula",              color: "#bd93f9" },
        { id: "tokyo_night",          label: "Tokyo Night",          color: "#7aa2f7" },
        { id: "tokyo_night_storm",    label: "Tokyo Storm",          color: "#7dcfff" },
        { id: "tokyo_night_day",      label: "Tokyo Day",            color: "#0db9d7" },
        { id: "kanagawa",             label: "Kanagawa",             color: "#7e9cd8" },
        { id: "kanagawa_dragon",      label: "Kanagawa Dragon",      color: "#8ba4b0" },
        { id: "rose_pine",            label: "Rosé Pine",            color: "#ebbcba" },
        { id: "rose_pine_moon",       label: "Rosé Pine Moon",       color: "#c4a7e7" },
        { id: "rose_pine_dawn",       label: "Rosé Pine Dawn",       color: "#b4637a" },
        { id: "everforest_dark",      label: "Everforest Dark",      color: "#a7c080" },
        { id: "everforest_light",     label: "Everforest Light",     color: "#8da101" },
        { id: "solarized_dark",       label: "Solarized Dark",       color: "#268bd2" },
        { id: "solarized_light",      label: "Solarized Light",      color: "#cb4b16" },
        { id: "one_dark",             label: "One Dark",             color: "#61afef" },
        { id: "one_light",            label: "One Light",            color: "#4078f2" },
        { id: "monokai",              label: "Monokai",              color: "#f92672" },
        { id: "monokai_pro",          label: "Monokai Pro",          color: "#ff6188" },
        { id: "ayu_dark",             label: "Ayu Dark",             color: "#ffb454" },
        { id: "ayu_mirage",           label: "Ayu Mirage",           color: "#ffcc66" },
        { id: "github_dark",          label: "GitHub Dark",          color: "#58a6ff" },
        { id: "github_light",         label: "GitHub Light",         color: "#0969da" },
        { id: "doom_one",             label: "Doom One",             color: "#51afef" },
        { id: "nightfox",             label: "Nightfox",             color: "#719cd6" },
        { id: "carbonfox",            label: "Carbonfox",            color: "#78a9ff" },
        { id: "oxocarbon",            label: "Oxocarbon",            color: "#33b1ff" },
        { id: "melange_dark",         label: "Melange Dark",         color: "#ebc06d" },
        { id: "melange_light",        label: "Melange Light",        color: "#a06d00" },
        { id: "iceberg",              label: "Iceberg",              color: "#84a0c6" },
        { id: "horizon",              label: "Horizon",              color: "#e95678" },
        { id: "edge_dark",            label: "Edge Dark",            color: "#5dc2a3" },
        { id: "moonfly",              label: "Moonfly",              color: "#80a0ff" },
        { id: "matrix",               label: "Matrix",               color: "#00ff41" },
        { id: "vapor",                label: "Vapor",                color: "#ff77ff" },
        { id: "outrun",               label: "Outrun",               color: "#ff007c" },
        { id: "biscuit",              label: "Biscuit",              color: "#d2a679" },
    ]
    readonly property var ditherModes: [ "none", "FloydSteinberg2x2", "FloydSteinberg", "8x8", "16x16" ]
    readonly property var colorOptions: [ 8, 16, 32, 64, 128 ]

    readonly property var transitions: [
        { id: "fade",  label: "Fade",  icon: "blur_on"      },
        { id: "slide", label: "Slide", icon: "swap_horiz"   },
        { id: "zoom",  label: "Zoom",  icon: "zoom_in_map"  },
        { id: "wipe",  label: "Wipe",  icon: "format_paint" },
    ]

    // Debounce: auto-reprocess 700ms after last slider/mode change
    Timer {
        id: debounce
        interval: 700
        repeat: false
        onTriggered: root.reprocess()
    }

    // State save debounce (faster, just writes JSON)
    Timer {
        id: saveDeb
        interval: 300
        repeat: false
        onTriggered: root.saveState()
    }

    onSlVibranceChanged:    { debounce.restart(); saveDeb.restart() }
    onSlContrastChanged:    { debounce.restart(); saveDeb.restart() }
    onSlTemperatureChanged: { debounce.restart(); saveDeb.restart() }
    onSlBrightnessChanged:  { debounce.restart(); saveDeb.restart() }
    onSlSaturationChanged:  { debounce.restart(); saveDeb.restart() }
    onSlHueShiftChanged:    { debounce.restart(); saveDeb.restart() }
    onSlHighlightChanged:   { debounce.restart(); saveDeb.restart() }
    onSlShadowChanged:      { debounce.restart(); saveDeb.restart() }
    onSlGrainChanged:       { debounce.restart(); saveDeb.restart() }
    onSlSharpnessChanged:   { debounce.restart(); saveDeb.restart() }
    onSelectedModeChanged:      { debounce.restart(); saveDeb.restart() }
    onSelectedTheoryChanged:    { debounce.restart(); saveDeb.restart() }
    onSelectedStyleChanged:     { debounce.restart(); saveDeb.restart() }
    onSelectedPracticalChanged: { debounce.restart(); saveDeb.restart() }
    onCurvePointsChanged:       { debounce.restart(); saveDeb.restart() }
    onRemapPaletteChanged:      { debounce.restart(); saveDeb.restart() }
    onRemapColorsChanged:       { debounce.restart(); saveDeb.restart() }
    onRemapDitherChanged:       { debounce.restart(); saveDeb.restart() }
    onDarkModeChanged:          { debounce.restart(); saveDeb.restart() }
    onApplyModeChanged:         { debounce.restart(); saveDeb.restart() }
    onStackableChanged:         { debounce.restart(); saveDeb.restart() }
    onCurrentWallChanged: {
        // If the user picked a fresh wallpaper (not one of WallTune's output
        // files), remember it as the source so Colors / Wallpaper modes can
        // reset back to it.
        if (currentWall
            && !/processed(-[ab])?\.png$/.test(currentWall)
            && !currentWall.includes("/walltune/")) {
            sourceWall = currentWall
            saveDeb.restart()
        }
        refreshHistogram()
    }

    // Set when reprocess() is called while a previous run is still in flight.
    // We kill the in-flight bash, and once it actually dies the rerunTimer
    // fires a fresh run with the *current* state — so dragging a slider doesn't
    // freeze the panel waiting for the old apply to finish.
    property bool _rerunPending: false

    Process {
        id: reprocessProc
        stdout: SplitParser {
            onRead: line => {
                const t = (line || "").trim()
                if (t.indexOf("WT_PHASE:") === 0) root.currentPhase = t.substring(9)
            }
        }
        onRunningChanged: {
            if (running) {
                root.currentPhase = "start"
                watchdogTimer.restart()
            } else if (root._rerunPending) {
                // Cancelled to apply newer state — keep `processing` true so
                // the button doesn't flash to "Reprocess" between cancel and
                // restart; rerunTimer will re-enter reprocess().
                watchdogTimer.stop()
                root._rerunPending = false
                root.currentPhase = "start"
                rerunTimer.restart()
            } else {
                watchdogTimer.stop()
                root.processing = false
                if (root.currentPhase === "error") {
                    // Failed run (ERR trap / watchdog / missing source):
                    // keep the red "Failed" label up long enough to be seen
                    // instead of pretending the apply finished.
                    errorHoldTimer.restart()
                } else {
                    root.currentPhase = "done"
                    phaseClearTimer.restart()
                }
            }
        }
    }
    // Hold the "done" state briefly so the bar visibly fills before fading,
    // then clear so a stale phase doesn't flash on next run before SplitParser
    // delivers the first marker.
    Timer { id: phaseClearTimer; interval: 500; repeat: false; onTriggered: root.currentPhase = "" }
    Timer { id: errorHoldTimer; interval: 6000; repeat: false; onTriggered: root.currentPhase = "" }
    Timer { id: rerunTimer; interval: 60; repeat: false; onTriggered: root.reprocess() }
    // Last line of defence: a pipeline that produces no exit for minutes
    // (hung dbus call, blocked helper, dead pipe) used to freeze the panel
    // on its last phase forever. Kill it and surface the failure instead.
    Timer {
        id: watchdogTimer
        interval: 180000; repeat: false
        onTriggered: {
            if (!reprocessProc.running) return
            console.warn("[WallTune] reprocess watchdog fired — killing hung pipeline at phase:", root.currentPhase)
            root.currentPhase = "error"
            root._rerunPending = false
            reprocessProc.running = false
        }
    }

    Process { id: saveProc }

    // ── WallTune history ────────────────────────────────────────────────
    // Newest first. Each entry: { ts, primary, secondary, tertiary, wallpaper, state }
    // Backed by the shared WallpaperRecents singleton.
    readonly property var history: WallpaperRecents.walltuneHistory

    function refreshWalltuneHistory() {
        WallpaperRecents.refreshWalltuneHistory()
    }
    function applyHistoryEntry(entry) {
        const s = entry?.state
        if (!s) return
        if (entry.wallpaper && entry.wallpaper !== "" && !/processed(-[ab])?\.png$/.test(entry.wallpaper) && !entry.wallpaper.includes("/walltune/")) {
            root.sourceWall = entry.wallpaper
        } else if (s.sourceWall && s.sourceWall !== "" && !/processed(-[ab])?\.png$/.test(s.sourceWall) && !s.sourceWall.includes("/walltune/")) {
            root.sourceWall = s.sourceWall
        }
        if (s.slVibrance    !== undefined) root.slVibrance    = s.slVibrance
        if (s.slContrast    !== undefined) root.slContrast    = s.slContrast
        if (s.slTemperature !== undefined) root.slTemperature = s.slTemperature
        if (s.slBrightness  !== undefined) root.slBrightness  = s.slBrightness
        if (s.slSaturation  !== undefined) root.slSaturation  = s.slSaturation
        if (s.slHueShift    !== undefined) root.slHueShift    = s.slHueShift
        if (s.slHighlight   !== undefined) root.slHighlight   = s.slHighlight
        if (s.slShadow      !== undefined) root.slShadow      = s.slShadow
        if (s.slGrain       !== undefined) root.slGrain       = s.slGrain
        if (s.slSharpness   !== undefined) root.slSharpness   = s.slSharpness
        if (s.selectedMode      !== undefined) root.selectedMode      = s.selectedMode
        if (s.selectedTheory    !== undefined) root.selectedTheory    = s.selectedTheory
        if (s.selectedStyle     !== undefined) root.selectedStyle     = s.selectedStyle
        if (s.selectedPractical !== undefined) root.selectedPractical = s.selectedPractical
        if (s.mixOrder !== undefined && Array.isArray(s.mixOrder) && s.mixOrder.length) root.mixOrder = s.mixOrder
        if (s.curvePoints       !== undefined && Array.isArray(s.curvePoints) && s.curvePoints.length >= 2)
            root.curvePoints    = s.curvePoints
        if (s.remapPalette  !== undefined) root.remapPalette  = s.remapPalette
        if (s.remapColors   !== undefined) root.remapColors   = s.remapColors
        if (s.remapDither   !== undefined) root.remapDither   = s.remapDither
        if (s.darkMode      !== undefined) root.darkMode      = s.darkMode
        if (s.applyMode     !== undefined) root.applyMode     = s.applyMode
        if (s.stackable     !== undefined) root.stackable     = s.stackable

        debounce.restart()
        saveDeb.restart()
    }
    Connections {
        target: GlobalStates
        function onWallTuneOpenChanged() {
            if (GlobalStates.wallTuneOpen) root.refreshWalltuneHistory()
        }
    }
    // Refresh the list a moment after each successful reprocess so the new
    // entry shows up.
    Connections {
        target: reprocessProc
        function onRunningChanged() {
            if (!reprocessProc.running) refreshWalltuneHistory()
        }
    }

    Process {
        id: histProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (Array.isArray(d) && d.length === 256) root.histogram = d
                } catch(e) {}
            }
        }
    }
    function refreshHistogram() {
        if (!currentWall || currentWall === "") return
        histProc.command = [home + "/.local/bin/tinct", "image", "histogram", currentWall]
        histProc.running = true
    }
    Process { id: blueScanProc; stdout: StdioCollector { onStreamFinished: {
        root.blueprints = text.trim().split("\n")
            .filter(l => l.trim())
            .map(p => ({ path: p.trim(), name: p.trim().split("/").pop().replace(".json","") }))
    }}}
    Process { id: loadProc; stdout: StdioCollector { onStreamFinished: {
        try {
            const s = JSON.parse(text)
            if (s.slVibrance    !== undefined) root.slVibrance    = s.slVibrance
            if (s.slContrast    !== undefined) root.slContrast    = s.slContrast
            if (s.slTemperature !== undefined) root.slTemperature = s.slTemperature
            if (s.slBrightness  !== undefined) root.slBrightness  = s.slBrightness
            if (s.slSaturation  !== undefined) root.slSaturation  = s.slSaturation
            if (s.slHueShift    !== undefined) root.slHueShift    = s.slHueShift
            if (s.slHighlight   !== undefined) root.slHighlight   = s.slHighlight
            if (s.slShadow      !== undefined) root.slShadow      = s.slShadow
            if (s.slGrain       !== undefined) root.slGrain       = s.slGrain
            if (s.slSharpness   !== undefined) root.slSharpness   = s.slSharpness
            if (s.selectedMode      !== undefined) root.selectedMode      = s.selectedMode
            if (s.selectedTheory    !== undefined) root.selectedTheory    = s.selectedTheory
            if (s.selectedStyle     !== undefined) root.selectedStyle     = s.selectedStyle
            if (s.selectedPractical !== undefined) root.selectedPractical = s.selectedPractical
            if (s.mixOrder !== undefined && Array.isArray(s.mixOrder) && s.mixOrder.length) root.mixOrder = s.mixOrder
            if (s.curvePoints       !== undefined && Array.isArray(s.curvePoints) && s.curvePoints.length >= 2)
                root.curvePoints    = s.curvePoints
            if (s.remapPalette      !== undefined) root.remapPalette      = s.remapPalette
            if (s.remapColors       !== undefined) root.remapColors       = s.remapColors
            if (s.remapDither       !== undefined) root.remapDither       = s.remapDither
            if (s.darkMode          !== undefined) root.darkMode          = s.darkMode
            if (s.applyMode         !== undefined) root.applyMode         = s.applyMode
            if (s.stackable         !== undefined) root.stackable         = s.stackable
            if (s.sourceWall        !== undefined) root.sourceWall        = s.sourceWall
            if (s.lastProcessedSlot !== undefined) root.lastProcessedSlot = s.lastProcessedSlot

            // Reconcile persisted sourceWall against the actual current
            // wallpaper. If the user changed wallpaper while walltune was
            // closed (e.g. via the random-wallpaper script or wallpaper
            // picker), `onCurrentWallChanged` never fired for it — so the
            // restored sourceWall would be stale and reprocess would edit
            // the *previous* wallpaper. Snap to current if it's a real
            // (non-walltune) image and differs from the loaded value.
            const cw = root.currentWall
            const isWalltuneOutput = cw && (/processed(-[ab])?\.png$/.test(cw)
                                         || cw.includes("/walltune/"))
            if (cw && !isWalltuneOutput && cw !== root.sourceWall) {
                root.sourceWall = cw
            }
        } catch(e) {}
    }}}

    property bool processing: false

    function reprocess() {
        if (!currentWall || currentWall === "" || currentWall === "--help") return
        // If a previous reprocess is still running, kill it and queue a fresh
        // one. onRunningChanged on reprocessProc fires rerunTimer when the
        // killed process is fully torn down. This way fast slider changes
        // always end up applying the *latest* state, not the stale in-flight
        // one — and the user doesn't have to wait 5 s for the old run to
        // finish before their new tweak takes effect.
        if (reprocessProc.running) {
            _rerunPending = true
            reprocessProc.running = false
            return
        }
        // Video: the UI shows the notice instead.
        if (sourceIsVideo) {
            processing = false
            return
        }
        processing = true

        const scriptDir = home + "/.config/quickshell/ii/scripts/colors"
        const mode      = darkMode ? "dark" : "light"
        // Persistent location — must survive a reboot, since this path is
        // saved into config.json as background.wallpaperPath. /tmp is cleared.
        const cacheDir  = home + "/.cache/quickshell/walltune"
        // Alternate between two filenames so wallpaperPath actually changes
        // every apply. Without this, Image.source stays bound to the same
        // string and never reloads — leaving the OLD processed image on
        // screen even though the file was overwritten with new content.
        // (Path-change is the only reload trigger; QML Image doesn't watch
        // the underlying file's mtime.)
        // Always write to the slot the bg layer is NOT currently showing,
        // so wallpaperPath actually changes and QML's Image cache reloads.
        // Basing the choice on `currentWall` (the live displayed path) is
        // robust to cancelled mid-runs — the previous lastProcessedSlot
        // counter could drift out of sync if a run was killed before it
        // finished writing, leaving the next run to overwrite the same slot
        // that's already on screen. Same-path write → no reload → looks
        // exactly like the wallpaper "stacking" effects on top of itself.
        const currentIsA = /processed-a\.png$/.test(currentWall || "")
        const currentIsB = /processed-b\.png$/.test(currentWall || "")
        const slot       = currentIsA ? "b" : (currentIsB ? "a"
                          : (root.lastProcessedSlot === "a" ? "b" : "a"))
        const tmp        = cacheDir + "/processed-" + slot + ".png"
        root.lastProcessedSlot = slot
        const schemeArg = selectedMode !== "" ? "--type " + selectedMode : ""

        // Map sliders (0-100, neutral=50) to ImageMagick values
        const brightness = Math.round(slBrightness + 50)        // 50-150
        const saturation = Math.round(slSaturation * 2)         // 0-200
        const hue        = Math.round(slHueShift * 2)           // 0-200
        const contrast   = Math.round((slContrast - 50) * 2)    // -100..+100
        const sharpness  = slSharpness > 50 ? ((slSharpness - 50) / 10).toFixed(1) : "0"
        const blur       = slSharpness < 50 ? ((50 - slSharpness) / 20).toFixed(1) : "0"
        const grain      = Math.round(slGrain * 0.4)

        // Temperature: warm/cool via RGB channel shift
        const temp   = slTemperature - 50
        const tBoost = Math.abs(Math.round(temp * 0.8))

        // The un-edited source, so edits don't compound across reprocesses.
        const srcWall = (sourceWall && sourceWall !== "") ? sourceWall : currentWall

        // baseImage = what the chain READS from before any per-run edits.
        //   stackable OFF (default): srcWall — every apply starts from the
        //                            original; sliders are absolute settings.
        //   stackable ON           : currently-displayed processed file — every
        //                            apply compounds on the last result; sliders
        //                            are deltas. Falls back to srcWall if there
        //                            is no prior processed image yet.
        const prevProcessed = /processed-[ab]\.png$/.test(currentWall || "")
                                ? currentWall : ""
        const baseImage = (stackable && prevProcessed !== "") ? prevProcessed : srcWall

        // With a palette remap the adjustments run on the remapped file, so the
        // sliders stay visible on top of the palette.
        const adjustSrc = (remapPalette !== "") ? tmp : baseImage

        // tinct image adjust: ImageMagick's maths, output path last so the
        // pipeline can swap it.
        const useLut = !curveIsIdentity()
        let args = [home + "/.local/bin/tinct", "image", "adjust",
            "--brightness", String(brightness), "--saturation", String(saturation), "--hue", String(hue),
            "--contrast", String(contrast)]
        if (temp !== 0 && tBoost > 0) args = args.concat(["--temperature", String(temp > 0 ? tBoost : -tBoost)])
        if (parseFloat(sharpness) > 0) args = args.concat(["--sharpen", sharpness])
        if (parseFloat(blur)      > 0) args = args.concat(["--blur", blur])
        if (grain > 0)                 args = args.concat(["--grain", (grain / 100).toFixed(2)])
        if (useLut) args = args.concat(["--curve", curvePoints.map(p => p[0] + "," + p[1]).join(";")])
        args.push(adjustSrc)

        args.push(tmp)

        // Delegate the entire colour-generation chain to switchwall.sh —
        // it already does matugen + generate_colors_material.py + applycolor.sh
        // + the IPC reload, exactly the same way the wallpaper picker does.
        // Pass --noswitch so it only regenerates the palette and themes apps;
        // the actual wallpaper file the bg system uses is whatever currently
        // points to. WallTune saves to /tmp/walltune-processed.png and the
        // wallpaper script will use that for matugen.
        const switchwall = `${Directories.wallpaperSwitchScriptPath}`
        const theoryArg    = selectedTheory    !== "" ? "--theory "    + selectedTheory    : ""
        const styleArg     = selectedStyle     !== "" ? "--style "     + selectedStyle     : ""
        const practicalArg = selectedPractical !== "" ? "--practical " + selectedPractical : ""
        const remapArg     = (remapPalette !== "" && remapPalette !== "matugen") ? "--remap " + remapPalette : ""
        // Pass the dragged chip order through; omit the flag entirely when empty
        // so switchwall doesn't swallow the following token as its value.
        const moCsv        = root.mixOrderArg()
        const mixOrderArg  = moCsv !== "" ? "--mix-order " + moCsv : ""

        // Palette remap — runs FIRST, quantising the SOURCE wallpaper onto the
        // chosen palette into `tmp`. The adjustments above then read
        // `tmp` (via adjustSrc), so the sliders/curve sit on top of the
        // palette. matugen still extracts the theme from the final adjusted
        // image, so the popular-palette look and the adjustments both apply.
        let preRemapStep = ":"
        if (remapPalette !== "") {
            const rdmc = home + "/.scripts/rdmcpape"
            const palArg = remapPalette === "matugen"
                ? "--matugen"
                : "--palette " + remapPalette
            // Remap also honours stackable: chain on the prior processed image
            // when the toggle is on, otherwise start fresh from srcWall.
            preRemapStep = `'${rdmc}' ${palArg} --colors ${remapColors} --dither ${remapDither} --output '${tmp}' '${baseImage}'`
        }

        // Snapshot the current WallTune state — embedded into history entry so
        // clicking a history chip can fully restore the look.
        const snap = {
            slVibrance, slContrast, slTemperature, slBrightness, slSaturation,
            slHueShift, slHighlight, slShadow, slGrain, slSharpness,
            selectedMode, selectedTheory, selectedStyle, selectedPractical,
            mixOrder,
            curvePoints, remapPalette, remapColors, remapDither, darkMode, applyMode,
            stackable
        }
        const snapJson = JSON.stringify(snap).replace(/'/g, "'\\''")

        // Dedupe globally: any existing entry whose (wallpaper, state) matches
        // the new one is stripped from the file before append. Effect: one
        // canonical entry per distinct look, and re-applying an old look
        // promotes it back to "newest" instead of cluttering. The previous
        // "compare to tail only" version still leaked dupes whenever a
        // different look came in between two identical ones.
        const histStep = [
            `hist="$HOME/.local/state/quickshell/walltune-history.jsonl"`,
            `mkdir -p "$(dirname "$hist")"`,
            `cj="$HOME/.local/state/quickshell/user/generated/colors.json"`,
            `if [ -f "$cj" ]; then`,
            `  new_key=$(jq -cn --arg w '${srcWall}' --argjson st '${snapJson}' '{w:$w, st:$st}')`,
            `  if [ -f "$hist" ]; then`,
            // Strip every prior entry that matches new_key, in place. `tostring`
            // canonicalises the JSON so deep object compare is just string ==.
            `    tmp_h=$(mktemp)`,
            `    jq -c --argjson nk "$new_key" 'select(({w:.wallpaper, st:.state}|tostring) != ($nk|tostring))' "$hist" > "$tmp_h" 2>/dev/null && mv "$tmp_h" "$hist" || rm -f "$tmp_h"`,
            `  fi`,
            `  pri=$(jq -r '.primary // ""' "$cj")`,
            `  sec=$(jq -r '.secondary // ""' "$cj")`,
            `  ter=$(jq -r '.tertiary // ""' "$cj")`,
            `  ts=$(date +%s)`,
            `  thumb_dir="${cacheDir}/thumbs"`,
            `  mkdir -p "$thumb_dir"`,
            `  thumb_path="$thumb_dir/$ts.png"`,
            `  "$HOME/.local/bin/tinct" image thumb --size 160 --jobs 1 '${tmp}' "$thumb_path"`,
            `  jq -cn --arg p "$pri" --arg s "$sec" --arg t "$ter" --arg w '${srcWall}' \\`,
            `        --arg th "$thumb_path" --argjson st '${snapJson}' --argjson ts "$ts" \\`,
            `        '{ts:$ts, primary:$p, secondary:$s, tertiary:$t, wallpaper:$w, thumbnail:$th, state:$st}' >> "$hist"`,
            `  if [ $(wc -l < "$hist") -gt 40 ]; then`,
            `    tmp_h=$(mktemp) && tail -n 40 "$hist" > "$tmp_h" && mv "$tmp_h" "$hist"`,
            `  fi`,
            `fi`
        ].join("\n")

        // Apply-mode branching:
        //   "both"      = wallpaper edited  + theme from edited
        //   "colors"    = wallpaper RESET   + theme from edited
        //                 (the WallTune adjustments only colour the theme;
        //                  displayed wallpaper reverts to source)
        //   "wallpaper" = wallpaper edited  + theme RESET (from source image)
        //                 (the displayed wallpaper carries the adjustments;
        //                  theme matches the original colours)
        const cfg = home + "/.config/illogical-impulse/config.json"
        // Each entry is [phaseName, shellCmd]. Phase names map to phaseLabel
        // in the panel — they don't have to be unique across modes, only
        // monotonic, so the progress strip advances naturally.
        let pipelineSteps = []
        if (applyMode === "colors") {
            // Magick to a temp file → matugen on it (theme from adjusted) →
            // force wallpaperPath back to the source wallpaper.
            const colorsTmp = cacheDir + "/colors-source.png"
            const adjustArgsColors = args.slice()
            adjustArgsColors[adjustArgsColors.length - 1] = colorsTmp
            pipelineSteps = [
                ["remap",   preRemapStep],
                ["tune",    adjustArgsColors.map(a => `'${a.replace(/'/g, "'\\''")}'`).join(" ")],
                ["extract", `timeout 150 '${switchwall}' --image '${colorsTmp}' --mode ${mode} --no-wallpaper-update ${schemeArg} ${theoryArg} ${styleArg} ${practicalArg} ${remapArg} ${mixOrderArg}`],
                // Snap wallpaperPath back to the source so the bg layer shows
                // the un-edited wallpaper.
                ["apply",   `jq --arg p '${srcWall}' --arg src '${srcWall}' '.background.wallpaperPath = $p | .background.wallpaperSourcePath = $src' '${cfg}' > '${cfg}.tmp' && mv '${cfg}.tmp' '${cfg}'`],
            ]
        } else if (applyMode === "wallpaper") {
            // Remap source → tinct adjustments on top → set wallpaper path to
            // the result → re-extract theme from the ORIGINAL source so the
            // theme stays "normal".
            pipelineSteps = [
                ["remap",   preRemapStep],
                ["tune",    args.map(a => `'${a.replace(/'/g, "'\\''")}'`).join(" ")],
                ["apply",   `jq --arg p '${tmp}' --arg src '${srcWall}' '.background.wallpaperPath = $p | .background.wallpaperSourcePath = $src' '${cfg}' > '${cfg}.tmp' && mv '${cfg}.tmp' '${cfg}'`],
                // Theme reset: matugen on the source wallpaper, no path change.
                ["extract", `timeout 150 '${switchwall}' --image '${srcWall}' --mode ${mode} --no-wallpaper-update ${schemeArg}`],
            ]
        } else { // "both"
            // Remap source → tinct adjustments on top → SET WALLPAPER → theme
            // from the final image. The wallpaper switch runs BEFORE theme
            // extraction on purpose: extract is the slowest, most failure-prone
            // step (external helpers, dbus) and when it ran first, any hang or
            // failure there meant the freshly tuned image never reached the
            // screen at all. This order also flips the wallpaper instantly —
            // colors follow a moment later.
            pipelineSteps = [
                ["remap",   preRemapStep],
                ["tune",    args.map(a => `'${a.replace(/'/g, "'\\''")}'`).join(" ")],
                ["apply",   `jq --arg p '${tmp}' --arg src '${srcWall}' '.background.wallpaperPath = $p | .background.wallpaperSourcePath = $src' '${cfg}' > '${cfg}.tmp' && mv '${cfg}.tmp' '${cfg}'`],
                ["extract", `timeout 150 '${switchwall}' --image '${tmp}' --mode ${mode} --no-wallpaper-update ${schemeArg} ${theoryArg} ${styleArg} ${practicalArg} ${remapArg} ${mixOrderArg}`],
            ]
        }

        // Interleave each pipeline step with `echo WT_PHASE:<name>` so the
        // SplitParser in reprocessProc can track real-time progress instead of
        // a single binary "running / done" flag.
        // NOTE: Qt's QJSEngine doesn't implement Array.prototype.flatMap (ES2019),
        // so use a manual loop. Using flatMap throws TypeError mid-reprocess() —
        // processing stays true, subprocess never starts, UI sticks on "Working".
        const phasedShell = []
        for (let i = 0; i < pipelineSteps.length; i++) {
            const phase = pipelineSteps[i][0]
            const step  = pipelineSteps[i][1]
            phasedShell.push(`echo "WT_PHASE:${phase}"`)
            phasedShell.push(step)
        }

        const script = [
            "set -e",
            // Any step failing (or timing out) prints the error marker so the
            // panel shows "Failed" instead of silently freezing/no-opping.
            `trap 'echo "WT_PHASE:error"' ERR`,
            `mkdir -p '${cacheDir}'`,
            // Guard: a missing/garbage source wallpaper (e.g. config.wallpaperPath
            // clobbered to "--help") makes the adjust step fail and, under set -e, aborts the
            // whole pipeline BEFORE switchwall — so colours silently never apply.
            // Fail loudly with an error phase instead of a confusing no-op.
            `[ -f '${srcWall}' ] || { echo "WT_PHASE:error"; echo "walltune: source wallpaper not found: '${srcWall}'" >&2; exit 1; }`,
            `echo "WT_PHASE:start"`,
            ...phasedShell,
            `echo "WT_PHASE:history"`,
            histStep,
            `echo "WT_PHASE:done"`
            // NOTE: do NOT delete ${tmp} — config.background.wallpaperPath
            // points at it, and the file must survive reboots and qs reloads.
        ].join("\n")

        // stdbuf -oL forces bash's stdout to line-buffered mode. Without it,
        // libc block-buffers pipe stdout (4 KB) and the `echo WT_PHASE:…`
        // markers don't flush until the whole script ends — which makes the
        // progress strip look frozen and the label stick on whatever phase
        // the SplitParser last saw (or the default).
        reprocessProc.command = ["stdbuf", "-oL", "bash", "-c", script]
        reprocessProc.running = true
    }

    function saveState() {
        const s = JSON.stringify({
            slVibrance: slVibrance, slContrast: slContrast,
            slTemperature: slTemperature, slBrightness: slBrightness,
            slSaturation: slSaturation, slHueShift: slHueShift,
            slHighlight: slHighlight, slShadow: slShadow,
            slGrain: slGrain, slSharpness: slSharpness,
            selectedMode: selectedMode,
            selectedTheory: selectedTheory,
            selectedStyle: selectedStyle,
            selectedPractical: selectedPractical,
            mixOrder: mixOrder,
            curvePoints: curvePoints,
            remapPalette: remapPalette,
            remapColors:  remapColors,
            remapDither:  remapDither,
            darkMode: darkMode,
            applyMode: applyMode,
            stackable: stackable,
            sourceWall: sourceWall,
            lastProcessedSlot: lastProcessedSlot
        })
        saveProc.command = ["bash", "-c",
            `mkdir -p "$(dirname '${stateFile}')" && printf '%s' ${JSON.stringify(s)} > '${stateFile}'`]
        saveProc.running = true
    }

    function resetSliders() {
        slVibrance = 50; slContrast = 50; slTemperature = 50
        slBrightness = 50; slSaturation = 50; slHueShift = 50
        slHighlight = 50; slShadow = 50; slGrain = 0; slSharpness = 50
        selectedMode = ""
        selectedTheory = ""
        selectedStyle = ""
        selectedPractical = ""
        resetCurve()
        remapPalette = ""
        remapColors  = 32
        remapDither  = "FloydSteinberg2x2"
    }

    function randomWall() { Wallpapers.randomFromCurrentFolder() }

    function applyBlueprint(path) {
        saveProc.command = ["bash", "-c", `aether --apply-blueprint '${path}' 2>/dev/null`]
        saveProc.running = true
    }

    Component.onCompleted: {
        darkMode = Appearance.m3colors.darkmode
        loadProc.command = ["bash", "-c", `cat '${stateFile}' 2>/dev/null || echo '{}'`]
        loadProc.running = true
        blueScanProc.command = ["bash", "-c", `find '${blueprintsDir}' -name '*.json' 2>/dev/null | sort`]
        blueScanProc.running = true
        refreshHistogram()
        refreshWalltuneHistory()
    }

    // Bottom action bar height (32 button + 12 top padding inside the bar)
    readonly property int bottomBarHeight: 44
    implicitHeight: Math.min(col.implicitHeight + headerBar.implicitHeight + 10 + 24 + root.bottomBarHeight, root.maxContentHeight)
    Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
    color: Appearance.colors.colLayer0
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    opacity: GlobalStates.wallTuneOpen ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

    // Sticky Header
    RowLayout {
        id: headerBar
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: 12
            bottomMargin: 0
        }
        height: 24

        MaterialSymbol { text: "tune"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colPrimary; opacity: 0.8 }
        StyledText { text: qsTr("Palette"); font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Medium; color: Appearance.colors.colOnLayer0; Layout.fillWidth: true }
        // Phase text shown in the header while processing — discreet, but
        // visible enough that you know *which* stage you're in without
        // scrolling down to the button.
        StyledText {
            // Also shown (in error red) after a failed run, until the
            // error-hold timer clears the phase — otherwise a failure is
            // indistinguishable from success.
            visible: (root.processing || root.currentPhase === "error") && root.phaseLabel !== ""
            text: root.phaseLabel
            font.pixelSize: Appearance.font.pixelSize.smaller - 2
            color: root.currentPhase === "error" ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
            opacity: (root.processing || root.currentPhase === "error") ? 0.85 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }
        Rectangle {
            implicitWidth: 24; implicitHeight: 24; radius: 12
            color: xHov.hovered ? Appearance.colors.colLayer2 : "transparent"
            HoverHandler { margin: Appearance.sizes.touchSlop; id: xHov }
            TapHandler { margin: Appearance.sizes.touchSlop; onTapped: GlobalStates.wallTuneOpen = false }
            MaterialSymbol { anchors.centerIn: parent; text: "close"; iconSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.4 }
        }
    }

    // Thin progress strip just below the header. Drives the visible "yes,
    // something is happening, here's how far along" feedback — width follows
    // root.progress (phase index / total). A shimmer sweeps the filled
    // portion so the bar never *looks* frozen during the long adjust step.
    Rectangle {
        id: progressStrip
        anchors {
            top: headerBar.bottom
            left: parent.left
            right: parent.right
            topMargin: 6
            leftMargin: 12
            rightMargin: 12
        }
        height: 3
        radius: 1.5
        color: Qt.alpha(Appearance.colors.colPrimary, 0.18)
        opacity: root.processing || root.currentPhase === "done" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Rectangle {
            id: progressFill
            height: parent.height
            radius: parent.radius
            // Floor at ~6% so the first phase already shows movement.
            width: parent.width * Math.max(0.06, root.progress)
            color: Appearance.colors.colPrimary
            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            clip: true

            // Soft shimmer that slides left → right across the filled portion.
            // Only runs while processing so it doesn't burn idle frames.
            Rectangle {
                id: shimmer
                height: parent.height
                width: 36
                radius: parent.radius
                color: "white"
                opacity: 0.32
                visible: root.processing && progressFill.width > 8
                x: -width
                SequentialAnimation on x {
                    running: shimmer.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: -36; to: progressFill.width; duration: 1100; easing.type: Easing.InOutCubic }
                    NumberAnimation { to: -36; duration: 0 }
                }
            }
        }
    }

    Flickable {
        id: scroll
        anchors {
            top: headerBar.bottom
            left: parent.left
            right: parent.right
            bottom: bottomBar.top
            margins: 12
            topMargin: 10
            bottomMargin: 0
        }
        contentWidth: width
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {
            policy: scroll.contentHeight > scroll.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            width: 4
            contentItem: Rectangle { radius: 2; color: Appearance.colors.colOutline; opacity: 0.4 }
        }

    ColumnLayout {
        id: col
        width: scroll.width
        // 10, not 13. Every section, card and pill row in the panel sits in
        // this column, so this one number sets the panel's overall density.
        spacing: 10

        // Wallpaper preview
        Rectangle {
            id: wallPreview
            Layout.fillWidth: true; implicitHeight: 80
            radius: 16
            color: Appearance.colors.colLayer1
            clip: true
            visible: root.currentWall !== ""

            Image {
                id: wallPreviewImg
                anchors.fill: parent
                source: root.currentWall !== "" ? "file://" + root.currentWall : ""
                fillMode: Image.PreserveAspectCrop; smooth: true; asynchronous: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: wallPreviewImg.width; height: wallPreviewImg.height
                        radius: wallPreview.radius
                    }
                }
            }
            // Animated wallpapers don't decode in a QML Image — show a
            // play-glyph placeholder instead of an empty box.
            Rectangle {
                anchors.fill: parent
                visible: root.sourceIsVideo
                radius: wallPreview.radius
                color: Appearance.colors.colLayer2
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "movie"
                    iconSize: 34
                    fill: 1
                    color: Appearance.colors.colSubtext
                }
            }
            BottomFadeOverlay {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                barHeight: 26
                text: FileUtils.fileNameForPath(root.currentWall)
            }
            // Tiny "edit crop" button — top-left, profile-picture-editor style.
            Rectangle {
                anchors { top: parent.top; left: parent.left; margins: 6 }
                width: 22; height: 22; radius: 11
                color: cropHov.hovered ? Appearance.colors.colPrimary : Qt.alpha("black", 0.55)
                border.width: 1; border.color: Qt.alpha("white", 0.25)
                Behavior on color { ColorAnimation { duration: 140 } }
                HoverHandler { margin: Appearance.sizes.touchSlop; id: cropHov }
                TapHandler { margin: Appearance.sizes.touchSlop; onTapped: GlobalStates.requestAdjusterOpen(0) }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "crop"
                    iconSize: 13
                    color: cropHov.hovered ? Appearance.m3colors.m3onPrimary : "white"
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
                StyledToolTip { text: qsTr("Adjust crop") }
            }
            Row {
                anchors { top: parent.top; right: parent.right; margins: 6 }
                spacing: 4
                Repeater {
                    model: [ Appearance.m3colors.m3primary, Appearance.m3colors.m3secondary, Appearance.m3colors.m3tertiary, Appearance.m3colors.m3primaryContainer, Appearance.m3colors.m3secondaryContainer ]
                    delegate: Rectangle {
                        required property var modelData
                        width: 14; height: 14; radius: 7; color: modelData
                        border.width: 1; border.color: Qt.alpha("white", 0.25)
                        Behavior on color { ColorAnimation { duration: 400 } }
                    }
                }
            }
        }

        // ── Active mix summary ─────────────────────────────────────────────
        // Surfaces every currently-stacked section choice (Mode / Theory /
        // Style / Practical / Remap / Curve) as a chip row. Click the chip
        // to open its section dropdown; click the × to clear that one entry.
        // Hidden entirely when nothing is active so the panel stays compact
        // at rest.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: root.activeMix.length > 0
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }

            RowLayout {
                Layout.fillWidth: true; spacing: 4
                MaterialSymbol {
                    text: "layers"
                    iconSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer0; opacity: 0.45
                }
                StyledText {
                    text: qsTr("Active mix")
                    font.pixelSize: Appearance.font.pixelSize.smaller - 1
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0; opacity: 0.5
                    Layout.fillWidth: true
                }
                Rectangle {
                    implicitWidth: clrAllRow.implicitWidth + 12
                    implicitHeight: 20
                    radius: 10
                    color: clrAllHov.hovered ? Appearance.colors.colLayer2 : "transparent"
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colOnLayer0, 0.18)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    HoverHandler { id: clrAllHov }
                    TapHandler { onTapped: {
                        root.selectedMode = ""
                        root.selectedTheory = ""
                        root.selectedStyle = ""
                        root.selectedPractical = ""
                        root.remapPalette = ""
                        root.resetCurve()
                    } }
                    Row { id: clrAllRow; anchors.centerIn: parent; spacing: 3
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "clear_all"; iconSize: 12
                            color: Appearance.colors.colOnLayer0; opacity: 0.55
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Clear")
                            font.pixelSize: Appearance.font.pixelSize.smaller - 3
                            color: Appearance.colors.colOnLayer0; opacity: 0.6
                        }
                    }
                }
            }

            // A numbered column, not a chip cloud. These stages RUN IN THIS
            // ORDER — mixOrder goes to switchwall.sh as --mix-order and the
            // palette genuinely differs by it — and a row of tags says nothing
            // about that. Drag a row to reorder; the number is the stage.
            ColumnLayout {
                id: mixStack
                Layout.fillWidth: true
                spacing: 3

                Repeater {
                    model: root.activeMix
                    delegate: Rectangle {
                        id: stage
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: Appearance.rounding.verysmall
                        color: stageMa.containsMouse || stageDrag.active
                            ? Qt.alpha(modelData.color, 0.22)
                            : Qt.alpha(modelData.color, 0.10)
                        border.width: 1
                        border.color: Qt.alpha(modelData.color, stageDrag.active ? 0.9 : 0.35)
                        Behavior on color { ColorAnimation { duration: 100 } }

                        // Moved by transform, not y: the layout keeps owning
                        // position, so the drag cannot fight it.
                        z: stageDrag.active ? 50 : 0
                        scale: stageDrag.active ? 1.02 : 1
                        Behavior on scale { NumberAnimation { duration: 90 } }
                        transform: Translate { y: stageDrag.active ? stageDrag.activeTranslation.y : 0 }

                        DragHandler {
                            id: stageDrag
                            target: null
                            yAxis.enabled: true
                            xAxis.enabled: false
                            property string dropKey: ""
                            onActiveTranslationChanged: {
                                if (!active) return;
                                const cy = stage.y + activeTranslation.y + stage.height / 2;
                                let best = null, bestD = Infinity;
                                for (const c of mixStack.children) {
                                    if (c === stage || !c.modelData) continue;
                                    const d = Math.abs((c.y + c.height / 2) - cy);
                                    if (d < bestD) { bestD = d; best = c; }
                                }
                                dropKey = best ? best.modelData.key : "";
                            }
                            onActiveChanged: {
                                if (active) { dropKey = ""; return; }
                                if (dropKey) root.moveMixBefore(stage.modelData.key, dropKey);
                                dropKey = "";
                            }
                        }

                        MouseArea {
                            id: stageMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: stageDrag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                            onClicked: if (!stageDrag.active) root.openMixSection(stage.modelData.key)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 4
                            spacing: 8

                            StyledText {
                                text: stage.index + 1
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.family: Appearance.font.family.numbers
                                color: Appearance.colors.colOnLayer0
                                opacity: 0.4
                            }
                            Rectangle {
                                implicitWidth: 8; implicitHeight: 8; radius: 4
                                color: stage.modelData.color
                            }
                            StyledText {
                                text: stage.modelData.section
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer0
                                opacity: 0.55
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: stage.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer0
                                elide: Text.ElideRight
                            }
                            MaterialSymbol {
                                text: "drag_indicator"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer0
                                opacity: stageMa.containsMouse ? 0.45 : 0.2
                            }
                            RippleButton {
                                implicitWidth: 22; implicitHeight: 22
                                buttonRadius: Appearance.rounding.full
                                onClicked: root.clearMix(stage.modelData.key)
                                contentItem: MaterialSymbol {
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: "close"
                                    iconSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer0
                                }
                            }
                        }
                    }
                }
            }
        }

        // Animated-wallpaper notice — the tuning pipeline can't
        // touch a video, so the controls below are inert for one.
        Rectangle {
            Layout.fillWidth: true
            visible: root.sourceIsVideo
            implicitHeight: noticeRow.implicitHeight + 16
            radius: 12
            color: Qt.alpha(Appearance.m3colors.m3tertiary, 0.14)
            RowLayout {
                id: noticeRow
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                spacing: 8
                MaterialSymbol {
                    text: "auto_awesome_motion"
                    iconSize: 20
                    color: Appearance.m3colors.m3tertiary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Animated wallpaper — colour tuning is unavailable. The theme is generated from a frame of the video.")
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        ColumnLayout { Layout.fillWidth: true; spacing: 5
            opacity: root.sourceIsVideo ? 0.4 : 1.0
        GroupHeading { text: qsTr("Wallpaper") }
            SectionLabel { text: qsTr("Transition") }
            SegmentedButtons {
                Layout.fillWidth: true
                showCheck: false
                currentId: GlobalStates.wallTransition
                onSelected: id => GlobalStates.wallTransition = id
                model: root.transitions.map(t => ({ id: t.id, label: t.label, icon: t.icon }))
            }
        }

        SectionLabel { text: qsTr("Apply to") }
        SegmentedButtons {
            Layout.fillWidth: true
            showCheck: false
            currentId: root.applyMode
            onSelected: id => root.applyMode = id
            model: root.applyModes.map(m => ({ id: m.id, label: m.label, icon: m.icon }))
        }

        // ── Parallax zoom on workspace scroll ──────────────────────────
        // Background.qml multiplies its render scale by this every time
        // you switch workspaces. 1.00 = no zoom, 1.07 = default subtle,
        // 1.30 = punchy. Off = disable entirely.
        // Parallax is two settings that are set once and left alone, so it
        // does not earn a permanent card in the main column.
        PanelActionButton {
            Layout.fillWidth: true
            iconName: "swap_horiz"
            buttonLabel: qsTr("Workspace parallax")
            onClicked: root.parallaxOpen = true
        }

        // ── Wallpaper effect ────────────────────────────────────────────
        // A pack effect drawn on the wallpaper layer. Deliberately NOT
        // decoration:screen_shader: this runs on a surface we already render,
        // so it costs no damage-tracking, does not fight the colour-grading
        // sliders, and warps sample the wallpaper directly with no capture.
        // Effects using theme roles (@primary) recolour with the palette this
        // panel generates, which is the point of putting it here.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: wallFxCol.implicitHeight + 24
            // Matches the parallax card above: same radius, same border.
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            ColumnLayout {
                id: wallFxCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7
                    MaterialSymbol {
                        text: "animation"; iconSize: 17
                        color: (Config.options.background.effect ?? "").length > 0
                            ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Wallpaper Effect"
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.bold: true
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: (Config.options.background.effect ?? "").length > 0
                            ? AppDisplay.effectName(Config.options.background.effect) : "off"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: (Config.options.background.effect ?? "").length > 0
                            ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }
                }

                // Effect picker — a dropdown rather than a wall of chips,
                // and the SELECTED effect's variables shown below it. This is
                // the display-settings shader-list treatment, on the wallpaper
                // layer: pick one, then tune what it exposes.
                //
                // Full width on its own row, at StyledComboBox's own 40px
                // height. Squeezing it onto the title row shrank it in both
                // directions and it no longer read as the card's main control.
                StyledComboBox {
                    Layout.fillWidth: true
                    // colLayer2, not secondaryContainer: filled with the accent
                    // it was the loudest element here, for a control that is
                    // off most of the time.
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    readonly property var opts: [{ name: "Off", path: "" }]
                        .concat(AppDisplay.effects.map(e => ({ name: e.name, path: e.path })))
                    model: opts
                    textRole: "name"
                    currentIndex: Math.max(0, opts.findIndex(
                        o => o.path === (Config.options.background.effect ?? "")))
                    onActivated: idx => Config.options.background.effect = opts[idx].path
                }

                // The effect's variables live in their own popup (opened
                // beside this panel) rather than inline — a stack of sliders
                // and swatch rows made WallTune enormous. Button only shows
                // when the selected effect actually exposes variables.
                // The shared panel-action element (same as DisplaySettings' shader "Browse…").
                PanelActionButton {
                    Layout.fillWidth: true
                    visible: WallEffect.hasVariables
                    iconName: "tune"
                    buttonLabel: "Variables…"
                    onClicked: GlobalStates.wallEffectVarsOpen = !GlobalStates.wallEffectVarsOpen
                }
            }
        }

        // ── Stack toggle ────────────────────────────────────────────────
        // OFF (default): every apply starts from the un-edited original — the
        //                sliders are absolute settings.
        // ON          : every apply chains on top of the previously-processed
        //                image — sliders become deltas. Each click on Reprocess
        //                visibly compounds the look (great for grain/wash
        //                drift, lousy for fine control).
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 28
            radius: 14
            color: root.stackable
                ? Appearance.colors.colPrimary
                : (stHovOuter.hovered ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1)
            Behavior on color { ColorAnimation { duration: 140 } }

            HoverHandler { id: stHovOuter }
            TapHandler { onTapped: root.stackable = !root.stackable }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 6
                spacing: 8

                MaterialSymbol {
                    text: root.stackable ? "layers" : "layers_clear"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.stackable ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                    opacity: root.stackable ? 1 : (stHovOuter.hovered ? 0.85 : 0.6)
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: -2
                    StyledText {
                        text: qsTr("Stack on previous")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: root.stackable ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                    StyledText {
                        text: root.stackable ? qsTr("Each apply compounds") : qsTr("Each apply starts from original")
                        font.pixelSize: Appearance.font.pixelSize.smaller - 3
                        color: root.stackable ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                        opacity: root.stackable ? 0.85 : 0.5
                        elide: Text.ElideRight
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                }

                // Mini iOS-style switch.
                Rectangle {
                    implicitWidth: 28; implicitHeight: 16; radius: 8
                    color: root.stackable
                        ? Qt.alpha(Appearance.m3colors.m3onPrimary, 0.35)
                        : Qt.alpha(Appearance.colors.colOnLayer0, 0.20)
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Rectangle {
                        width: 12; height: 12; radius: 6
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.stackable ? parent.width - width - 2 : 2
                        color: root.stackable ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                }
            }
        }

        GroupHeading { text: qsTr("Colour") }
        SectionLabel { text: qsTr("Theme mode") }
        SegmentedButtons {
            Layout.fillWidth: true
            showCheck: false
            currentId: root.darkMode ? "dark" : "light"
            onSelected: id => root.darkMode = (id === "dark")
            model: [
                { id: "dark",  label: qsTr("Dark"),  icon: "dark_mode" },
                { id: "light", label: qsTr("Light"), icon: "light_mode" }
            ]
        }

        // Extraction mode
        SectionLabel { text: qsTr("Extraction mode") }
        Flow { Layout.fillWidth: true; spacing: 4
            Repeater {
                model: root.extractModes
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool active: root.selectedMode === modelData.id
                    implicitWidth: mRow.implicitWidth + 14; implicitHeight: 28; radius: 14
                    color: active ? modelData.color : (mHov.hovered ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    HoverHandler { id: mHov }
                    TapHandler { onTapped: root.selectedMode = modelData.id }
                    Row { id: mRow; anchors.centerIn: parent; spacing: 5
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; visible: !active; width: 6; height: 6; radius: 3; color: modelData.color; opacity: 0.9 }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter; text: modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller - 2
                            color: active ? "white" : Appearance.colors.colOnLayer0; opacity: active ? 1 : 0.7
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                    }
                }
            }
        }

        // Divider — separates the live editing controls above from the
        // saved-history section below, giving the panel a clear two-zone
        // hierarchy instead of one long undifferentiated scroll.
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 2
            Layout.bottomMargin: 2
            implicitHeight: 1
            color: Appearance.colors.colOutline
            opacity: 0.15
            visible: root.history.length > 0
        }


        // ── Per-app colours ──────────────────────────────────────────────
        // Everything below shapes the one palette every app receives. This
        // opens the panel that shifts it per app afterwards — a terminal that
        // wants more contrast than the bar, or a role pinned by hand.
        PanelActionButton {
            Layout.fillWidth: true
            iconName: "palette"
            buttonLabel: qsTr("Per-app colours…")
            // Matches the section headers below it (PanelActionButton is 32
            // by default), so this block reads as one list of rows.
            implicitHeight: 40
            onClicked: GlobalStates.appColorsOpen = !GlobalStates.appColorsOpen
        }

        // ── Color Theory dropdown ────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            // 40, not 26. These are the panel's main navigation rows and they
            // read as thin dividers at 26 next to the 40px buttons around them.
            height: 40; radius: 20
            // Square the bottom corners while open so the header and the body
            // below read as ONE container rather than two stacked pills.
            bottomLeftRadius:  root.theoryOpen ? 0 : 20
            bottomRightRadius: root.theoryOpen ? 0 : 20
            color: (thHeadHov.hovered || thBodyHov.hovered) ? Appearance.colors.colLayer2 : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } }
            HoverHandler { id: thHeadHov }
            TapHandler { onTapped: root.theoryOpen = !root.theoryOpen }
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 6; spacing: 6
                StyledText {
                    text: qsTr("Color Theory")
                    font.pixelSize: Appearance.font.pixelSize.smaller - 1
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0; opacity: 0.5
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.selectedTheory !== ""
                    text: {
                        const m = root.theoryModes.find(x => x.id === root.selectedTheory)
                        return m ? "· " + m.label : ""
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller - 2
                    color: Appearance.colors.colPrimary; opacity: 0.85
                    elide: Text.ElideRight
                }
                Item { Layout.fillWidth: true; visible: root.selectedTheory === "" }
                MaterialSymbol {
                    text: "expand_more"; iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0; opacity: 0.5
                    rotation: root.theoryOpen ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
            }
        }
        Item {
            Layout.fillWidth: true
            clip: true
            Layout.preferredHeight: root.theoryOpen ? thFlow.implicitHeight : 0
            // A ColumnLayout puts its spacing on BOTH sides of a zero-height
            // item, so every closed section still cost 13px above + 13px
            // below for a 26px header -- half the collapsed area was gap,
            // six times over. An invisible item is skipped entirely,
            // spacing included. The epsilon keeps it visible for the whole
            // collapse animation and drops it only once fully closed.
            visible: Layout.preferredHeight > 0.5
            // Pulled up by the column's own spacing so it TOUCHES the header;
            // otherwise the container highlight would be split by a 10px gap.
            Layout.topMargin: -col.spacing
            HoverHandler { id: thBodyHov }
            Rectangle {
                anchors.fill: parent
                z: -1
                color: (thHeadHov.hovered || thBodyHov.hovered) ? Appearance.colors.colLayer2 : "transparent"
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: 20
                bottomRightRadius: 20
                Behavior on color { ColorAnimation { duration: 100 } }
            }
            opacity: root.theoryOpen ? 1 : 0
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Flow { id: thFlow; width: parent.width; spacing: 4
                Repeater {
                    model: root.theoryModes
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: root.selectedTheory === modelData.id
                        implicitWidth: thRow.implicitWidth + 14; implicitHeight: 24; radius: 12
                        color: active ? modelData.color : (thHov.hovered ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        HoverHandler { id: thHov }
                        TapHandler { onTapped: root.selectedTheory = modelData.id }
                        Row { id: thRow; anchors.centerIn: parent; spacing: 5
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; visible: !active; width: 6; height: 6; radius: 3; color: modelData.color; opacity: 0.9 }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter; text: modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller - 2
                                color: active ? "white" : Appearance.colors.colOnLayer0; opacity: active ? 1 : 0.7
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }
                        }
                    }
                }
            }
        }

        // ── Style dropdown ────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            // 40, not 26. These are the panel's main navigation rows and they
            // read as thin dividers at 26 next to the 40px buttons around them.
            height: 40; radius: 20
            // Square the bottom corners while open so the header and the body
            // below read as ONE container rather than two stacked pills.
            bottomLeftRadius:  root.styleOpen ? 0 : 20
            bottomRightRadius: root.styleOpen ? 0 : 20
            color: (stHeadHov.hovered || stBodyHov.hovered) ? Appearance.colors.colLayer2 : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } }
            HoverHandler { id: stHeadHov }
            TapHandler { onTapped: root.styleOpen = !root.styleOpen }
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 6; spacing: 6
                StyledText {
                    text: qsTr("Style")
                    font.pixelSize: Appearance.font.pixelSize.smaller - 1
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0; opacity: 0.5
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.selectedStyle !== ""
                    text: {
                        const m = root.styleModes.find(x => x.id === root.selectedStyle)
                        return m ? "· " + m.label : ""
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller - 2
                    color: Appearance.colors.colPrimary; opacity: 0.85
                    elide: Text.ElideRight
                }
                Item { Layout.fillWidth: true; visible: root.selectedStyle === "" }
                MaterialSymbol {
                    text: "expand_more"; iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0; opacity: 0.5
                    rotation: root.styleOpen ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
            }
        }
        Item {
            Layout.fillWidth: true
            clip: true
            Layout.preferredHeight: root.styleOpen ? stFlow.implicitHeight : 0
            // Skipped by the layout when closed, spacing included (see above).
            visible: Layout.preferredHeight > 0.5
            // Pulled up by the column's own spacing so it TOUCHES the header;
            // otherwise the container highlight would be split by a 10px gap.
            Layout.topMargin: -col.spacing
            HoverHandler { id: stBodyHov }
            Rectangle {
                anchors.fill: parent
                z: -1
                color: (stHeadHov.hovered || stBodyHov.hovered) ? Appearance.colors.colLayer2 : "transparent"
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: 20
                bottomRightRadius: 20
                Behavior on color { ColorAnimation { duration: 100 } }
            }
            opacity: root.styleOpen ? 1 : 0
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Flow { id: stFlow; width: parent.width; spacing: 4
                Repeater {
                    model: root.styleModes
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: root.selectedStyle === modelData.id
                        implicitWidth: stRow.implicitWidth + 14; implicitHeight: 24; radius: 12
                        color: active ? modelData.color : (stHov.hovered ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        HoverHandler { id: stHov }
                        TapHandler { onTapped: root.selectedStyle = modelData.id }
                        Row { id: stRow; anchors.centerIn: parent; spacing: 5
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; visible: !active; width: 6; height: 6; radius: 3; color: modelData.color; opacity: 0.9 }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter; text: modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller - 2
                                color: active ? "white" : Appearance.colors.colOnLayer0; opacity: active ? 1 : 0.7
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }
                        }
                    }
                }
            }
        }

        // ── Practical dropdown ────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            // 40, not 26. These are the panel's main navigation rows and they
            // read as thin dividers at 26 next to the 40px buttons around them.
            height: 40; radius: 20
            // Square the bottom corners while open so the header and the body
            // below read as ONE container rather than two stacked pills.
            bottomLeftRadius:  root.practicalOpen ? 0 : 20
            bottomRightRadius: root.practicalOpen ? 0 : 20
            color: (prHeadHov.hovered || prBodyHov.hovered) ? Appearance.colors.colLayer2 : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } }
            HoverHandler { id: prHeadHov }
            TapHandler { onTapped: root.practicalOpen = !root.practicalOpen }
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 6; spacing: 6
                StyledText {
                    text: qsTr("Practical")
                    font.pixelSize: Appearance.font.pixelSize.smaller - 1
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0; opacity: 0.5
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.selectedPractical !== ""
                    text: {
                        const m = root.practicalModes.find(x => x.id === root.selectedPractical)
                        return m ? "· " + m.label : ""
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller - 2
                    color: Appearance.colors.colPrimary; opacity: 0.85
                    elide: Text.ElideRight
                }
                Item { Layout.fillWidth: true; visible: root.selectedPractical === "" }
                MaterialSymbol {
                    text: "expand_more"; iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0; opacity: 0.5
                    rotation: root.practicalOpen ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
            }
        }
        Item {
            Layout.fillWidth: true
            clip: true
            Layout.preferredHeight: root.practicalOpen ? prFlow.implicitHeight : 0
            // Skipped by the layout when closed, spacing included (see above).
            visible: Layout.preferredHeight > 0.5
            // Pulled up by the column's own spacing so it TOUCHES the header;
            // otherwise the container highlight would be split by a 10px gap.
            Layout.topMargin: -col.spacing
            HoverHandler { id: prBodyHov }
            Rectangle {
                anchors.fill: parent
                z: -1
                color: (prHeadHov.hovered || prBodyHov.hovered) ? Appearance.colors.colLayer2 : "transparent"
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: 20
                bottomRightRadius: 20
                Behavior on color { ColorAnimation { duration: 100 } }
            }
            opacity: root.practicalOpen ? 1 : 0
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Flow { id: prFlow; width: parent.width; spacing: 4
                Repeater {
                    model: root.practicalModes
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: root.selectedPractical === modelData.id
                        implicitWidth: prRow.implicitWidth + 14; implicitHeight: 24; radius: 12
                        color: active ? modelData.color : (prHov.hovered ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        HoverHandler { id: prHov }
                        TapHandler { onTapped: root.selectedPractical = modelData.id }
                        Row { id: prRow; anchors.centerIn: parent; spacing: 5
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; visible: !active; width: 6; height: 6; radius: 3; color: modelData.color; opacity: 0.9 }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter; text: modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller - 2
                                color: active ? "white" : Appearance.colors.colOnLayer0; opacity: active ? 1 : 0.7
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }
                        }
                    }
                }
            }
        }

        // ── Tone Curve dropdown ───────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            // 40, not 26. These are the panel's main navigation rows and they
            // read as thin dividers at 26 next to the 40px buttons around them.
            height: 40; radius: 20
            // Square the bottom corners while open so the header and the body
            // below read as ONE container rather than two stacked pills.
            bottomLeftRadius:  root.curveOpen ? 0 : 20
            bottomRightRadius: root.curveOpen ? 0 : 20
            color: (cvHeadHov.hovered || cvBodyHov.hovered) ? Appearance.colors.colLayer2 : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } }
            HoverHandler { id: cvHeadHov }
            TapHandler { onTapped: root.curveOpen = !root.curveOpen }
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 6; spacing: 6
                StyledText {
                    text: qsTr("Tone Curve")
                    font.pixelSize: Appearance.font.pixelSize.smaller - 1
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0; opacity: 0.5
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: !root.curveIsIdentity()
                    text: "· " + (root.curvePoints.length) + " pts"
                    font.pixelSize: Appearance.font.pixelSize.smaller - 2
                    color: Appearance.colors.colPrimary; opacity: 0.85
                    elide: Text.ElideRight
                }
                Item { Layout.fillWidth: true; visible: root.curveIsIdentity() }
                MaterialSymbol {
                    text: "expand_more"; iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0; opacity: 0.5
                    rotation: root.curveOpen ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
            }
        }
        Item {
            Layout.fillWidth: true
            clip: true
            Layout.preferredHeight: root.curveOpen ? curveBody.implicitHeight : 0
            // Skipped by the layout when closed, spacing included (see above).
            visible: Layout.preferredHeight > 0.5
            // Pulled up by the column's own spacing so it TOUCHES the header;
            // otherwise the container highlight would be split by a 10px gap.
            Layout.topMargin: -col.spacing
            HoverHandler { id: cvBodyHov }
            Rectangle {
                anchors.fill: parent
                z: -1
                color: (cvHeadHov.hovered || cvBodyHov.hovered) ? Appearance.colors.colLayer2 : "transparent"
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: 20
                bottomRightRadius: 20
                Behavior on color { ColorAnimation { duration: 100 } }
            }
            opacity: root.curveOpen ? 1 : 0
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 140 } }

            ColumnLayout {
                id: curveBody
                width: parent.width; spacing: 4

                // The interactive curve canvas
                Rectangle {
                    id: curveBox
                    Layout.fillWidth: true
                    implicitHeight: 160
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    clip: true

                    // ─── Histogram backdrop ──────────────────────────────
                    Canvas {
                        id: histCanvas
                        anchors.fill: parent
                        anchors.margins: 4
                        antialiasing: false
                        readonly property var data: root.histogram
                        onDataChanged: requestPaint()
                        onWidthChanged:  requestPaint()
                        onHeightChanged: requestPaint()
                        Component.onCompleted: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            if (!data || data.length !== 256) return
                            // Use log scale so peaks don't crush the whole graph
                            let maxV = 0
                            for (let i = 0; i < 256; i++) {
                                const v = Math.log(1 + data[i])
                                if (v > maxV) maxV = v
                            }
                            if (maxV <= 0) return
                            ctx.fillStyle = Qt.rgba(
                                Appearance.colors.colPrimary.r,
                                Appearance.colors.colPrimary.g,
                                Appearance.colors.colPrimary.b,
                                0.18)
                            const W = width, H = height
                            ctx.beginPath()
                            ctx.moveTo(0, H)
                            for (let i = 0; i < 256; i++) {
                                const x = (i / 255) * W
                                const v = Math.log(1 + data[i]) / maxV
                                const y = H - v * H
                                ctx.lineTo(x, y)
                            }
                            ctx.lineTo(W, H)
                            ctx.closePath()
                            ctx.fill()
                        }
                    }

                    // ─── Diagonal reference + grid ───────────────────────
                    Canvas {
                        id: gridCanvas
                        anchors.fill: parent
                        anchors.margins: 4
                        antialiasing: true
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        Component.onCompleted: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            const W = width, H = height
                            // Faint grid
                            ctx.strokeStyle = Qt.rgba(1,1,1,0.07)
                            ctx.lineWidth = 1
                            for (let i = 1; i < 4; i++) {
                                const x = (i / 4) * W
                                const y = (i / 4) * H
                                ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, H); ctx.stroke()
                                ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(W, y); ctx.stroke()
                            }
                            // Reference diagonal
                            ctx.strokeStyle = Qt.rgba(1,1,1,0.15)
                            ctx.beginPath()
                            ctx.moveTo(0, H); ctx.lineTo(W, 0)
                            ctx.stroke()
                        }
                    }

                    // ─── Curve line ──────────────────────────────────────
                    Canvas {
                        id: curveCanvas
                        anchors.fill: parent
                        anchors.margins: 4
                        antialiasing: true
                        readonly property var pts: root.curvePoints
                        onPtsChanged: requestPaint()
                        onWidthChanged:  requestPaint()
                        onHeightChanged: requestPaint()
                        Component.onCompleted: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            const W = width, H = height
                            const sorted = pts.slice().sort((a, b) => a[0] - b[0])
                            ctx.strokeStyle = Appearance.colors.colPrimary
                            ctx.lineWidth = 2
                            ctx.beginPath()
                            // Sample 128 points using linear interp between sorted control points
                            for (let i = 0; i <= 128; i++) {
                                const t = i / 128
                                let y = t
                                if (sorted.length >= 2) {
                                    if (t <= sorted[0][0]) y = sorted[0][1]
                                    else if (t >= sorted[sorted.length-1][0]) y = sorted[sorted.length-1][1]
                                    else for (let j = 0; j < sorted.length-1; j++) {
                                        const [x0,y0] = sorted[j], [x1,y1] = sorted[j+1]
                                        if (t >= x0 && t <= x1) {
                                            const u = x1 === x0 ? 0 : (t - x0) / (x1 - x0)
                                            y = y0 + u * (y1 - y0)
                                            break
                                        }
                                    }
                                }
                                const px = t * W
                                const py = H - y * H
                                if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py)
                            }
                            ctx.stroke()
                        }
                    }

                    // ─── Control point handles ───────────────────────────
                    Repeater {
                        model: root.curvePoints.length
                        delegate: Rectangle {
                            required property int index
                            readonly property var pt: root.curvePoints[index]
                            readonly property real innerW: curveBox.width  - 8
                            readonly property real innerH: curveBox.height - 8
                            x: 4 + pt[0] * innerW - width/2
                            y: 4 + (1 - pt[1]) * innerH - height/2
                            width: 11; height: 11; radius: 6
                            color: dragHov.hovered || dragArea.drag.active ? Appearance.colors.colPrimary : "white"
                            border.width: 2
                            border.color: Appearance.colors.colPrimary
                            z: 5

                            HoverHandler { margin: Appearance.sizes.touchSlop; id: dragHov }

                            MouseArea {
                                id: dragArea
                                anchors.fill: parent
                                anchors.margins: -6
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                drag.target: parent
                                drag.minimumX: 4 - parent.width/2
                                drag.maximumX: 4 + parent.innerW - parent.width/2
                                drag.minimumY: 4 - parent.height/2
                                drag.maximumY: 4 + parent.innerH - parent.height/2
                                onPositionChanged: {
                                    if (!drag.active) return
                                    // Convert pixel back to [0,1] and update state.
                                    // Clamp x: endpoints stay at 0/1, middle points stay between neighbours.
                                    const newX = (parent.x + parent.width/2 - 4) / parent.innerW
                                    const newY = 1 - (parent.y + parent.height/2 - 4) / parent.innerH
                                    const arr = root.curvePoints.slice()
                                    let cx = Math.max(0, Math.min(1, newX))
                                    let cy = Math.max(0, Math.min(1, newY))
                                    // Lock first/last x at 0/1 (only y editable on endpoints).
                                    const sorted = arr.slice().sort((a, b) => a[0] - b[0])
                                    const isFirst = sorted[0] === arr[index]
                                    const isLast  = sorted[sorted.length-1] === arr[index]
                                    if (isFirst) cx = 0
                                    if (isLast)  cx = 1
                                    arr[index] = [cx, cy]
                                    root.curvePoints = arr
                                }
                                onClicked: function(mouse) {
                                    if (mouse.button === Qt.RightButton) {
                                        // Don't allow removing if only 2 points left.
                                        if (root.curvePoints.length <= 2) return
                                        const arr = root.curvePoints.slice()
                                        arr.splice(index, 1)
                                        root.curvePoints = arr
                                    }
                                }
                            }
                        }
                    }

                    // ─── Background tap to add a new point ───────────────
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: 4
                        z: 1
                        acceptedButtons: Qt.LeftButton
                        onClicked: function(mouse) {
                            const x = mouse.x / width
                            const y = 1 - mouse.y / height
                            const arr = root.curvePoints.slice()
                            arr.push([Math.max(0.001, Math.min(0.999, x)),
                                      Math.max(0,     Math.min(1,     y))])
                            root.curvePoints = arr
                        }
                    }
                }

                // ─── Hint + Reset ───────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("click to add · drag to adjust · right-click to remove")
                        font.pixelSize: Appearance.font.pixelSize.smaller - 3
                        color: Appearance.colors.colOnLayer0; opacity: 0.4
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        implicitHeight: 22; implicitWidth: cvResetRow.implicitWidth + 12; radius: 11
                        color: cvResetHov.hovered ? Appearance.colors.colLayer2 : "transparent"
                        border.width: 1; border.color: Appearance.colors.colLayer0Border
                        Behavior on color { ColorAnimation { duration: 100 } }
                        HoverHandler { id: cvResetHov }
                        TapHandler { onTapped: root.resetCurve() }
                        Row { id: cvResetRow; anchors.centerIn: parent; spacing: 3
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "restart_alt"; iconSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer0; opacity: 0.6
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("Reset")
                                font.pixelSize: Appearance.font.pixelSize.smaller - 2
                                color: Appearance.colors.colOnLayer0; opacity: 0.7
                            }
                        }
                    }
                }
            }
        }

        // ── Palette Remap dropdown ────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            // 40, not 26. These are the panel's main navigation rows and they
            // read as thin dividers at 26 next to the 40px buttons around them.
            height: 40; radius: 20
            // Square the bottom corners while open so the header and the body
            // below read as ONE container rather than two stacked pills.
            bottomLeftRadius:  root.remapOpen ? 0 : 20
            bottomRightRadius: root.remapOpen ? 0 : 20
            color: (rmHeadHov.hovered || rmBodyHov.hovered) ? Appearance.colors.colLayer2 : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } }
            HoverHandler { id: rmHeadHov }
            TapHandler { onTapped: root.remapOpen = !root.remapOpen }
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 6; spacing: 6
                StyledText {
                    text: qsTr("Palette Remap")
                    font.pixelSize: Appearance.font.pixelSize.smaller - 1
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0; opacity: 0.5
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.remapPalette !== ""
                    text: {
                        const m = root.remapPalettes.find(x => x.id === root.remapPalette)
                        return m ? "· " + m.label + " (" + root.remapColors + ")" : ""
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller - 2
                    color: Appearance.colors.colPrimary; opacity: 0.85
                    elide: Text.ElideRight
                }
                Item { Layout.fillWidth: true; visible: root.remapPalette === "" }
                MaterialSymbol {
                    text: "expand_more"; iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0; opacity: 0.5
                    rotation: root.remapOpen ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
            }
        }
        Item {
            Layout.fillWidth: true
            clip: true
            Layout.preferredHeight: root.remapOpen ? remapBody.implicitHeight : 0
            // Skipped by the layout when closed, spacing included (see above).
            visible: Layout.preferredHeight > 0.5
            // Pulled up by the column's own spacing so it TOUCHES the header;
            // otherwise the container highlight would be split by a 10px gap.
            Layout.topMargin: -col.spacing
            HoverHandler { id: rmBodyHov }
            Rectangle {
                anchors.fill: parent
                z: -1
                color: (rmHeadHov.hovered || rmBodyHov.hovered) ? Appearance.colors.colLayer2 : "transparent"
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: 20
                bottomRightRadius: 20
                Behavior on color { ColorAnimation { duration: 100 } }
            }
            opacity: root.remapOpen ? 1 : 0
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 140 } }

            ColumnLayout {
                id: remapBody
                width: parent.width; spacing: 6

                // Palette chips
                Flow { Layout.fillWidth: true; spacing: 4
                    Repeater {
                        model: root.remapPalettes
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool active: root.remapPalette === modelData.id
                            implicitWidth: rmRow.implicitWidth + 14; implicitHeight: 24; radius: 12
                            color: active ? modelData.color : (rmChipHov.hovered ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1)
                            Behavior on color { ColorAnimation { duration: 100 } }
                            HoverHandler { id: rmChipHov }
                            TapHandler { onTapped: root.remapPalette = modelData.id }
                            Row { id: rmRow; anchors.centerIn: parent; spacing: 5
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; visible: !active; width: 6; height: 6; radius: 3; color: modelData.color; opacity: 0.9 }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter; text: modelData.label
                                    font.pixelSize: Appearance.font.pixelSize.smaller - 2
                                    color: active ? "white" : Appearance.colors.colOnLayer0; opacity: active ? 1 : 0.7
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                            }
                        }
                    }
                }

                // Colors quantization picker
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.remapPalette !== ""
                    StyledText {
                        text: qsTr("Colors")
                        font.pixelSize: Appearance.font.pixelSize.smaller - 2
                        color: Appearance.colors.colOnLayer0; opacity: 0.5
                        Layout.preferredWidth: 50
                    }
                    Repeater {
                        model: root.colorOptions
                        delegate: Rectangle {
                            required property int modelData
                            readonly property bool active: root.remapColors === modelData
                            Layout.fillWidth: true
                            implicitHeight: 22; radius: 11
                            color: active ? Appearance.colors.colSecondaryContainer
                                          : (cHov.hovered ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1)
                            Behavior on color { ColorAnimation { duration: 100 } }
                            HoverHandler { id: cHov }
                            TapHandler { onTapped: root.remapColors = modelData }
                            StyledText {
                                anchors.centerIn: parent; text: modelData
                                font.pixelSize: Appearance.font.pixelSize.smaller - 2
                                color: active ? Appearance.m3colors.m3onSecondaryContainer
                                              : Appearance.colors.colOnLayer0
                                opacity: active ? 1 : 0.7
                            }
                        }
                    }
                }

                // Dither picker
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.remapPalette !== ""
                    StyledText {
                        text: qsTr("Dither")
                        font.pixelSize: Appearance.font.pixelSize.smaller - 2
                        color: Appearance.colors.colOnLayer0; opacity: 0.5
                        Layout.preferredWidth: 50
                    }
                    Repeater {
                        model: [
                            { id: "none",                  label: "None" },
                            { id: "FloydSteinberg2x2",     label: "2×2"  },
                            { id: "FloydSteinberg",        label: "FS"   },
                            { id: "8x8",                   label: "8×8"  },
                            { id: "16x16",                 label: "16×16"},
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool active: root.remapDither === modelData.id
                            Layout.fillWidth: true
                            implicitHeight: 22; radius: 11
                            color: active ? Appearance.colors.colSecondaryContainer
                                          : (dHov.hovered ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1)
                            Behavior on color { ColorAnimation { duration: 100 } }
                            HoverHandler { id: dHov }
                            TapHandler { onTapped: root.remapDither = modelData.id }
                            StyledText {
                                anchors.centerIn: parent; text: modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller - 2
                                color: active ? Appearance.m3colors.m3onSecondaryContainer
                                              : Appearance.colors.colOnLayer0
                                opacity: active ? 1 : 0.7
                            }
                        }
                    }
                }
            }
        }

        // ── Adjustments dropdown ──────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            // 40, not 26. These are the panel's main navigation rows and they
            // read as thin dividers at 26 next to the 40px buttons around them.
            height: 40; radius: 20
            // Square the bottom corners while open so the header and the body
            // below read as ONE container rather than two stacked pills.
            bottomLeftRadius:  root.adjustOpen ? 0 : 20
            bottomRightRadius: root.adjustOpen ? 0 : 20
            color: (adjHeadHov.hovered || adjBodyHov.hovered) ? Appearance.colors.colLayer2 : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } }
            HoverHandler { id: adjHeadHov }
            TapHandler { onTapped: root.adjustOpen = !root.adjustOpen }
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 6; spacing: 6
                StyledText {
                    text: qsTr("Adjustments")
                    font.pixelSize: Appearance.font.pixelSize.smaller - 1
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0; opacity: 0.5
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.adjustChangedCount > 0
                    text: "\u00b7 " + root.adjustChangedCount + qsTr(" changed")
                    font.pixelSize: Appearance.font.pixelSize.smaller - 2
                    color: Appearance.colors.colPrimary; opacity: 0.85
                    elide: Text.ElideRight
                }
                Item { Layout.fillWidth: true; visible: root.adjustChangedCount === 0 }
                MaterialSymbol {
                    text: "expand_more"; iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0; opacity: 0.5
                    rotation: root.adjustOpen ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
            }
        }

        // Collapsed by default like every other section here. A bare Repeater
        // cannot be height-animated on its own -- it has no item of its own in
        // the layout -- so the sliders live in a ColumnLayout inside a clipped
        // Item, which is what the Color Theory / Tone Curve sections do too.
        Item {
            Layout.fillWidth: true
            clip: true
            Layout.preferredHeight: root.adjustOpen ? adjCol.implicitHeight : 0
            // Skipped by the layout when closed, spacing included (see above).
            visible: Layout.preferredHeight > 0.5
            // Pulled up by the column's own spacing so it TOUCHES the header;
            // otherwise the container highlight would be split by a 10px gap.
            Layout.topMargin: -col.spacing
            HoverHandler { id: adjBodyHov }
            Rectangle {
                anchors.fill: parent
                z: -1
                color: (adjHeadHov.hovered || adjBodyHov.hovered) ? Appearance.colors.colLayer2 : "transparent"
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: 20
                bottomRightRadius: 20
                Behavior on color { ColorAnimation { duration: 100 } }
            }
            opacity: root.adjustOpen ? 1 : 0
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 140 } }
            ColumnLayout {
                id: adjCol
                width: parent.width
                spacing: 4
                // Sliders — each delegate reads root.c{i}a / root.c{i}b directly as live bindings
                Repeater {
                    model: root.sliderDefs
                    delegate: RowLayout {
                        required property var modelData
                        required property int index
                        // No fixed height any more: StyledSlider's handle is 33px
                        // tall, so pinning the row at 22 clipped it. Let the row
                        // take the slider's own implicit height.
                        Layout.fillWidth: true; spacing: 8

                        // Direct property bindings — QML tracks these as reactive dependencies
                        readonly property color ca: root[modelData.ai]
                        readonly property color cb: root[modelData.bi]

                        StyledText {
                            text: modelData.label; font.pixelSize: Appearance.font.pixelSize.smaller - 2
                            color: Appearance.colors.colOnLayer0; opacity: 0.55; Layout.preferredWidth: 66
                        }
                        // The shared M3 slider, same as the per-app colour popup
                        // uses -- but carrying this row's own gradient endpoints
                        // instead of the theme accent. This was a hand-rolled 3px
                        // line with a 12px dot, which read as a hairline next to
                        // every other slider in the shell.
                        //
                        // StyledSlider paints flat fills, not gradients, so the
                        // far colour drives the fill and handle while the near one
                        // tints the empty track -- the same two colours, just not
                        // interpolated across the bar.
                        StyledSlider {
                            Layout.fillWidth: true
                            configuration: StyledSlider.Configuration.S
                            from: 0
                            to: 100
                            value: root[modelData.prop]
                            highlightColor: cb
                            handleColor: cb
                            // Mixed toward the panel's own container colour rather
                            // than just made transparent. Straight transparency let
                            // each row's near-colour through at full character, so
                            // the empty track came out solid olive on Temperature,
                            // grey on Saturation and invisible on Brightness -- ten
                            // different chromes down one column. A 25% tint keeps a
                            // hint of the row's colour on a consistent base.
                            trackColor: ColorUtils.mix(ca, Appearance.colors.colSecondaryContainer, 0.25)
                            usePercentTooltip: false
                            tooltipContent: {
                                const v = Math.round(root[modelData.prop] - 50)
                                return v > 0 ? "+" + v : String(v)
                            }
                            onMoved: root[modelData.prop] = value
                            Behavior on highlightColor { ColorAnimation { duration: 500 } }
                            Behavior on trackColor { ColorAnimation { duration: 500 } }
                        }
                        StyledText {
                            readonly property int v: Math.round(root[modelData.prop] - 50)
                            text: v > 0 ? "+" + v : v
                            font.pixelSize: Appearance.font.pixelSize.smaller - 3
                            color: Appearance.colors.colOnLayer0; opacity: 0.35
                            Layout.preferredWidth: 24; horizontalAlignment: Text.AlignRight
                        }
                    }
                }

            }
        }

        // Blueprints
        ColumnLayout { Layout.fillWidth: true; spacing: 4; visible: root.blueprints.length > 0
            SectionLabel { text: qsTr("Blueprints") }
            Flow { Layout.fillWidth: true; spacing: 4
                Repeater {
                    model: root.blueprints
                    delegate: Rectangle {
                        required property var modelData
                        implicitWidth: bpR.implicitWidth + 14; implicitHeight: 24; radius: Appearance.rounding.normal
                        color: bpHov.hovered ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
                        Behavior on color { ColorAnimation { duration: 100 } }
                        HoverHandler { id: bpHov }
                        TapHandler { onTapped: root.applyBlueprint(modelData.path) }
                        Row { id: bpR; anchors.centerIn: parent; spacing: 4
                            MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "auto_awesome"; iconSize: Appearance.font.pixelSize.smaller - 1; color: bpHov.hovered ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer0; opacity: 0.7 }
                            StyledText { anchors.verticalCenter: parent.verticalCenter; text: modelData.name; font.pixelSize: Appearance.font.pixelSize.smaller; color: bpHov.hovered ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer0 }
                        }
                    }
                }
            }
        }

    }
    }

    // ── Sticky bottom action bar ─────────────────────────────────────────
    Item {
        id: bottomBar
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 12
            rightMargin: 12
            bottomMargin: 12
        }
        // 48, matching the Effect dropdown, so the bar reads as the panel's
        // primary action rather than a strip of small icons under it.
        height: 48

        RowLayout {
            anchors.fill: parent
            spacing: 6

            // Reset
            Rectangle {
                implicitWidth: 48; implicitHeight: 48; radius: 24
                color: rstHov.hovered ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                Behavior on color { ColorAnimation { duration: 100 } }
                HoverHandler { margin: Appearance.sizes.touchSlop; id: rstHov }
                TapHandler { margin: Appearance.sizes.touchSlop; onTapped: root.resetSliders() }
                MaterialSymbol { anchors.centerIn: parent; text: "restart_alt"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer0; opacity: 0.5 }
            }

            // Random
            Rectangle {
                implicitWidth: 48; implicitHeight: 48; radius: 24
                color: rndHov.hovered ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                Behavior on color { ColorAnimation { duration: 100 } }
                HoverHandler { margin: Appearance.sizes.touchSlop; id: rndHov }
                TapHandler { margin: Appearance.sizes.touchSlop; onTapped: root.randomWall() }
                MaterialSymbol { anchors.centerIn: parent; text: "shuffle"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer0; opacity: 0.5 }
            }

            // Open wallpaper selector
            Rectangle {
                implicitWidth: 48; implicitHeight: 48; radius: 24
                color: wsHov.hovered ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                Behavior on color { ColorAnimation { duration: 100 } }
                HoverHandler { margin: Appearance.sizes.touchSlop; id: wsHov }
                TapHandler { margin: Appearance.sizes.touchSlop; onTapped: { GlobalStates.wallpaperSelectorOpen = true; GlobalStates.wallTuneOpen = false } }
                MaterialSymbol { anchors.centerIn: parent; text: "wallpaper"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer0; opacity: 0.5 }
            }

            // Reprocess
            Rectangle {
                Layout.fillWidth: true; implicitHeight: 48; radius: Appearance.rounding.full
                color: rpHov.hovered ? Appearance.colors.colPrimary : Qt.alpha(Appearance.colors.colPrimary, 0.15)
                Behavior on color { ColorAnimation { duration: 150 } }
                HoverHandler { id: rpHov }
                TapHandler { onTapped: if (!root.processing) root.reprocess() }
                RowLayout { anchors.centerIn: parent; spacing: 5
                    MaterialSymbol {
                        text: root.processing ? "sync" : "auto_fix_high"
                        iconSize: Appearance.font.pixelSize.small
                        color: rpHov.hovered ? "white" : Appearance.colors.colPrimary
                        Behavior on color { ColorAnimation { duration: 150 } }
                        RotationAnimation on rotation {
                            running: root.processing
                            loops: Animation.Infinite; from: 0; to: 360; duration: 900
                        }
                    }
                    StyledText {
                        text: root.processing ? (root.phaseLabel + "…") : qsTr("Reprocess")
                        font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.Medium
                        color: rpHov.hovered ? "white" : Appearance.colors.colPrimary
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }
            }
        }
    }

    // Parallax, on demand: two settings that get set once and left alone.
    PanelSheet {
        id: parallaxPopup
        open: root.parallaxOpen
        title: qsTr("Workspace parallax")
        onClosed: root.parallaxOpen = false

            Rectangle {
                Layout.fillWidth: true
                // +24 with 12px inner margins, same as the Effect card. It was
                // +14 with 10px margins, so the two cards sat at visibly
                // different densities right next to each other.
                implicitHeight: parallaxCol.implicitHeight + 24
                // Card chrome, shared with the Effect card below: one radius from
                // the ramp and one border, instead of 14-with-border here and
                // 17-without there.
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
    
                ColumnLayout {
                    id: parallaxCol
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                    spacing: 4
    
                    RowLayout {
                        Layout.fillWidth: true
                        MaterialSymbol {
                            text: "swap_horiz"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: qsTr("Workspace parallax")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer0
                        }
                        // Mini iOS-style switch.
                        Rectangle {
                            implicitWidth: 28; implicitHeight: 16; radius: 8
                            color: Config.options.background.parallax.enableWorkspace
                                ? Qt.alpha(Appearance.colors.colPrimary, 0.45)
                                : Qt.alpha(Appearance.colors.colOnLayer0, 0.20)
                            Behavior on color { ColorAnimation { duration: 140 } }
                            TapHandler {
                                margin: Appearance.sizes.touchSlop
                                onTapped: Config.options.background.parallax.enableWorkspace =
                                    !Config.options.background.parallax.enableWorkspace
                            }
                            Rectangle {
                                width: 12; height: 12; radius: 6
                                anchors.verticalCenter: parent.verticalCenter
                                x: Config.options.background.parallax.enableWorkspace
                                    ? parent.width - width - 2 : 2
                                color: Config.options.background.parallax.enableWorkspace
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colOnLayer0
                                Behavior on x     { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 140 } }
                            }
                        }
                    }
    
                    RowLayout {
                        Layout.fillWidth: true
                        enabled: Config.options.background.parallax.enableWorkspace
                        opacity: enabled ? 1 : 0.45
                        Behavior on opacity { NumberAnimation { duration: 160 } }
    
                        StyledText {
                            text: qsTr("Zoom")
                            font.pixelSize: Appearance.font.pixelSize.smaller - 1
                            color: Appearance.colors.colOnLayer0
                            opacity: 0.7
                            Layout.preferredWidth: 38
                        }
                        Slider {
                            id: zoomSlider
                            Layout.fillWidth: true
                            implicitHeight: 16
                            from: 1.00
                            to:   1.30
                            stepSize: 0.01
                            value: Config.options.background.parallax.workspaceZoom
                            onMoved: Config.options.background.parallax.workspaceZoom = value
    
                            // Custom M3-style track + thumb (the default QtQuick
                            // Slider's big dark knob looked out of place next to the
                            // panel's pill controls). Thin rounded groove, primary
                            // fill up to the thumb, small primary thumb that grows
                            // on press.
                            background: Rectangle {
                                x: zoomSlider.leftPadding
                                y: zoomSlider.topPadding + zoomSlider.availableHeight / 2 - height / 2
                                width: zoomSlider.availableWidth
                                height: 4
                                radius: 2
                                color: Qt.alpha(Appearance.colors.colOnLayer0, 0.15)
                                Rectangle {
                                    width: zoomSlider.position * parent.width
                                    height: parent.height
                                    radius: parent.radius
                                    color: Appearance.colors.colPrimary
                                }
                            }
                            handle: Rectangle {
                                x: zoomSlider.leftPadding + zoomSlider.position * (zoomSlider.availableWidth - width)
                                y: zoomSlider.topPadding + zoomSlider.availableHeight / 2 - height / 2
                                implicitWidth: 14
                                implicitHeight: 14
                                radius: 7
                                color: Appearance.colors.colPrimary
                                scale: zoomSlider.pressed ? 1.25 : (zoomHov.hovered ? 1.1 : 1)
                                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                HoverHandler { id: zoomHov }
                            }
                        }
                        StyledText {
                            text: Math.round(Config.options.background.parallax.workspaceZoom * 100) + "%"
                            font.pixelSize: Appearance.font.pixelSize.smaller - 1
                            color: Appearance.colors.colOnLayer0
                            Layout.preferredWidth: 38
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }
    }
}


