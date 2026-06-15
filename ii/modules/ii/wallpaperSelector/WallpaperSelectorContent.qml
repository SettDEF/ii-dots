import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import Quickshell.Io

MouseArea {
    id: root
    property int columns: 4
    property real previewCellAspectRatio: 4 / 3
    property bool useDarkMode: Appearance.m3colors.darkmode

    // "folder" = normal directory grid; "recents" = recent wallpapers grid
    property string viewMode: "folder"

    // ── Filters (persisted in Persistent.states.wallpaperPicker) ─────
    //   typeFilter:  "all" | "pic" | "vid"
    //   sortMode:    "newest" | "oldest" | "az" | "za" | "largest" | "smallest"
    //   orientation: "all" | "landscape" | "portrait" | "square"
    // Applied to Wallpapers.nameFilters / sortField / via a derived list
    // (orientation needs per-file dimension lookup; handled at grid level).
    property string typeFilter:  Persistent.states.wallpaperPicker?.typeFilter  ?? "all"
    property string sortMode:    Persistent.states.wallpaperPicker?.sortMode    ?? "newest"
    property string orientation: Persistent.states.wallpaperPicker?.orientation ?? "all"

    onTypeFilterChanged: {
        if (Persistent.states.wallpaperPicker)
            Persistent.states.wallpaperPicker.typeFilter = typeFilter
        _reapplyFilters()
    }
    onSortModeChanged: {
        if (Persistent.states.wallpaperPicker)
            Persistent.states.wallpaperPicker.sortMode = sortMode
        _reapplyFilters()
    }
    onOrientationChanged: {
        if (Persistent.states.wallpaperPicker)
            Persistent.states.wallpaperPicker.orientation = orientation
        _reapplyFilters()
    }

    // Derived extension list — drives Wallpapers.nameFilters indirectly.
    readonly property var activeExtensions: {
        switch (typeFilter) {
            case "pic": return Wallpapers.extensions
            case "vid": return Wallpapers.videoExtensions
            default:    return Wallpapers.allExtensions
        }
    }
    // Apply type + sort to the Wallpapers service.
    Connections {
        target: Wallpapers
        function onSearchQueryChanged() { root._reapplyFilters() }
    }
    function _reapplyFilters() {
        const exts = root.activeExtensions
        const q = (Wallpapers.searchQuery || "").split(" ").filter(s => s.length > 0)
        const patterns = exts.map(ext =>
            q.length > 0
                ? q.map(s => `*${s}*`).join("") + `*.${ext}`
                : `*.${ext}`)
        Wallpapers.folderModel.nameFilters = patterns
        // FolderListModel sortField: 0 Unsorted, 1 Name, 2 Time, 3 Size, 4 Type.
        switch (root.sortMode) {
            case "oldest":   Wallpapers.folderModel.sortField = 2; Wallpapers.folderModel.sortReversed = false; break
            case "az":       Wallpapers.folderModel.sortField = 1; Wallpapers.folderModel.sortReversed = false; break
            case "za":       Wallpapers.folderModel.sortField = 1; Wallpapers.folderModel.sortReversed = true;  break
            case "largest":  Wallpapers.folderModel.sortField = 3; Wallpapers.folderModel.sortReversed = true;  break
            case "smallest": Wallpapers.folderModel.sortField = 3; Wallpapers.folderModel.sortReversed = false; break
            case "newest":
            default:         Wallpapers.folderModel.sortField = 2; Wallpapers.folderModel.sortReversed = true;  break
        }
    }
    // (Component.onCompleted is merged with loadWalltuneStateProc below)

    function updateThumbnails() {
        const totalImageMargin = (Appearance.sizes.wallpaperSelectorItemMargins + Appearance.sizes.wallpaperSelectorItemPadding) * 2
        const thumbnailSizeName = Images.thumbnailSizeNameForDimensions(grid.cellWidth - totalImageMargin, grid.cellHeight - totalImageMargin)
        Wallpapers.generateThumbnail(thumbnailSizeName)
    }

    Connections {
        target: Wallpapers
        function onDirectoryChanged() {
            root.updateThumbnails()
            root.clearSelection()
            // Dismiss any open right-click menu — its captured filePath is
            // no longer in view, so leaving it open would act on the wrong tile.
            if (ctxMenu.opened) ctxMenu.dismiss()
        }
    }

    function handleFilePasting(event) {
        const currentClipboardEntry = Cliphist.entries[0]
        if (/^\d+\tfile:\/\/\S+/.test(currentClipboardEntry)) {
            const url = StringUtils.cleanCliphistEntry(currentClipboardEntry);
            Wallpapers.setDirectory(FileUtils.trimFileProtocol(decodeURIComponent(url)));
            event.accepted = true;
        } else {
            event.accepted = false; // No image, let text pasting proceed
        }
    }

    property bool walltuneActiveConfig: false
    property var walltuneStateData: ({})
    property string pendingWallpaperPath: ""

    function hasCustomWalltuneConfig(state) {
        if (!state) return false;
        const defaults = {
            slVibrance: 50,
            slContrast: 50,
            slTemperature: 50,
            slBrightness: 50,
            slSaturation: 50,
            slHueShift: 50,
            slHighlight: 50,
            slShadow: 50,
            slGrain: 0,
            slSharpness: 50,
            selectedMode: "",
            selectedTheory: "",
            selectedStyle: "",
            selectedPractical: "",
            remapPalette: ""
        };
        for (let key in defaults) {
            if (state[key] !== undefined && state[key] !== defaults[key]) {
                return true;
            }
        }
        if (state.curvePoints !== undefined && Array.isArray(state.curvePoints)) {
            if (state.curvePoints.length !== 2) return true;
            const a = state.curvePoints[0];
            const b = state.curvePoints[1];
            if (!a || !b || a[0] !== 0 || a[1] !== 0 || b[0] !== 1 || b[1] !== 1) {
                return true;
            }
        }
        return false;
    }

    function selectWallpaperPath(filePath) {
        if (filePath && filePath.length > 0) {
            filterField.text = "";

            if (Images.isValidImageByName(filePath) && root.walltuneActiveConfig) {
                root.applyWalltuneToWallpaper(filePath);
                GlobalStates.wallpaperSelectorOpen = false;
            } else {
                Wallpapers.select(filePath, root.useDarkMode);
            }
        }
    }

    // ── Context-menu helpers ────────────────────────────────────────────
    function copyPath(p) {
        Quickshell.execDetached(["wl-copy", "--", FileUtils.trimFileProtocol(p)])
    }
    function showInFiles(p) {
        Quickshell.execDetached(["xdg-open",
            FileUtils.parentDirectory(FileUtils.trimFileProtocol(p))])
    }
    function applyMode(p, dark) {
        Wallpapers.apply(FileUtils.trimFileProtocol(p), dark)
        GlobalStates.wallpaperSelectorOpen = false
        GlobalStates.requestAdjusterOpen()
    }
    function applyAndAdjust(p) {
        selectWallpaperPath(p)
        GlobalStates.requestAdjusterOpen()
    }
    // ── Multi-select + delete ───────────────────────────────────────────
    property var selectedSet: ({})
    readonly property int selectedCount: Object.keys(selectedSet).length
    function isSelected(p) { return root.selectedSet[p] === true }
    function toggleSelect(p) {
        const s = Object.assign({}, root.selectedSet)
        if (s[p]) delete s[p]; else s[p] = true
        root.selectedSet = s
    }
    function clearSelection() { root.selectedSet = ({}) }
    function doDelete(paths) {
        if (!paths || paths.length === 0) return
        Quickshell.execDetached(["rm", "-f", "--"]
            .concat(paths.map(p => FileUtils.trimFileProtocol(p))))
        root.clearSelection()
        Qt.callLater(root.updateThumbnails)
    }
    // Two-step confirm: re-opens the menu at the same spot as a verify step.
    function confirmDelete(paths) {
        const n = paths.length
        Qt.callLater(() => ctxMenu.popup(ctxMenu.px, ctxMenu.py, [
            { icon: "delete_forever", danger: true,
              label: "Delete " + n + " wallpaper" + (n > 1 ? "s" : ""),
              onTriggered: () => root.doDelete(paths) },
            { icon: "close", label: "Cancel", onTriggered: () => {} }
        ]))
    }

    function menuForFile(f) {
        const path = f.filePath
        if (f.fileIsDir) return [
            { icon: "folder_open",  label: "Open folder", onTriggered: () => Wallpapers.setDirectory(path) },
            { icon: "content_copy", label: "Copy path",   onTriggered: () => root.copyPath(path) }
        ]
        const isVid = /\.(mp4|webm|mkv|avi|mov|m4v|gif)$/i.test(f.fileName ?? "")
        const m = [{ icon: "wallpaper", label: "Apply wallpaper",
                     onTriggered: () => root.selectWallpaperPath(path) }]
        m.push({ icon: "crop", label: "Apply & adjust crop…",
                 onTriggered: () => root.applyAndAdjust(path) })
        if (!isVid) {
            m.push({ icon: "light_mode", label: "Apply · light mode",
                     onTriggered: () => root.applyMode(path, false) })
            m.push({ icon: "dark_mode",  label: "Apply · dark mode",
                     onTriggered: () => root.applyMode(path, true) })
        }
        m.push({ separator: true })
        const sel = root.isSelected(path)
        m.push({ icon: sel ? "check_box" : "check_box_outline_blank",
                 label: sel ? "Deselect" : "Select",
                 onTriggered: () => root.toggleSelect(path) })
        const n = root.selectedCount
        if (n > 0 && sel)
            m.push({ icon: "delete", danger: true, label: "Delete " + n + " selected…",
                     onTriggered: () => root.confirmDelete(Object.keys(root.selectedSet)) })
        else
            m.push({ icon: "delete", danger: true, label: "Delete wallpaper…",
                     onTriggered: () => root.confirmDelete([path]) })
        m.push({ separator: true })
        m.push({ icon: "content_copy", label: "Copy path",     onTriggered: () => root.copyPath(path) })
        m.push({ icon: "folder",       label: "Show in files", onTriggered: () => root.showInFiles(path) })
        return m
    }
    function menuForRecent(path) {
        return [
            { icon: "wallpaper",    label: "Apply wallpaper", onTriggered: () => root.selectWallpaperPath(path) },
            { icon: "crop",         label: "Apply & adjust crop…", onTriggered: () => root.applyAndAdjust(path) },
            { separator: true },
            { icon: "content_copy", label: "Copy path",       onTriggered: () => root.copyPath(path) },
            { icon: "folder",       label: "Show in files",   onTriggered: () => root.showInFiles(path) }
        ]
    }
    function menuGeneral() {
        return [
            { icon: "crop", label: "Adjust current wallpaper…",
              onTriggered: () => GlobalStates.wallpaperAdjusterOpen = true },
            { icon: "refresh", label: "Refresh thumbnails", onTriggered: () => root.updateThumbnails() },
            { icon: "ifl",     label: "Random from this folder",
              onTriggered: () => Wallpapers.randomFromCurrentFolder(root.useDarkMode) },
            { separator: true },
            { icon: "open_in_new", label: "System file picker", onTriggered: () => {
                Wallpapers.openFallbackPicker(root.useDarkMode)
                GlobalStates.wallpaperSelectorOpen = false
            } }
        ]
    }

    Connections {
        target: Wallpapers
        function onChanged() {
            GlobalStates.wallpaperSelectorOpen = false;
        }
    }

    Component.onCompleted: {
        loadWalltuneStateProc.running = true
        Qt.callLater(_reapplyFilters)
    }

    Process {
        id: loadWalltuneStateProc
        command: ["bash", "-c", "cat '" + FileUtils.trimFileProtocol(Directories.home) + "/.local/state/quickshell/walltune-state.json' 2>/dev/null || echo '{}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const state = JSON.parse(text)
                    root.walltuneStateData = state
                    root.walltuneActiveConfig = root.hasCustomWalltuneConfig(state)
                } catch(e) { root.walltuneActiveConfig = false }
            }
        }
    }

    Process {
        id: applyWalltuneProc
        onRunningChanged: if (!running) {
            GlobalStates.wallpaperSelectorOpen = false
            Qt.callLater(() => GlobalStates.wallpaperAdjusterOpen = true)
        }
    }

    function applyWalltuneToWallpaper(wallPath) {
        const s = root.walltuneStateData;
        if (!s) {
            return;
        }

        const home = FileUtils.trimFileProtocol(Directories.home);
        const scriptDir = home + "/.config/quickshell/ii/scripts/colors";
        const cacheDir = home + "/.cache/quickshell/walltune";

        const mode = root.useDarkMode ? "dark" : "light";

        // Read and flip the slot
        const slot = (root.walltuneStateData.lastProcessedSlot === "a") ? "b" : "a";
        const tmp = cacheDir + "/processed-" + slot + ".png";

        // Retrieve slider settings from walltuneStateData
        const slVibrance    = s.slVibrance    !== undefined ? s.slVibrance    : 50;
        const slBrightness  = s.slBrightness  !== undefined ? s.slBrightness  : 50;
        const slSaturation  = s.slSaturation  !== undefined ? s.slSaturation  : 50;
        const slHueShift    = s.slHueShift    !== undefined ? s.slHueShift    : 50;
        const slContrast    = s.slContrast    !== undefined ? s.slContrast    : 50;
        const slSharpness   = s.slSharpness   !== undefined ? s.slSharpness   : 50;
        const slGrain       = s.slGrain       !== undefined ? s.slGrain       : 0;
        const slTemperature = s.slTemperature !== undefined ? s.slTemperature : 50;

        const brightness = Math.round(slBrightness + 50);
        const saturation = Math.round(slSaturation * 2);
        const hue        = Math.round(slHueShift * 2);
        const contrast   = Math.round((slContrast - 50) * 2);
        const sharpness  = slSharpness > 50 ? ((slSharpness - 50) / 10).toFixed(1) : "0";
        const blur       = slSharpness < 50 ? ((50 - slSharpness) / 20).toFixed(1) : "0";
        const grain      = Math.round(slGrain * 0.4);

        const temp   = slTemperature - 50;
        const tBoost = Math.abs(Math.round(temp * 0.8));

        const srcWall = wallPath;

        // Build magick args
        let magickArgs = ["magick", srcWall,
            "-modulate", brightness + "," + saturation + "," + hue,
            "-brightness-contrast", "0," + contrast];

        if (temp > 0) {
            magickArgs = magickArgs.concat(["-channel", "Red",  "-evaluate", "add",      tBoost + "%", "+channel",
                                            "-channel", "Blue", "-evaluate", "subtract", tBoost + "%", "+channel"]);
        } else if (temp < 0) {
            magickArgs = magickArgs.concat(["-channel", "Red",  "-evaluate", "subtract", tBoost + "%", "+channel",
                                            "-channel", "Blue", "-evaluate", "add",      tBoost + "%", "+channel"]);
        }

        if (parseFloat(sharpness) > 0) magickArgs = magickArgs.concat(["-unsharp", "0x" + sharpness]);
        if (parseFloat(blur)      > 0) magickArgs = magickArgs.concat(["-blur",    "0x" + blur]);
        if (grain > 0)                 magickArgs = magickArgs.concat(["-attenuate", (grain / 100).toFixed(2), "+noise", "Gaussian"]);

        // Tone curve check
        const lutPath = cacheDir + "/curve.pgm";
        const curvePoints = s.curvePoints !== undefined ? s.curvePoints : [[0,0],[1,1]];
        const useLut = (curvePoints.length !== 2 || curvePoints[0][0] !== 0 || curvePoints[0][1] !== 0 || curvePoints[1][0] !== 1 || curvePoints[1][1] !== 1);

        if (useLut) magickArgs = magickArgs.concat(["-interpolate", "Bicubic", lutPath, "-clut"]);
        magickArgs.push(tmp);

        // Curve python generation step
        const curvePy = scriptDir + "/walltune-curve.py";
        const ptsStr  = curvePoints.map(p => p[0] + "," + p[1]).join(";");
        const lutStep = useLut
            ? `python3 '${curvePy}' lut '${ptsStr}' '${lutPath}'`
            : `:`;

        // Switchwall and remapping settings
        const switchwall = Directories.wallpaperSwitchScriptPath;
        const selectedMode = s.selectedMode || "";
        const selectedTheory = s.selectedTheory || "";
        const selectedStyle = s.selectedStyle || "";
        const selectedPractical = s.selectedPractical || "";
        const remapPalette = s.remapPalette || "";
        const remapColors = s.remapColors !== undefined ? s.remapColors : 32;
        const remapDither = s.remapDither !== undefined ? s.remapDither : "FloydSteinberg2x2";
        const applyMode = s.applyMode || "both";

        const schemeArg = selectedMode !== "" ? "--type " + selectedMode : "";
        const theoryArg    = selectedTheory    !== "" ? "--theory "    + selectedTheory    : "";
        const styleArg     = selectedStyle     !== "" ? "--style "     + selectedStyle     : "";
        const practicalArg = selectedPractical !== "" ? "--practical " + selectedPractical : "";
        const remapArg     = (remapPalette !== "" && remapPalette !== "matugen") ? "--remap " + remapPalette : "";

        // Remap runs FIRST so the magick adjustments land on top of the
        // palette and stay visible (see WallTuneContent.qml for the rationale).
        let preRemapStep = ":";
        if (remapPalette !== "") {
            const rdmc = home + "/.scripts/rdmcpape";
            const palArg = remapPalette === "matugen"
                ? "--matugen"
                : "--palette " + remapPalette;
            preRemapStep = `'${rdmc}' ${palArg} --colors ${remapColors} --dither ${remapDither} --output '${tmp}' '${srcWall}'`;
            magickArgs[1] = tmp;  // adjustments now read the remapped file
        }

        // Save updated state file step
        const newState = Object.assign({}, root.walltuneStateData, {
            sourceWall: srcWall,
            lastProcessedSlot: slot
        });
        const newStateJsonStr = JSON.stringify(newState);
        const stateFile = home + "/.local/state/quickshell/walltune-state.json";
        const saveStateStep = `mkdir -p "$(dirname '${stateFile}')" && printf '%s' '${newStateJsonStr.replace(/'/g, "'\\''")}' > '${stateFile}'`;

        // Save history entry step
        const snap = {
            slVibrance: slVibrance, slContrast: slContrast, slTemperature: slTemperature,
            slBrightness: slBrightness, slSaturation: slSaturation, slHueShift: slHueShift,
            slHighlight: s.slHighlight !== undefined ? s.slHighlight : 50,
            slShadow: s.slShadow !== undefined ? s.slShadow : 50,
            slGrain: s.slGrain !== undefined ? s.slGrain : 0,
            slSharpness: slSharpness,
            selectedMode: selectedMode, selectedTheory: selectedTheory,
            selectedStyle: selectedStyle, selectedPractical: selectedPractical,
            curvePoints: curvePoints, remapPalette: remapPalette,
            remapColors: remapColors, remapDither: remapDither,
            darkMode: root.useDarkMode
        };
        const snapJson = JSON.stringify(snap).replace(/'/g, "'\\''");

        const histStep = [
            `hist="$HOME/.local/state/quickshell/walltune-history.jsonl"`,
            `mkdir -p "$(dirname "$hist")"`,
            `cj="$HOME/.local/state/quickshell/user/generated/colors.json"`,
            `if [ -f "$cj" ]; then`,
            `  pri=$(jq -r '.primary // ""' "$cj")`,
            `  sec=$(jq -r '.secondary // ""' "$cj")`,
            `  ter=$(jq -r '.tertiary // ""' "$cj")`,
            `  ts=$(date +%s)`,
            `  thumb_dir="${cacheDir}/thumbs"`,
            `  mkdir -p "$thumb_dir"`,
            `  thumb_path="$thumb_dir/$ts.png"`,
            `  magick '${tmp}' -thumbnail 160x120 "$thumb_path"`,
            `  jq -cn --arg p "$pri" --arg s "$sec" --arg t "$ter" --arg w '${srcWall}' \\`,
            `        --arg th "$thumb_path" --argjson st '${snapJson}' --argjson ts "$ts" \\`,
            `        '{ts:$ts, primary:$p, secondary:$s, tertiary:$t, wallpaper:$w, thumbnail:$th, state:$st}' >> "$hist"`,
            `  if [ $(wc -l < "$hist") -gt 40 ]; then`,
            `    tmp_hist=$(mktemp) && tail -n 40 "$hist" > "$tmp_hist" && mv "$tmp_hist" "$hist"`,
            `  fi`,
            `fi`,
            `# Add to standard wallpaper recents`,
            `recents="$HOME/.local/state/quickshell/wallpaper-recents.jsonl"`,
            `if [ -f "$recents" ]; then`,
            `  tmp_rec=$(mktemp) && jq -c --arg p '${srcWall}' 'select(.path != $p)' "$recents" > "$tmp_rec" && mv "$tmp_rec" "$recents"`,
            `fi`,
            `jq -cn --arg p '${srcWall}' --argjson t $(date +%s) '{type:"recent",path:$p,ts:$t}' >> "$recents"`,
            `if [ $(wc -l < "$recents") -gt 40 ]; then`,
            `  tmp_rec=$(mktemp) && tail -n 40 "$recents" > "$tmp_rec" && mv "$tmp_rec" "$recents"`,
            `fi`
        ].join("\n");

        const cfg = home + "/.config/illogical-impulse/config.json";
        let pipelineSteps = [];

        if (applyMode === "colors") {
            const colorsTmp = cacheDir + "/colors-source.png";
            const magickArgsColors = magickArgs.slice();
            magickArgsColors[magickArgsColors.length - 1] = colorsTmp;
            pipelineSteps = [
                preRemapStep,
                magickArgsColors.map(a => `'${a.replace(/'/g, "'\\''")}'`).join(" "),
                `'${switchwall}' --image '${colorsTmp}' --mode ${mode} --no-wallpaper-update ${schemeArg} ${theoryArg} ${styleArg} ${practicalArg} ${remapArg}`,
                `jq --arg p '${srcWall}' --arg src '${srcWall}' '.background.wallpaperPath = $p | .background.wallpaperSourcePath = $src' '${cfg}' > '${cfg}.tmp' && mv '${cfg}.tmp' '${cfg}'`,
            ];
        } else if (applyMode === "wallpaper") {
            pipelineSteps = [
                preRemapStep,
                magickArgs.map(a => `'${a.replace(/'/g, "'\\''")}'`).join(" "),
                `jq --arg p '${tmp}' --arg src '${srcWall}' '.background.wallpaperPath = $p | .background.wallpaperSourcePath = $src' '${cfg}' > '${cfg}.tmp' && mv '${cfg}.tmp' '${cfg}'`,
                `'${switchwall}' --image '${srcWall}' --mode ${mode} --no-wallpaper-update ${schemeArg}`,
            ];
        } else { // "both"
            pipelineSteps = [
                preRemapStep,
                magickArgs.map(a => `'${a.replace(/'/g, "'\\''")}'`).join(" "),
                `'${switchwall}' --image '${tmp}' --mode ${mode} --no-wallpaper-update ${schemeArg} ${theoryArg} ${styleArg} ${practicalArg} ${remapArg}`,
                `jq --arg p '${tmp}' --arg src '${srcWall}' '.background.wallpaperPath = $p | .background.wallpaperSourcePath = $src' '${cfg}' > '${cfg}.tmp' && mv '${cfg}.tmp' '${cfg}'`,
            ];
        }

        const script = [
            "set -e",
            `mkdir -p '${cacheDir}'`,
            lutStep,
            ...pipelineSteps,
            saveStateStep,
            histStep
        ].join("\n");

        const wrapperScript = `
echo "START" > /tmp/walltune-debug.log
echo "$1" > /tmp/walltune-script.sh
eval "$1" >> /tmp/walltune-debug.log 2>&1
echo "Done with exit code $?" >> /tmp/walltune-debug.log
notify-send -a "WallTune" -i "color-management" "WallTune" "Applied custom configuration to new wallpaper."
`;
        Quickshell.execDetached(["bash", "-c", wrapperScript, "--", script]);
    }

    // ── Wallpaper recents (last 40) ─────────────────────────────────────
    // Backed by the shared WallpaperRecents singleton (services/) so the
    // wallpaper picker, Nexus theme tab, and WallTune all see the same list
    // without each spawning their own bash process.
    readonly property var wallpaperRecents: WallpaperRecents.recents

    Connections {
        target: GlobalStates
        function onWallpaperSelectorOpenChanged() {
            if (GlobalStates.wallpaperSelectorOpen) {
                WallpaperRecents.refreshRecents()
                loadWalltuneStateProc.running = true
            }
        }
    }

    acceptedButtons: Qt.BackButton | Qt.ForwardButton | Qt.RightButton
    onPressed: event => {
        if (event.button === Qt.BackButton) {
            Wallpapers.navigateBack();
        } else if (event.button === Qt.ForwardButton) {
            Wallpapers.navigateForward();
        } else if (event.button === Qt.RightButton) {
            ctxMenu.popup(event.x, event.y, root.menuGeneral());
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (ctxMenu.opened) ctxMenu.dismiss();
            else GlobalStates.wallpaperSelectorOpen = false;
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) { // Intercept Ctrl+V to handle "paste to go to" in pickers
            root.handleFilePasting(event);
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Up) {
            Wallpapers.navigateUp();
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Left) {
            Wallpapers.navigateBack();
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Right) {
            Wallpapers.navigateForward();
            event.accepted = true;
        } else if (event.key === Qt.Key_Left) {
            grid.moveSelection(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            grid.moveSelection(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            grid.moveSelection(-grid.columns);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            grid.moveSelection(grid.columns);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            grid.activateCurrent();
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace) {
            if (filterField.text.length > 0) {
                filterField.text = filterField.text.substring(0, filterField.text.length - 1);
            }
            filterField.forceActiveFocus();
            event.accepted = true;
        } else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_L) {
            addressBar.focusBreadcrumb();
            event.accepted = true;
        } else if (event.key === Qt.Key_Slash) {
            filterField.forceActiveFocus();
            event.accepted = true;
        } else {
            if (event.text.length > 0) {
                filterField.text += event.text;
                filterField.cursorPosition = filterField.text.length;
                filterField.forceActiveFocus();
            }
            event.accepted = true;
        }
    }

    implicitHeight: mainLayout.implicitHeight
    implicitWidth: mainLayout.implicitWidth

    StyledRectangularShadow {
        target: wallpaperGridBackground
    }
    Rectangle {
        id: wallpaperGridBackground
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
        focus: true
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

        property int calculatedRows: Math.ceil(grid.count / grid.columns)

        implicitWidth: gridColumnLayout.implicitWidth
        implicitHeight: gridColumnLayout.implicitHeight

        RowLayout {
            id: mainLayout
            anchors.fill: parent
            spacing: -4

            Rectangle {
                Layout.fillHeight: true
                Layout.margins: 4
                implicitWidth: quickDirColumnLayout.implicitWidth
                implicitHeight: quickDirColumnLayout.implicitHeight
                color: Appearance.colors.colLayer1
                radius: wallpaperGridBackground.radius - Layout.margins

                ColumnLayout {
                    id: quickDirColumnLayout
                    anchors.fill: parent
                    spacing: 0

                    StyledText {
                        Layout.margins: 12
                        font {
                            pixelSize: Appearance.font.pixelSize.normal
                            weight: Font.Medium
                        }
                        text: Translation.tr("Pick a wallpaper")
                    }
                    ListView {
                        // Quick dirs
                        Layout.fillHeight: true
                        Layout.margins: 4
                        implicitWidth: 140
                        clip: true
                        model: [
                            { icon: "home", name: "Home", path: Directories.home },
                            { icon: "docs", name: "Documents", path: Directories.documents },
                            { icon: "download", name: "Downloads", path: Directories.downloads },
                            { icon: "image", name: "Pictures", path: Directories.pictures },
                            { icon: "movie", name: "Videos", path: Directories.videos },
                            { icon: "", name: "---", path: "INTENTIONALLY_INVALID_DIR" },
                            { icon: "wallpaper", name: "Wallpapers", path: `${Directories.pictures}/Wallpapers` },
                            // Direct shortcut to the SkwdWall download folder
                            // (FolderListModel doesn't recurse, so these files
                            // aren't visible from the parent Wallpapers view).
                            { icon: "language", name: "Skwd", path: `${Directories.pictures}/Wallpapers/skwd` },
                            ...(Config.options.policies.weeb === 1 ? [{ icon: "favorite", name: "Homework", path: `${Directories.pictures}/homework` }] : []),
                            { icon: "history", name: "Recent", path: "", action: "recents" },
                        ]
                        delegate: RippleButton {
                            id: quickDirButton
                            required property var modelData
                            anchors {
                                left: parent.left
                                right: parent.right
                            }
                            onClicked: {
                                if (quickDirButton.modelData.action === "recents") {
                                    root.viewMode = "recents"
                                    WallpaperRecents.refreshRecents()
                                } else {
                                    root.viewMode = "folder"
                                    Wallpapers.setDirectory(quickDirButton.modelData.path)
                                }
                            }
                            enabled: modelData.icon.length > 0
                            toggled: modelData.action === "recents"
                                ? root.viewMode === "recents"
                                : (root.viewMode === "folder" && Wallpapers.directory === Qt.resolvedUrl(modelData.path))
                            colBackgroundToggled: Appearance.colors.colSecondaryContainer
                            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                            colRippleToggled: Appearance.colors.colSecondaryContainerActive
                            buttonRadius: height / 2
                            implicitHeight: 38

                            contentItem: RowLayout {
                                MaterialSymbol {
                                    color: quickDirButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                    iconSize: Appearance.font.pixelSize.larger
                                    text: quickDirButton.modelData.icon
                                    fill: quickDirButton.toggled ? 1 : 0
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignLeft
                                    color: quickDirButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                    text: quickDirButton.modelData.name
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: gridColumnLayout
                Layout.fillWidth: true
                Layout.fillHeight: true

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    AddressBar {
                        id: addressBar
                        Layout.margins: 4
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        directory: Wallpapers.effectiveDirectory
                        onNavigateToDirectory: path => {
                            Wallpapers.setDirectory(path.length == 0 ? "/" : path);
                        }
                        radius: wallpaperGridBackground.radius - 4
                    }

                    // Open Wallpaper Hub (skwd-wall dube) — local + Wallhaven + Reddit
                    RippleButton {
                        id: hubButton
                        Layout.alignment: Qt.AlignVCenter
                        Layout.rightMargin: 4
                        implicitHeight: 36
                        buttonRadius: height / 2
                        toggled: false
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        StyledToolTip { text: qsTr("Wallpaper Hub — browse local + Wallhaven + Reddit") }
                        onClicked: {
                            GlobalStates.openHubFromSelector()
                        }
                        contentItem: RowLayout {
                            spacing: 6
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "travel_explore"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                text: qsTr("Hub")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }

                Item {
                    id: gridDisplayRegion
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    StyledIndeterminateProgressBar {
                        id: indeterminateProgressBar
                        visible: Wallpapers.thumbnailGenerationRunning && value == 0
                        anchors {
                            bottom: parent.top
                            left: parent.left
                            right: parent.right
                            leftMargin: 4
                            rightMargin: 4
                        }
                    }

                    StyledProgressBar {
                        visible: Wallpapers.thumbnailGenerationRunning && value > 0
                        value: Wallpapers.thumbnailGenerationProgress
                        anchors.fill: indeterminateProgressBar
                    }

                    // ── Recents grid (shown when viewMode === "recents") ─
                    GridView {
                        id: recentsGrid
                        anchors.fill: parent
                        visible: root.viewMode === "recents"
                        clip: true
                        cellWidth: width / root.columns
                        cellHeight: cellWidth / root.previewCellAspectRatio
                        model: root.wallpaperRecents
                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            width: 6
                            contentItem: Rectangle { radius: 3; color: Appearance.colors.colOutline; opacity: 0.4 }
                        }

                        delegate: Item {
                            required property string modelData
                            width: GridView.view.cellWidth
                            height: GridView.view.cellHeight

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 4
                                radius: 8
                                color: Appearance.colors.colLayer1
                                clip: true
                                readonly property bool isCurrent: modelData === Config.options.background.wallpaperPath
                                border.width: isCurrent ? 2 : (rGridHov.hovered ? 1 : 0)
                                border.color: isCurrent
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colOutline
                                Behavior on border.width { NumberAnimation { duration: 120 } }

                                ClippingRectangle {
                                    // Pre-generates a small thumbnail via
                                    // `magick`, caches it under the Freedesktop
                                    // thumbnail spec, then loads THAT instead
                                    // of decoding the full 4 K PNG every time.
                                    // Solves the silent-drop issue where large
                                    // images blew QML's scenegraph budget.
                                    anchors.fill: parent
                                    anchors.margins: parent.border.width
                                    radius: 6
                                    color: Appearance.colors.colLayer2
                                    ThumbnailImage {
                                        id: rGridImg
                                        anchors.fill: parent
                                        sourcePath: "file://" + modelData
                                        sourceSize.width: 320
                                        sourceSize.height: 320
                                        fillMode: Image.PreserveAspectCrop
                                        // Animated formats blow up magick (~8 GB / m4v).
                                        generateThumbnail: {
                                            const p = (modelData || "").toLowerCase()
                                            return !p.match(/\.(gif|mp4|webm|m4v|mkv|mov|avi)(\?|$)/)
                                        }
                                    }
                                }

                                BottomFadeOverlay {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                    visible: rGridHov.hovered
                                    barHeight: 22
                                    elide: Text.ElideMiddle
                                    text: FileUtils.fileNameForPath(modelData)
                                }

                                HoverHandler { id: rGridHov }
                                TapHandler { onTapped: root.selectWallpaperPath(modelData) }
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.RightButton
                                    onClicked: mouse => {
                                        const p = mapToItem(root, mouse.x, mouse.y);
                                        ctxMenu.popup(p.x, p.y, root.menuForRecent(modelData));
                                    }
                                }
                            }
                        }
                    }

                    // Empty-state when recents tab has no entries
                    StyledText {
                        anchors.centerIn: parent
                        visible: root.viewMode === "recents" && root.wallpaperRecents.length === 0
                        text: qsTr("No recent wallpapers yet")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer0; opacity: 0.4
                    }

                    GridView {
                        id: grid
                        visible: root.viewMode === "folder" && Wallpapers.folderModel.count > 0

                        readonly property int columns: root.columns
                        readonly property int rows: Math.max(1, Math.ceil(count / columns))
                        property int currentIndex: 0

                        anchors.fill: parent
                        cellWidth: width / root.columns
                        cellHeight: cellWidth / root.previewCellAspectRatio
                        interactive: true
                        clip: true
                        keyNavigationWraps: true
                        boundsBehavior: Flickable.StopAtBounds
                        bottomMargin: extraOptions.implicitHeight
                        ScrollBar.vertical: StyledScrollBar {}

                        Component.onCompleted: {
                            root.updateThumbnails()
                        }

                        function moveSelection(delta) {
                            currentIndex = Math.max(0, Math.min(grid.model.count - 1, currentIndex + delta));
                            positionViewAtIndex(currentIndex, GridView.Contain);
                        }

                        function activateCurrent() {
                            const filePath = grid.model.get(currentIndex, "filePath")
                            root.selectWallpaperPath(filePath);
                        }

                        model: Wallpapers.folderModel
                        onModelChanged: currentIndex = 0
                        delegate: WallpaperDirectoryItem {
                            required property var modelData
                            required property int index
                            fileModelData: modelData
                            selected: root.isSelected(modelData.filePath)
                            width: grid.cellWidth
                            height: grid.cellHeight
                            // Suppress the hover/focus highlight while a context
                            // menu is up — otherwise the tile under the menu stays
                            // visibly "active" behind it.
                            readonly property bool _highlight: !ctxMenu.opened && (index === grid?.currentIndex || containsMouse)
                            colBackground: _highlight ? Appearance.colors.colPrimary : (fileModelData.filePath === Config.options.background.wallpaperPath) ? Appearance.colors.colSecondaryContainer : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
                            colText: _highlight ? Appearance.colors.colOnPrimary : (fileModelData.filePath === Config.options.background.wallpaperPath) ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0

                            onEntered: {
                                grid.currentIndex = index;
                            }
                            
                            onActivated: {
                                root.selectWallpaperPath(fileModelData.filePath);
                            }
                            onContextRequested: (mx, my) => {
                                const p = mapToItem(root, mx, my);
                                ctxMenu.popup(p.x, p.y, root.menuForFile(fileModelData));
                            }
                            onSelectToggled: root.toggleSelect(fileModelData.filePath)
                        }

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: gridDisplayRegion.width
                                height: gridDisplayRegion.height
                                radius: wallpaperGridBackground.radius
                            }
                        }
                    }

                    Toolbar {
                        id: extraOptions
                        anchors {
                            bottom: parent.bottom
                            horizontalCenter: parent.horizontalCenter
                            bottomMargin: 8
                        }

                        IconToolbarButton {
                            implicitWidth: height
                            onClicked: {
                                Wallpapers.openFallbackPicker(root.useDarkMode);
                                GlobalStates.wallpaperSelectorOpen = false;
                            }
                            altAction: () => {
                                Wallpapers.openFallbackPicker(root.useDarkMode);
                                GlobalStates.wallpaperSelectorOpen = false;
                                Config.options.wallpaperSelector.useSystemFileDialog = true
                            }
                            text: "open_in_new"
                            StyledToolTip {
                                text: Translation.tr("Use the system file picker instead\nRight-click to make this the default behavior")
                            }
                        }

                        IconToolbarButton {
                            implicitWidth: height
                            onClicked: {
                                Wallpapers.randomFromCurrentFolder();
                            }
                            text: "ifl"
                            StyledToolTip {
                                text: Translation.tr("Pick random from this folder")
                            }
                        }

                        IconToolbarButton {
                            implicitWidth: height
                            onClicked: root.useDarkMode = !root.useDarkMode
                            text: root.useDarkMode ? "dark_mode" : "light_mode"
                            StyledToolTip {
                                text: Translation.tr("Click to toggle light/dark mode\n(applied when wallpaper is chosen)")
                            }
                        }

                        // ── Type filter (ALL / PIC / VID) ─────────────────
                        // Single icon button that cycles through the three
                        // states on click. Picks the right glyph and shows
                        // the current state in the tooltip.
                        IconToolbarButton {
                            implicitWidth: height
                            text: root.typeFilter === "pic" ? "image"
                                : root.typeFilter === "vid" ? "movie"
                                : "filter_alt"
                            onClicked: {
                                root.typeFilter = root.typeFilter === "all" ? "pic"
                                                : root.typeFilter === "pic" ? "vid"
                                                : "all"
                            }
                            StyledToolTip {
                                text: Translation.tr("Type filter: %1\nClick to cycle ALL → Pictures → Videos")
                                    .arg(root.typeFilter === "pic" ? Translation.tr("Pictures only")
                                       : root.typeFilter === "vid" ? Translation.tr("Videos only")
                                       : Translation.tr("All media"))
                            }
                        }

                        // ── Sort order (cycles 6 modes) ───────────────────
                        // Same pattern as type filter — cycle on click,
                        // current mode in the tooltip + glyph.
                        IconToolbarButton {
                            implicitWidth: height
                            text: root.sortMode === "newest"   ? "sort"
                                : root.sortMode === "oldest"   ? "history"
                                : root.sortMode === "az"       ? "sort_by_alpha"
                                : root.sortMode === "za"       ? "abc"
                                : root.sortMode === "largest"  ? "vertical_align_top"
                                :                                "vertical_align_bottom"
                            onClicked: {
                                const seq = ["newest", "oldest", "az", "za", "largest", "smallest"]
                                const i = seq.indexOf(root.sortMode)
                                root.sortMode = seq[(i + 1) % seq.length]
                            }
                            StyledToolTip {
                                text: {
                                    const label = {
                                        newest:   Translation.tr("Newest first"),
                                        oldest:   Translation.tr("Oldest first"),
                                        az:       Translation.tr("Name A → Z"),
                                        za:       Translation.tr("Name Z → A"),
                                        largest:  Translation.tr("Largest first"),
                                        smallest: Translation.tr("Smallest first"),
                                    }[root.sortMode] || ""
                                    return Translation.tr("Sort: %1\nClick to cycle").arg(label)
                                }
                            }
                        }

                        ToolbarTextField {
                            id: filterField
                            placeholderText: focus ? Translation.tr("Search wallpapers") : Translation.tr("Hit \"/\" to search")

                            // Style
                            clip: true
                            font.pixelSize: Appearance.font.pixelSize.small

                            // Search
                            onTextChanged: {
                                Wallpapers.searchQuery = text;
                            }

                            Keys.onPressed: event => {
                                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) { // Intercept Ctrl+V to handle "paste to go to" in pickers
                                    root.handleFilePasting(event);
                                    return;
                                }
                                else if (text.length !== 0) {
                                    // No filtering, just navigate grid
                                    if (event.key === Qt.Key_Down) {
                                        grid.moveSelection(grid.columns);
                                        event.accepted = true;
                                        return;
                                    }
                                    if (event.key === Qt.Key_Up) {
                                        grid.moveSelection(-grid.columns);
                                        event.accepted = true;
                                        return;
                                    }
                                }
                                event.accepted = false;
                            }
                        }

                        IconToolbarButton {
                            implicitWidth: height
                            onClicked: {
                                GlobalStates.wallpaperSelectorOpen = false;
                            }
                            text: "close"
                            StyledToolTip {
                                text: Translation.tr("Cancel wallpaper selection")
                            }
                        }
                    }
                }
            }
        }

        // Right-click context menu — overlays the whole picker.
        PopupContextMenu { id: ctxMenu }
    }

}
