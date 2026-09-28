pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

/**
 * Display settings panel — brightness, colour temperature, live colour grading
 * (saturation / contrast / gain / gamma / invert) and per-monitor mode control.
 *
 * Colour grading is done with a Hyprland screen shader: the values are baked
 * into a GLSL file which is then applied with
 * `hyprctl keyword decoration:screen_shader`. When every grading value is
 * neutral the shader is cleared entirely (`[[EMPTY]]`) so there is no GPU cost
 * for a no-op pass — that matters on battery.
 *
 * Mode/scale/VRR changes are deliberately NOT live: they apply on an explicit
 * button, because a bad `monitor` keyword can leave you staring at a black
 * screen mid-drag.
 */
Scope {
    id: root

    // ── Colour grading state ────────────────────────────────────────────
    property real saturation: 1.0
    property real contrast: 1.0
    property real gain: 1.0
    property real gamma: 1.0
    property bool invert: false
    property bool grayscale: false

    readonly property bool gradingNeutral: saturation === 1.0 && contrast === 1.0
        && gain === 1.0 && gamma === 1.0 && !invert && !grayscale

    // Effective saturation: the grayscale switch just pins it to 0.
    readonly property real effSaturation: grayscale ? 0.0 : saturation

    function resetGrading() {
        root.saturation = 1.0;
        root.contrast = 1.0;
        root.gain = 1.0;
        root.gamma = 1.0;
        root.invert = false;
        root.grayscale = false;
        root.applyGrading();
    }

    function applyGrading() {
        // The service owns generation and persistence: it keeps these six
        // values, writes the .frag and applies it. That is what lets the
        // grading come back after a reboot, when /dev/shm has been emptied and
        // this panel has not been instantiated at all.
        AppDisplay.setBaseGrading({
            saturation: root.saturation, contrast: root.contrast,
            gain: root.gain, gamma: root.gamma,
            invert: root.invert, grayscale: root.grayscale,
        });
    }

    // Show what is actually on screen, rather than neutral sliders over a
    // graded display.
    function adoptSavedGrading() {
        const g = AppDisplay.baseGrading;
        if (!g) return;
        root.saturation = g.saturation ?? 1.0;
        root.contrast = g.contrast ?? 1.0;
        root.gain = g.gain ?? 1.0;
        root.gamma = g.gamma ?? 1.0;
        root.invert = g.invert === true;
        root.grayscale = g.grayscale === true;
    }
    Component.onCompleted: root.adoptSavedGrading()

    // Values typed into the launcher (`/display --saturation=1.4`) land here.
    // The panel remains the owner; this just copies them in and re-grades.
    Connections {
        target: GlobalStates
        function onDisplayGradingChanged() {
            const g = GlobalStates.displayGrading ?? {};
            if (g.saturation !== undefined) root.saturation = g.saturation;
            if (g.contrast !== undefined) root.contrast = g.contrast;
            if (g.gain !== undefined) root.gain = g.gain;
            if (g.gamma !== undefined) root.gamma = g.gamma;
            if (g.invert !== undefined) root.invert = g.invert;
            if (g.grayscale !== undefined) root.grayscale = g.grayscale;
            root.scheduleGrading();
        }
    }

    // Coalesce slider drags into one shader rebuild.
    Timer {
        id: gradingDebounce
        interval: 110
        repeat: false
        onTriggered: {
            root.applyGrading();
            root.scheduleHistory("Colour grading");
        }
    }
    function scheduleGrading() { gradingDebounce.restart(); }

    // ── Shader effects (whole-screen GLSL) ──────────────────────────────
    // Presets are real .frag files, so built-ins and your own shaders share
    // one code path: everything is just "point screen_shader at a file".
    // Note this is mutually exclusive with the colour-grading sliders above —
    // Hyprland supports a single screen shader at a time, so applying an
    // effect takes over and Reset/Clear hands control back to grading.
    readonly property string shaderDir: Quickshell.env("HOME") + "/.config/hypr/shaders"
    readonly property string folderStore: Quickshell.env("HOME") + "/.local/state/quickshell/user/shaderFolders.json"
    property var extraDirs: []
    property var shaderFiles: []
    property string activeShader: ""
    property bool shaderBrowserOpen: false
    property bool monitorPopupOpen: false

    // Which display the monitor popup edits. Empty means "whichever is
    // focused" — resolved lazily so unplugging the selected monitor degrades
    // to a sensible default instead of leaving the popup bound to nothing.
    property string selectedMonitor: ""

    function openMonitorPopup(name) {
        root.selectedMonitor = name ?? "";
        root.monitorPopupOpen = true;
    }

    // When non-empty, the shader browser is picking a shader FOR THIS APP
    // (an AppDisplay profile) instead of setting the global effect.
    property string browserTarget: ""

    // ── Per-app popups ──────────────────────────────────────────────────
    // Two stacked layers: the strip at the top of the panel opens the app
    // LIST, and picking an app there opens that app's settings on top of it.
    property bool appListOpen: false
    // Effects browser: which app we're picking an animated effect for.
    property string effectTarget: ""
    readonly property bool effectBrowserOpen: root.effectTarget.length > 0
    readonly property int profileCount: Object.keys(AppDisplay.profiles).length

    property string appPopupId: ""
    readonly property bool appPopupOpen: root.appPopupId.length > 0

    function openAppPopup(appId) {
        // Materialise a profile on first open so every control has something
        // concrete to bind to and edit.
        if (!AppDisplay.has(appId))
            AppDisplay.setProfile(appId, AppDisplay.defaults);
        root.appPopupId = appId;
    }

    // One-line description of a profile for the app list.
    function profileSummary(appId) {
        if (!AppDisplay.has(appId))
            return "no profile";
        const p = AppDisplay.get(appId);
        const when = p.trigger === "focus" ? "on focus" : "on workspace";
        const bits = [];
        if (p.scope === "window") {
            if (p.dim > 0.001) bits.push(Math.round(p.dim * 100) + "% dim");
            if (p.tintStrength > 0.001) bits.push("tint");
        } else {
            if (p.shader && p.shader.length > 0) bits.push(AppDisplay.shaderName(p.shader));
            else if (!AppDisplay.isNeutral(p)) bits.push("graded");
        }
        return (bits.length > 0 ? bits.join(", ") + " · " : "") + when;
    }

    function openBrowser(appId) {
        root.browserTarget = appId ?? "";
        root.rescanShaders();
        root.shaderBrowserOpen = true;
    }

    // What the browser should highlight / write to, given its current mode.
    readonly property string browserSelection: root.browserTarget.length > 0
        ? AppDisplay.get(root.browserTarget).shader : root.activeShader

    function browserPick(path) {
        if (root.browserTarget.length > 0)
            AppDisplay.update(root.browserTarget, "shader", path);
        else if (path.length === 0)
            root.clearShader();
        else
            root.applyShaderFile(path);
        root.shaderBrowserOpen = false;
    }

    // Apps offered for a rule: everything currently open, plus every app that
    // already has a rule (so a rule stays editable after you close the app).
    readonly property var appList: {
        const seen = ({});
        const out = [];
        const tls = ToplevelManager.toplevels?.values ?? [];
        for (let i = 0; i < tls.length; ++i) {
            const id = tls[i]?.appId ?? "";
            if (id.length === 0 || seen[id]) continue;
            seen[id] = true;
            out.push(id);
        }
        for (const k in AppDisplay.profiles) {
            if (!seen[k]) { seen[k] = true; out.push(k); }
        }
        return out.sort();
    }

    // Shaders grouped by the folder they came from, so the browser can show
    // each source as its own container instead of one undifferentiated list.
    readonly property var shaderGroups: {
        const g = ({});
        for (let i = 0; i < root.shaderFiles.length; ++i) {
            const path = String(root.shaderFiles[i]);
            const parts = path.split("/");
            const dir = parts.length > 1 ? parts[parts.length - 2] : "shaders";
            if (!g[dir]) g[dir] = [];
            g[dir].push(path);
        }
        return Object.keys(g).sort().map(k => ({ name: k, items: g[k] }));
    }

    // Picking an animated effect only makes sense on a window-scope profile,
    // so choosing one also switches the profile to window scope rather than
    // silently saving something that can never run.
    function browserPickEffect(path) {
        if (root.browserTarget.length === 0) return;
        AppDisplay.update(root.browserTarget, "scope", "window");
        AppDisplay.update(root.browserTarget, "effect", path);
        root.shaderBrowserOpen = false;
    }

    function shaderName(path) {
        const base = String(path).split("/").pop();
        return base.replace(/\.(frag|glsl)$/, "");
    }

    function rescanShaders() {
        const dirs = [root.shaderDir].concat(root.extraDirs);
        scanProc.command = ["bash", "-c",
            "find " + dirs.map(d => "'" + d + "'").join(" ")
            + " -maxdepth 2 \\( -name '*.frag' -o -name '*.glsl' \\) 2>/dev/null | sort -u"];
        scanProc.running = true;
    }

    function applyShaderFile(path) {
        root.activeShader = path;
        AppDisplay.setBase(path, false);
        root.pushHistory("Effect: " + root.shaderName(path));
    }

    function clearShader() {
        root.activeShader = "";
        // Hand control back to the grading sliders (which re-apply or clear).
        root.applyGrading();
        root.pushHistory("Effect cleared");
    }

    Process {
        id: scanProc
        stdout: StdioCollector {
            onStreamFinished: root.shaderFiles =
                text.trim().length > 0 ? text.trim().split("\n") : []
        }
    }

    // zenity file / folder pickers
    Process {
        id: filePicker
        command: ["zenity", "--file-selection", "--title=Choose a shader (.frag/.glsl)"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (p.length > 0) root.applyShaderFile(p);
            }
        }
    }
    Process {
        id: packFolderPicker
        command: ["zenity", "--file-selection", "--directory", "--title=Add an effect pack folder"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (p.length > 0) AppDisplay.addPackFolder(p);
            }
        }
    }
    Process {
        id: folderPicker
        command: ["zenity", "--file-selection", "--directory", "--title=Add a shader folder"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (p.length === 0 || root.extraDirs.indexOf(p) !== -1) return;
                root.extraDirs = [...root.extraDirs, p];
                foldersFile.setText(JSON.stringify(root.extraDirs));
                root.rescanShaders();
            }
        }
    }

    FileView {
        id: foldersFile
        path: Qt.resolvedUrl(root.folderStore)
        onLoaded: {
            try { root.extraDirs = JSON.parse(foldersFile.text() || "[]"); } catch (e) { root.extraDirs = []; }
            root.rescanShaders();
        }
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) foldersFile.setText("[]");
            root.rescanShaders();
        }
    }

    // ── Change history ──────────────────────────────────────────────────
    // Every applied change snapshots the full display state, so you can see
    // what you did and jump back to any earlier configuration.
    readonly property string historyStore:
        Quickshell.env("HOME") + "/.local/state/quickshell/user/displayHistory.json"
    property var history: []
    readonly property int historyLimit: 25
    // Set while restoring so re-applying doesn't record a fresh entry.
    property bool restoring: false

    function currentState() {
        const m = HyprlandData.monitors && HyprlandData.monitors.length > 0
            ? HyprlandData.monitors[0] : null;
        return {
            saturation: root.saturation,
            contrast: root.contrast,
            gain: root.gain,
            gamma: root.gamma,
            invert: root.invert,
            grayscale: root.grayscale,
            colorTemp: root.colorTemp,
            shader: root.activeShader,
            monName: m ? m.name : "",
            monMode: m ? (m.width + "x" + m.height + "@" + m.refreshRate.toFixed(2)) : "",
            monScale: m ? m.scale : 1
        };
    }

    function pushHistory(label) {
        if (root.restoring)
            return;
        const st = root.currentState();
        // Ignore no-ops so dragging a slider back to where it was doesn't
        // fill the list with identical entries.
        if (root.history.length > 0
            && JSON.stringify(root.history[0].state) === JSON.stringify(st))
            return;
        const entry = { ts: Date.now(), label: label, state: st };
        root.history = [entry].concat(root.history).slice(0, root.historyLimit);
        historyFile.setText(JSON.stringify(root.history));
    }

    function restoreState(st) {
        root.restoring = true;
        root.saturation = st.saturation ?? 1.0;
        root.contrast   = st.contrast   ?? 1.0;
        root.gain       = st.gain       ?? 1.0;
        root.gamma      = st.gamma      ?? 1.0;
        root.invert     = st.invert     ?? false;
        root.grayscale  = st.grayscale  ?? false;
        root.colorTemp  = st.colorTemp  ?? 6500;
        root.applyTemp();
        // A saved effect wins; otherwise re-apply (or clear) the grading.
        if (st.shader && st.shader.length > 0)
            root.applyShaderFile(st.shader);
        else {
            root.activeShader = "";
            root.applyGrading();
        }
        // Not `hyprctl keyword`: under a Lua config Hyprland answers "unknown
        // request" and hyprctl still exits 0, so restoring a monitor looked
        // like it worked and did nothing.
        if (st.monName && st.monMode)
            MonitorManager._runMonitor({
                output: st.monName,
                mode: st.monMode,
                position: "auto",
                scale: Number(st.monScale ?? 1).toFixed(2)
            });
        Qt.callLater(() => root.restoring = false);
    }

    function clearHistory() {
        root.history = [];
        historyFile.setText("[]");
    }

    function agoText(ts) {
        const s = Math.max(0, Math.floor((Date.now() - ts) / 1000));
        if (s < 60)    return s + "s ago";
        if (s < 3600)  return Math.floor(s / 60) + "m ago";
        if (s < 86400) return Math.floor(s / 3600) + "h ago";
        return Math.floor(s / 86400) + "d ago";
    }

    // Coalesce slider drags into a single history entry.
    Timer {
        id: historyDebounce
        interval: 700
        repeat: false
        property string pendingLabel: ""
        onTriggered: root.pushHistory(pendingLabel)
    }
    function scheduleHistory(label) {
        historyDebounce.pendingLabel = label;
        historyDebounce.restart();
    }

    FileView {
        id: historyFile
        path: Qt.resolvedUrl(root.historyStore)
        onLoaded: {
            try { root.history = JSON.parse(historyFile.text() || "[]"); }
            catch (e) { root.history = []; }
        }
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) historyFile.setText("[]");
        }
    }

    // ── Colour temperature (hyprsunset) ─────────────────────────────────
    property int colorTemp: 6500
    function applyTemp() {
        Quickshell.execDetached(["bash", "-c",
            "pidof hyprsunset >/dev/null || hyprsunset --temperature " + root.colorTemp + " & sleep 0.05; "
            + "hyprctl hyprsunset temperature " + root.colorTemp]);
    }
    Timer {
        id: tempDebounce
        interval: 140
        repeat: false
        onTriggered: {
            root.applyTemp();
            root.scheduleHistory("Temperature " + root.colorTemp + "K");
        }
    }

    Loader {
        active: GlobalStates.displayOpen

        sourceComponent: PanelWindow {
            id: win

            onImplicitWidthChanged: PanelStack.register("display", implicitWidth)
            Component.onDestruction: PanelStack.unregister("display")

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:displaySettings"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors.top: true
            anchors.right: true
            margins.top: Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut + 8
            // Side by side rather than stacked on top: the offset is the
            // total width of the panels open to our right.
            margins.right: (Appearance.sizes.hyprlandGapsOut + 8) + PanelStack.offsetFor("display")
            Behavior on margins.right {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            implicitWidth: ScreenFit.panelWidth
            implicitHeight: mainCard.implicitHeight

            mask: Region { item: mainCard }

            Component.onCompleted: {

                PanelStack.register("display", implicitWidth);
                // Re-read the packs whenever the panel opens, so an effect you
                // just dropped into a folder is there without a restart or a
                // refresh button — FolderListModel does not watch directories.
                AppDisplay.rescanEffects();
                root.rescanShaders();
            }

            // The monitor this panel is acting on. Resolution order: the one
            // the user picked, else the focused one, else the first. It used to
            // be monitors[0] unconditionally, which is why every control in the
            // popup edited the internal panel no matter what you clicked.
            readonly property var mon: {
                const list = HyprlandData.monitors ?? [];
                if (list.length === 0) return null;
                if (root.selectedMonitor.length > 0) {
                    const picked = list.find(m => m.name === root.selectedMonitor);
                    if (picked) return picked;   // else fall through: it was unplugged
                }
                return list.find(m => m.focused) ?? list[0];
            }

            // Pending (un-applied) scale from the Advanced slider.
            property real pendingScale: mon?.scale ?? 1.0

            // One place that builds the `monitor` keyword, so the arrangement
            // drag and the Apply button can't drift apart.
            function applyMonitor(name, mode, x, y, scale, vrr) {
                // Was `hyprctl keyword monitor <csv>`, which this Hyprland
                // answers with "unknown request" — so dragging a monitor in the
                // arrangement, or hitting Apply, changed nothing at all while
                // still writing a history entry claiming it had. DisplayProfiles
                // owns the working transport and the type contract.
                DisplayProfiles.set(name, "mode", mode);
                DisplayProfiles.set(name, "position", Math.round(x) + "x" + Math.round(y));
                DisplayProfiles.set(name, "scale", Number(scale).toFixed(2));
                if (vrr !== undefined)
                    DisplayProfiles.set(name, "vrr", vrr ? 1 : 0);
                DisplayProfiles.apply(name);
                // Re-read so the arrangement snaps to the real values, then
                // snapshot once the new geometry is known.
                Qt.callLater(() => {
                    HyprlandData.updateMonitors();
                    root.scheduleHistory("Monitor " + name);
                });
            }

            Rectangle {
                id: mainCard
                width: parent.width
                // Capped by ScreenFit, which is the single place that
                // knows about fractional scaling and reserved strips —
                // this used to be copy-pasted and the copies drifted.
                readonly property real maxHeight: ScreenFit.maxHeight(win)
                // Full available height, not content height: these sit SIDE BY SIDE,
                // and panels of three different heights in a row reads as
                // broken rather than as compact. The flickable below
                // handles panels whose content is shorter.
                implicitHeight: ScreenFit.maxHeight(win)
                radius: Appearance.rounding.large
                // See StackedSettingsPanel: a literal here does not retheme
                // and mismatches every themed child by a hair.
                color: Appearance.colors.colLayer0Base
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                StyledFlickable {
                    id: scroller
                    anchors.fill: parent
                    anchors.margins: 16
                    contentHeight: contentColumn.implicitHeight
                    contentWidth: width
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: contentColumn
                    width: scroller.width
                    spacing: 14

                    // ── Header ──────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialSymbol {
                            text: "display_settings"
                            iconSize: 20
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: "Display"
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.bold: true
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            text: win.mon ? win.mon.name : ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        Rectangle {
                            width: 26; height: 26; radius: 13
                            color: closeHov.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover)
                            Behavior on color { ColorAnimation { duration: 160 } }
                            HoverHandler { margin: Appearance.sizes.touchSlop; id: closeHov }
                            TapHandler { margin: Appearance.sizes.touchSlop; onTapped: GlobalStates.displayOpen = false }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: 16
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    // ── Per-app strip ───────────────────────────────────
                    // Sits above everything: it answers "is something other
                    // than my global settings driving the screen right now?",
                    // which you want to know before you start turning dials.
                    Rectangle {
                        id: perAppStrip
                        readonly property bool live: AppDisplay.enabled
                            && (AppDisplay.governing.length > 0 || AppDisplay.overlays.length > 0)

                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: Appearance.rounding.small
                        color: perAppStrip.live
                            ? Qt.alpha(Appearance.colors.colPrimary, stripHov.hovered ? 0.20 : 0.14)
                            : (stripHov.hovered ? Appearance.colors.colLayer1Hover
                                                : Appearance.colors.colLayer1)
                        Behavior on color { ColorAnimation { duration: 160 } }
                        HoverHandler { id: stripHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.appListOpen = true }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 7

                            MaterialSymbol {
                                text: perAppStrip.live ? "bolt" : "apps"
                                iconSize: 16
                                color: perAppStrip.live ? Appearance.colors.colPrimary
                                                        : Appearance.colors.colSubtext
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    if (!AppDisplay.enabled) return "Per-app display — off";
                                    if (AppDisplay.governing.length > 0)
                                        return AppDisplay.governing + " driving screen";
                                    if (AppDisplay.overlays.length > 0)
                                        return AppDisplay.overlays.length + " app overlay"
                                            + (AppDisplay.overlays.length === 1 ? "" : "s") + " active";
                                    return "Per-app display — no profile active";
                                }
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: perAppStrip.live ? Appearance.colors.colPrimary
                                                        : Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                            Rectangle {
                                visible: root.profileCount > 0
                                implicitHeight: 17
                                implicitWidth: cntText.implicitWidth + 12
                                radius: 8
                                color: Qt.alpha(Appearance.colors.colOnLayer0, 0.10)
                                StyledText {
                                    id: cntText
                                    anchors.centerIn: parent
                                    text: root.profileCount
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            MaterialSymbol {
                                text: "chevron_right"
                                iconSize: 16
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    // ── Monitor arrangement (drag like KDE Plasma) ──────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        MaterialSymbol { text: "monitor"; iconSize: 16; color: Appearance.colors.colSubtext }
                        StyledText {
                            Layout.fillWidth: true
                            text: "Arrangement"
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: true
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            text: (MonitorManager.friendly?.length ?? 0) > 1
                                ? "drag to position · right-click for more" : "right-click for more"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }

                    MonitorArrangement {
                        id: arrangement
                        onRequestApply: (name, mode, x, y, scale) =>
                            win.applyMonitor(name, mode, x, y, scale)
                        onRequestOpen: name => root.openMonitorPopup(name)
                        onRequestMenu: (name, mx, my) => monMenu.openAt(name, mx, my)

                        MonitorContextMenu {
                            id: monMenu
                            anchorItem: arrangement
                            onRequestOpen: name => root.openMonitorPopup(name)
                        }
                    }

                    // Displays that are currently OFF. They have no geometry
                    // to place, so they cannot live in the arrangement above —
                    // but leaving them out entirely is how you end up with a
                    // monitor you switched off and no control to switch back on.
                    Flow {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        spacing: 6
                        visible: repOff.count > 0

                        StyledText {
                            text: Translation.tr("Turned off:")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            anchors.verticalCenter: undefined
                        }

                        Repeater {
                            id: repOff
                            model: (MonitorManager.friendly ?? []).filter(m => m.disabled)
                            delegate: RippleButton {
                                required property var modelData
                                implicitHeight: 26
                                implicitWidth: offRow.implicitWidth + 18
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colLayer2
                                onClicked: MonitorSafety.enable(modelData.name)
                                contentItem: RowLayout {
                                    id: offRow
                                    anchors.centerIn: parent
                                    spacing: 5
                                    MaterialSymbol {
                                        text: "power_settings_new"
                                        iconSize: 14
                                        color: Appearance.colors.colOnLayer2
                                    }
                                    StyledText {
                                        text: modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colOnLayer2
                                    }
                                }
                                StyledToolTip {
                                    text: Translation.tr("Turn %1 back on").arg(modelData.name)
                                }
                            }
                        }
                    }

                    // ── Backlight ───────────────────────────────────────
                    SettingSlider {
                        label: "Screen Brightness"
                        icon: "brightness_6"
                        from: 0.01; to: 1.0
                        value: Brightness.getMonitorForScreen(win.screen)?.brightness ?? 1.0
                        editScale: 100; decimals: 0; unit: "%"
                        onMovedValue: v => Brightness.getMonitorForScreen(win.screen)?.setBrightness(v)
                    }

                    // ── Colour temperature ──────────────────────────────
                    SettingSlider {
                        label: "Colour Temperature"
                        icon: "wb_twilight"
                        from: 2000; to: 6500; stepSize: 100
                        value: root.colorTemp
                        decimals: 0; unit: "K"
                        onMovedValue: v => { root.colorTemp = Math.round(v); tempDebounce.restart(); }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Qt.alpha(Appearance.colors.colOnLayer0, 0.10)
                    }

                    // ── Colour grading (screen shader) ──────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        MaterialSymbol {
                            text: "palette"
                            iconSize: 16
                            color: root.gradingNeutral ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: "Colour Grading"
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: true
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            visible: root.activeShader.length === 0
                            text: root.gradingNeutral ? "off" : "active"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: root.gradingNeutral ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                        }
                        // Hyprland runs ONE screen shader, so an effect and the
                        // grading sliders cannot both be live. Saying so with a
                        // way out beats letting the sliders move and do nothing.
                        Rectangle {
                            visible: root.activeShader.length > 0
                            implicitHeight: 20
                            implicitWidth: takeoverRow.implicitWidth + 14
                            radius: 10
                            color: Qt.alpha(Appearance.colors.colPrimary, ovrHov.hovered ? 0.30 : 0.18)
                            Behavior on color { ColorAnimation { duration: 140 } }
                            HoverHandler { id: ovrHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.clearShader() }
                            RowLayout {
                                id: takeoverRow
                                anchors.centerIn: parent
                                spacing: 4
                                StyledText {
                                    text: root.shaderName(root.activeShader) + " in control"
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colPrimary
                                }
                                MaterialSymbol {
                                    text: "close"; iconSize: 12
                                    color: Appearance.colors.colPrimary
                                }
                            }
                        }
                    }

                    SettingSlider {
                        enabled: root.activeShader.length === 0 && !root.grayscale
                        label: "Saturation"
                        icon: "invert_colors"
                        from: 0.0; to: 2.0
                        value: root.saturation
                        editScale: 100; decimals: 0; unit: "%"
                        onMovedValue: v => { root.saturation = v; root.scheduleGrading(); }
                    }
                    SettingSlider {
                        enabled: root.activeShader.length === 0
                        label: "Contrast"
                        icon: "contrast"
                        from: 0.5; to: 2.0
                        value: root.contrast
                        unit: "×"
                        onMovedValue: v => { root.contrast = v; root.scheduleGrading(); }
                    }
                    SettingSlider {
                        enabled: root.activeShader.length === 0
                        label: "Gain"
                        icon: "exposure"
                        from: 0.3; to: 1.8
                        value: root.gain
                        unit: "×"
                        onMovedValue: v => { root.gain = v; root.scheduleGrading(); }
                    }
                    SettingSlider {
                        enabled: root.activeShader.length === 0
                        label: "Gamma"
                        icon: "gradient"
                        from: 0.5; to: 2.4
                        value: root.gamma
                        onMovedValue: v => { root.gamma = v; root.scheduleGrading(); }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        SettingSwitch {
                            label: "Grayscale"
                            checked: root.grayscale
                            onToggled: c => { root.grayscale = c; root.applyGrading(); }
                        }
                        SettingSwitch {
                            label: "Invert"
                            checked: root.invert
                            onToggled: c => { root.invert = c; root.applyGrading(); }
                        }
                        Item { Layout.fillWidth: true }
                        RippleButton {
                            implicitWidth: 76
                            implicitHeight: 30
                            colBackground: Appearance.colors.colLayer1
                            contentItem: RowLayout {
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol { text: "restart_alt"; iconSize: 14; color: Appearance.colors.colOnLayer1 }
                                StyledText { text: "Reset"; font.pixelSize: 11; color: Appearance.colors.colOnLayer1 }
                            }
                            onClicked: root.resetGrading()
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Qt.alpha(Appearance.colors.colOnLayer0, 0.10)
                    }

                    // ── Shader effects ──────────────────────────────────
                    Expander {
                        title: "Shader Effects"
                        icon: "auto_awesome"

                        StyledText {
                            Layout.fillWidth: true
                            text: root.activeShader.length > 0
                                ? "Active: " + root.shaderName(root.activeShader)
                                : "No effect — colour grading is in control"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: root.activeShader.length > 0
                                ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            elide: Text.ElideMiddle
                        }

                        // Quick chips for the first handful of shaders
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: root.shaderFiles.slice(0, 8)
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool sel: modelData === root.activeShader
                                    implicitHeight: 28
                                    implicitWidth: chipLabel.implicitWidth + 20
                                    radius: height / 2
                                    color: sel ? Appearance.colors.colPrimary
                                        : (shaderChipHov.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1)
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    HoverHandler { id: shaderChipHov }
                                    TapHandler {
                                        onTapped: sel ? root.clearShader() : root.applyShaderFile(modelData)
                                    }
                                    StyledText {
                                        id: chipLabel
                                        anchors.centerIn: parent
                                        text: root.shaderName(modelData)
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: sel ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            PanelActionButton {
                                Layout.fillWidth: true
                                iconName: "folder_open"
                                buttonLabel: "Browse…"
                                onClicked: root.openBrowser("")
                            }
                            RippleButton {
                                implicitWidth: 86
                                implicitHeight: 32
                                enabled: root.activeShader.length > 0
                                opacity: enabled ? 1 : 0.45
                                colBackground: Appearance.colors.colLayer1
                                contentItem: RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol { text: "close"; iconSize: 14; color: Appearance.colors.colOnLayer1 }
                                    StyledText { text: "Clear"; font.pixelSize: 11; color: Appearance.colors.colOnLayer1 }
                                }
                                onClicked: root.clearShader()
                            }
                        }
                    }

                }
                }
                // ── Monitor popup (opened by tapping the arrangement) ────
                Rectangle {
                    id: monitorDim
                    anchors.fill: parent
                    radius: mainCard.radius
                    color: "#D0000000"
                    z: 290
                    visible: opacity > 0.01
                    opacity: root.monitorPopupOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.monitorPopupOpen = false
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 28
                        implicitHeight: Math.min(parent.height - 40, monitorCol.implicitHeight + 26)
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colLayer0
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        transformOrigin: Item.Center
                        scale: root.monitorPopupOpen ? 1.0 : 0.94
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        MouseArea { anchors.fill: parent }   // block click-through
                        clip: true

                        StyledFlickable {
                            anchors.fill: parent
                            anchors.margins: 13
                            contentHeight: monitorCol.implicitHeight
                            contentWidth: width
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: monitorCol
                            width: parent.width
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 7
                                MaterialSymbol { text: "monitor"; iconSize: 17; color: Appearance.colors.colPrimary }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: win.mon ? win.mon.name : "Monitor"
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.bold: true
                                    color: Appearance.colors.colOnLayer0
                                }
                                Rectangle {
                                    width: 26; height: 26; radius: 13
                                    color: mpcHov.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    HoverHandler { margin: Appearance.sizes.touchSlop; id: mpcHov }
                                    TapHandler { margin: Appearance.sizes.touchSlop; onTapped: root.monitorPopupOpen = false }
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "close"; iconSize: 15
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }

                        // ── Deep settings (collapsed by default) ────────────
                        Expander {
                            id: advanced
                            title: "Advanced display settings"
                            icon: "tune"

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Resolution & refresh"
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    text: win.mon
                                        ? win.mon.width + "×" + win.mon.height + " @ " + Math.round(win.mon.refreshRate) + "Hz"
                                        : ""
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                            }

                            StyledComboBox {
                                id: modeBox
                                Layout.fillWidth: true
                                model: win.mon?.availableModes ?? []
                                currentIndex: 0
                            }

                            SettingSlider {
                                label: "Scale"
                                icon: "zoom_in"
                                from: 1.0; to: 2.0; stepSize: 0.05
                                value: win.mon?.scale ?? 1.0
                                unit: "×"
                                // Applied with the button, not live — a bad mode/scale
                                // mid-drag can black out the screen.
                                onMovedValue: v => win.pendingScale = v
                            }

                            // ── Rotation ────────────────────────────────────
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Rotation"
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                                StyledComboBox {
                                    id: rotBox
                                    implicitWidth: 132
                                    // Index IS the Hyprland transform value for
                                    // 0/90/180/270; the flipped transforms (4-7)
                                    // are deliberately not offered — they are a
                                    // projector fix, not a desktop setting, and
                                    // an accidental mirror is hard to undo when
                                    // you cannot read the screen.
                                    model: ["Landscape", "Portrait 90°", "Landscape 180°", "Portrait 270°"]
                                    currentIndex: Math.min(3, win.mon?.transform ?? 0)
                                }
                            }

                            // ── Colour ──────────────────────────────────────
                            SettingSwitch {
                                id: depthSwitch
                                label: "10-bit colour"
                                // currentFormat reads XRGB2101010 for 10-bit.
                                checked: String(win.mon?.currentFormat ?? "").indexOf("2101010") >= 0
                            }

                            SettingSlider {
                                id: sdrBrightSlider
                                label: "SDR brightness"
                                icon: "brightness_medium"
                                from: 0.5; to: 2.0; stepSize: 0.01
                                value: Number(win.mon?.sdrBrightness ?? 1.0)
                                unit: "×"
                            }

                            SettingSlider {
                                id: sdrSatSlider
                                label: "SDR saturation"
                                icon: "palette"
                                from: 0.0; to: 2.0; stepSize: 0.01
                                value: Number(win.mon?.sdrSaturation ?? 1.0)
                                unit: "×"
                            }

                            // Saturation/contrast/gain further up this panel are
                            // a screen shader, and Hyprland's screen_shader is a
                            // single global — it cannot differ per display. The
                            // two sliders above are the compositor's own
                            // per-monitor controls, so they are the ones that can.
                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: "These apply to this display only. The grading sliders in the main panel are a screen shader, which Hyprland applies globally."
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                SettingSwitch {
                                    id: vrrSwitch
                                    label: "VRR"
                                    checked: (win.mon?.vrr ?? false)
                                }
                                Item { Layout.fillWidth: true }
                                RippleButton {
                                    implicitWidth: 96
                                    implicitHeight: 32
                                    colBackground: Appearance.colors.colPrimary
                                    contentItem: RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        MaterialSymbol { text: "check"; iconSize: 15; color: Appearance.colors.colOnPrimary }
                                        StyledText { text: "Apply"; font.pixelSize: 11; font.bold: true; color: Appearance.colors.colOnPrimary }
                                    }
                                    onClicked: {
                                        if (!win.mon) return;
                                        const m = win.mon;
                                        const mode = (modeBox.currentIndex >= 0 && (modeBox.model?.length ?? 0) > 0)
                                            ? modeBox.model[modeBox.currentIndex]
                                            : (m.width + "x" + m.height + "@" + m.refreshRate.toFixed(2));
                                        // Everything the popup owns, written to
                                        // this monitor's profile and applied in
                                        // ONE call — separate calls per axis make
                                        // the display remode several times over.
                                        DisplayProfiles.set(m.name, "mode", mode);
                                        DisplayProfiles.set(m.name, "position", Math.round(m.x) + "x" + Math.round(m.y));
                                        DisplayProfiles.set(m.name, "scale", Number(win.pendingScale).toFixed(2));
                                        DisplayProfiles.set(m.name, "vrr", vrrSwitch.checked ? 1 : 0);
                                        DisplayProfiles.set(m.name, "transform", rotBox.currentIndex);
                                        DisplayProfiles.set(m.name, "bitdepth", depthSwitch.checked ? 10 : 8);
                                        DisplayProfiles.set(m.name, "sdrbrightness", Number(sdrBrightSlider.value).toFixed(2));
                                        DisplayProfiles.set(m.name, "sdrsaturation", Number(sdrSatSlider.value).toFixed(2));
                                        DisplayProfiles.apply(m.name);
                                        root.scheduleHistory("Monitor " + m.name);
                                    }
                                }
                            }

                            // ── Profile actions ─────────────────────────────
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 6
                                StyledText {
                                    Layout.fillWidth: true
                                    text: {
                                        const n = DisplayProfiles.overrideCount(win.mon?.name ?? "");
                                        return n === 0 ? "No overrides saved"
                                                       : n + (n === 1 ? " override saved" : " overrides saved");
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                                RippleButton {
                                    implicitWidth: 74
                                    implicitHeight: 28
                                    // Only meaningful with somewhere to copy TO.
                                    visible: (HyprlandData.monitors?.length ?? 0) > 1
                                    contentItem: StyledText {
                                        anchors.centerIn: parent
                                        text: "Copy to other"
                                        font.pixelSize: 10
                                        color: Appearance.colors.colOnLayer2
                                    }
                                    onClicked: {
                                        const others = (HyprlandData.monitors ?? [])
                                            .filter(m => m.name !== win.mon?.name);
                                        for (const o of others) {
                                            DisplayProfiles.copyTo(win.mon.name, o.name);
                                            DisplayProfiles.apply(o.name);
                                        }
                                    }
                                }
                                RippleButton {
                                    implicitWidth: 56
                                    implicitHeight: 28
                                    contentItem: StyledText {
                                        anchors.centerIn: parent
                                        text: "Reset"
                                        font.pixelSize: 10
                                        color: Appearance.m3colors.m3error
                                    }
                                    // Forgets the overrides. It cannot put the
                                    // display back — Hyprland has no undo — so
                                    // the label says Reset, not Revert.
                                    onClicked: DisplayProfiles.clear(win.mon?.name ?? "")
                                }
                            }
                        }

                        // ── History ─────────────────────────────────────────
                        Expander {
                            title: "History"
                            icon: "history"

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.history.length > 0
                                        ? root.history.length + " saved configuration"
                                          + (root.history.length === 1 ? "" : "s")
                                        : "No changes recorded yet"
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                                RippleButton {
                                    implicitWidth: 66
                                    implicitHeight: 26
                                    enabled: root.history.length > 0
                                    opacity: enabled ? 1 : 0.45
                                    colBackground: Appearance.colors.colLayer1
                                    contentItem: StyledText {
                                        anchors.centerIn: parent
                                        text: "Clear"
                                        font.pixelSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    onClicked: root.clearHistory()
                                }
                            }

                            // Newest first; tap an entry to restore that state.
                            Repeater {
                                model: root.history.slice(0, 12)
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    implicitHeight: 38
                                    radius: Appearance.rounding.small
                                    color: hHov.hovered ? Appearance.colors.colLayer1Hover
                                        : (index === 0 ? Qt.alpha(Appearance.colors.colPrimary, 0.10) : ColorUtils.transparentize(Qt.alpha(Appearance.colors.colPrimary, 0.10)))
                                    Behavior on color { ColorAnimation { duration: 130 } }
                                    HoverHandler { id: hHov }
                                    TapHandler { onTapped: root.restoreState(modelData.state) }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8
                                        MaterialSymbol {
                                            text: index === 0 ? "radio_button_checked" : "restore"
                                            iconSize: 15
                                            color: index === 0 ? Appearance.colors.colPrimary
                                                               : Appearance.colors.colSubtext
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: -3
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: modelData.label ?? "Change"
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colOnLayer0
                                                elide: Text.ElideRight
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: {
                                                    const s = modelData.state ?? {};
                                                    const bits = [];
                                                    if (s.shader && s.shader.length > 0)
                                                        bits.push(root.shaderName(s.shader));
                                                    else if (s.saturation !== undefined)
                                                        bits.push("sat " + Math.round(s.saturation * 100) + "%");
                                                    if (s.colorTemp !== undefined) bits.push(s.colorTemp + "K");
                                                    if (s.monScale !== undefined) bits.push(Number(s.monScale).toFixed(2) + "×");
                                                    return bits.join(" · ");
                                                }
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colSubtext
                                                elide: Text.ElideRight
                                            }
                                        }
                                        StyledText {
                                            text: index === 0 ? "current" : root.agoText(modelData.ts ?? 0)
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: index === 0 ? Appearance.colors.colPrimary
                                                               : Appearance.colors.colSubtext
                                        }
                                    }
                                }
                            }
                        }
                        }
                        }
                    }
                }


                // ── Per-app list popup (opened by the top strip) ─────────
                Rectangle {
                    id: appListDim
                    anchors.fill: parent
                    radius: mainCard.radius
                    color: "#D0000000"
                    z: 292
                    visible: opacity > 0.01
                    opacity: root.appListOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    MouseArea { anchors.fill: parent; onClicked: root.appListOpen = false }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 24
                        implicitHeight: Math.min(parent.height - 40, listCol.implicitHeight + 26)
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colLayer0
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        transformOrigin: Item.Center
                        scale: root.appListOpen ? 1.0 : 0.94
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        MouseArea { anchors.fill: parent }   // block click-through

                        StyledFlickable {
                            id: listFlick
                            anchors.fill: parent
                            anchors.margins: 13
                            contentHeight: listCol.implicitHeight
                            clip: true

                            ColumnLayout {
                                id: listCol
                                width: listFlick.width
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 7
                                    MaterialSymbol { text: "apps"; iconSize: 17; color: Appearance.colors.colPrimary }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "Per-App Display"
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.bold: true
                                        color: Appearance.colors.colOnLayer0
                                    }
                                    Rectangle {
                                        width: 26; height: 26; radius: 13
                                        color: alcHov.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover)
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        HoverHandler { margin: Appearance.sizes.touchSlop; id: alcHov; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { margin: Appearance.sizes.touchSlop; onTapped: root.appListOpen = false }
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "close"; iconSize: 15
                                            color: Appearance.colors.colSubtext
                                        }
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Give an app its own look. Tap one to configure."
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                    wrapMode: Text.WordWrap
                                }

                                SettingSwitch {
                                    label: "Enable per-app display"
                                    checked: AppDisplay.enabled
                                    onToggled: c => AppDisplay.enabled = c
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 1
                                    color: Qt.alpha(Appearance.colors.colOnLayer0, 0.10)
                                }

                                Repeater {
                                    model: ScriptModel { values: root.appList }
                                    delegate: Rectangle {
                                        id: appRow
                                        required property var modelData
                                        readonly property string appId: String(modelData)
                                        readonly property bool hasProfile: AppDisplay.has(appRow.appId)
                                        readonly property var prof: AppDisplay.get(appRow.appId)
                                        readonly property bool live: AppDisplay.enabled && appRow.hasProfile
                                            && AppDisplay.triggerMatches(appRow.appId)

                                        Layout.fillWidth: true
                                        implicitHeight: 46
                                        radius: Appearance.rounding.small
                                        opacity: AppDisplay.enabled ? 1.0 : 0.55
                                        color: appHov.hovered ? Appearance.colors.colLayer1Hover
                                                              : Appearance.colors.colLayer1
                                        Behavior on color { ColorAnimation { duration: 130 } }
                                        HoverHandler { id: appHov; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: root.openAppPopup(appRow.appId) }

                                        // Left accent bar, lit while this profile is live.
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 3
                                            height: appRow.live ? parent.height - 14 : 0
                                            radius: 2
                                            color: Appearance.colors.colPrimary
                                            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 11
                                            anchors.rightMargin: 8
                                            spacing: 9

                                            IconImage {
                                                implicitSize: 24
                                                source: Quickshell.iconPath(
                                                    AppSearch.guessIcon(appRow.appId), "image-missing")
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: -2
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: appRow.appId
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    color: Appearance.colors.colOnLayer1
                                                    elide: Text.ElideRight
                                                }
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: root.profileSummary(appRow.appId)
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: appRow.hasProfile
                                                        ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            Rectangle {
                                                visible: appRow.hasProfile
                                                implicitHeight: 18
                                                implicitWidth: badgeText.implicitWidth + 14
                                                radius: 9
                                                color: Qt.alpha(Appearance.colors.colPrimary, 0.16)
                                                StyledText {
                                                    id: badgeText
                                                    anchors.centerIn: parent
                                                    text: appRow.prof.scope === "window" ? "window" : "screen"
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: Appearance.colors.colPrimary
                                                }
                                            }
                                            MaterialSymbol {
                                                text: "chevron_right"
                                                iconSize: 16
                                                color: Appearance.colors.colSubtext
                                            }
                                        }
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: root.appList.length === 0
                                    text: "No open windows to configure."
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }
                    }
                }

                // ── Effects browser (packs = folders of effects) ─────────
                Rectangle {
                    id: fxDim
                    anchors.fill: parent
                    radius: mainCard.radius
                    color: "#D0000000"
                    z: 298
                    visible: opacity > 0.01
                    opacity: root.effectBrowserOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    MouseArea { anchors.fill: parent; onClicked: root.effectTarget = "" }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 24
                        implicitHeight: Math.min(parent.height - 40, fxCol.implicitHeight + 26)
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colLayer0
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        transformOrigin: Item.Center
                        scale: root.effectBrowserOpen ? 1.0 : 0.94
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        MouseArea { anchors.fill: parent }

                        StyledFlickable {
                            id: fxFlick
                            anchors.fill: parent
                            anchors.margins: 13
                            contentHeight: fxCol.implicitHeight
                            clip: true

                            ColumnLayout {
                                id: fxCol
                                width: fxFlick.width
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 7
                                    MaterialSymbol { text: "animation"; iconSize: 17; color: Appearance.colors.colPrimary }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "Effects"
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.bold: true
                                        color: Appearance.colors.colOnLayer0
                                    }
                                    Rectangle {
                                        width: 26; height: 26; radius: 13
                                        color: fxcHov.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover)
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        HoverHandler { margin: Appearance.sizes.touchSlop; id: fxcHov; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { margin: Appearance.sizes.touchSlop; onTapped: root.effectTarget = "" }
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "close"; iconSize: 15
                                            color: Appearance.colors.colSubtext
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    SettingSwitch {
                                        label: "Live previews"
                                        checked: AppDisplay.livePreview
                                        onToggled: c => AppDisplay.livePreview = c
                                    }
                                    Item { Layout.fillWidth: true }
                                    StyledText {
                                        visible: AppDisplay.livePreview
                                        text: "costs GPU"
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Animated, and drawn only over " + root.effectTarget + "."
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                    wrapMode: Text.WordWrap
                                    elide: Text.ElideRight
                                }

                                // "None" clears the effect.
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 34
                                    radius: Appearance.rounding.small
                                    readonly property bool sel: root.effectTarget.length > 0
                                        && AppDisplay.get(root.effectTarget).effect === ""
                                    color: sel ? Appearance.colors.colSecondaryContainer
                                        : (noneHov.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover))
                                    Behavior on color { ColorAnimation { duration: 130 } }
                                    HoverHandler { id: noneHov; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        onTapped: {
                                            AppDisplay.update(root.effectTarget, "effect", "");
                                            root.effectTarget = "";
                                        }
                                    }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        spacing: 8
                                        MaterialSymbol { text: "block"; iconSize: 15; color: Appearance.colors.colSubtext }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: "None"
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colOnLayer0
                                        }
                                    }
                                }

                                // One group per pack folder.
                                Repeater {
                                    model: ScriptModel { values: AppDisplay.packNames }
                                    delegate: ColumnLayout {
                                        id: packGroup
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 4

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.topMargin: 4
                                            spacing: 6
                                            MaterialSymbol { text: "folder"; iconSize: 13; color: Appearance.colors.colSubtext }
                                            StyledText {
                                                text: String(packGroup.modelData)
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.bold: true
                                                color: Appearance.colors.colSubtext
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: 1
                                                color: Qt.alpha(Appearance.colors.colOnLayer0, 0.10)
                                            }
                                        }

                                        Repeater {
                                            model: ScriptModel {
                                                values: AppDisplay.effectsInPack(packGroup.modelData)
                                            }
                                            delegate: Rectangle {
                                                id: fxRow
                                                required property var modelData
                                                readonly property bool sel: root.effectTarget.length > 0
                                                    && AppDisplay.get(root.effectTarget).effect === fxRow.modelData.path
                                                // Right-click reveals this effect's variables.
                                                // Behind a gesture so the list stays scannable
                                                // and applying stays a single left click.
                                                property bool paramsOpen: false
                                                Layout.fillWidth: true
                                                implicitHeight: fxRow.paramsOpen
                                                    ? 44 + fxChips.implicitHeight + 10 : 44
                                                Behavior on implicitHeight {
                                                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                                }
                                                radius: Appearance.rounding.small
                                                color: fxRow.sel ? Appearance.colors.colSecondaryContainer
                                                    : (fxHov.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover))
                                                Behavior on color { ColorAnimation { duration: 130 } }
                                                HoverHandler { id: fxHov; cursorShape: Qt.PointingHandCursor }
                                                TapHandler {
                                                    onTapped: {
                                                        AppDisplay.update(root.effectTarget, "effect", fxRow.modelData.path);
                                                        root.effectTarget = "";
                                                    }
                                                }
                                                TapHandler {
                                                    acceptedButtons: Qt.RightButton
                                                    onTapped: fxRow.paramsOpen = !fxRow.paramsOpen
                                                }
                                                RowLayout {
                                                    // Pinned to the top band, NOT anchors.fill:
                                                    // the row grows when the variable chips open,
                                                    // and a filled header would re-centre itself
                                                    // straight into them.
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    height: 44
                                                    anchors.leftMargin: 10
                                                    anchors.rightMargin: 10
                                                    spacing: 9
                                                    // Colour swatch doubles as the effect's identity.
                                                    // Live thumbnail running the
                                                    // real renderer, so what you
                                                    // see is what you get.
                                                    Rectangle {
                                                        implicitWidth: AppDisplay.livePreview ? 42 : 22
                                                        implicitHeight: AppDisplay.livePreview ? 26 : 22
                                                        radius: AppDisplay.livePreview
                                                            ? Appearance.rounding.verysmall : 11
                                                        clip: true
                                                        color: AppDisplay.livePreview
                                                            ? Appearance.colors.colLayer0
                                                            : Qt.alpha(fxRow.modelData.color, 0.9)
                                                        border.width: 1
                                                        border.color: Qt.alpha(Appearance.colors.colOnLayer0, 0.2)
                                                        Behavior on implicitWidth { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                                                        EffectRenderer {
                                                            anchors.fill: parent
                                                            previewMode: true
                                                            visible: AppDisplay.livePreview
                                                            fx: AppDisplay.livePreview ? fxRow.modelData : null
                                                            rounding: Appearance.rounding.verysmall
                                                        }
                                                        MaterialSymbol {
                                                            anchors.centerIn: parent
                                                            visible: !AppDisplay.livePreview
                                                            text: fxRow.modelData.icon
                                                            iconSize: 12
                                                            color: Appearance.colors.colOnLayer0
                                                        }
                                                    }
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: -2
                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: fxRow.modelData.name
                                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                                            color: Appearance.colors.colOnLayer0
                                                            elide: Text.ElideRight
                                                        }
                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: fxRow.modelData.desc
                                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                                            color: Appearance.colors.colSubtext
                                                            elide: Text.ElideRight
                                                        }
                                                    }
                                                    MaterialSymbol {
                                                        visible: fxRow.sel
                                                        text: "check_circle"; iconSize: 15
                                                        color: Appearance.colors.colPrimary
                                                    }
                                                    MaterialSymbol {
                                                        visible: !fxRow.paramsOpen
                                                        text: "tune"; iconSize: 13
                                                        opacity: fxHov.hovered ? 0.9 : 0.35
                                                        color: Appearance.colors.colSubtext
                                                    }
                                                }

                                                Flow {
                                                    id: fxChips
                                                    visible: fxRow.paramsOpen
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    anchors.topMargin: 46
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 10
                                                    spacing: 5
                                                    Repeater {
                                                        model: ScriptModel {
                                                            values: fxRow.paramsOpen
                                                                ? (fxRow.modelData.params ?? []) : []
                                                        }
                                                        delegate: ParamChip {
                                                            required property var modelData
                                                            appId: root.effectTarget
                                                            effectPath: fxRow.modelData.path
                                                            param: modelData
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: AppDisplay.effects.length === 0 ? 90 : 0
                                    visible: AppDisplay.effects.length === 0
                                    PagePlaceholder {
                                        anchors.centerIn: parent
                                        icon: "animation"
                                        title: "No effect packs found"
                                        shown: AppDisplay.effects.length === 0
                                    }
                                }

                                PanelActionButton {
                                    Layout.fillWidth: true
                                    iconName: "create_new_folder"
                                    buttonLabel: "Add pack folder"
                                    onClicked: packFolderPicker.running = true
                                }
                            }
                        }
                    }
                }

                // ── Per-app popup ────────────────────────────────────────
                Rectangle {
                    id: appDim
                    anchors.fill: parent
                    radius: mainCard.radius
                    color: "#D0000000"
                    z: 295
                    visible: opacity > 0.01
                    opacity: root.appPopupOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    MouseArea { anchors.fill: parent; onClicked: root.appPopupId = "" }

                    Rectangle {
                        id: appCard
                        anchors.centerIn: parent
                        width: parent.width - 24
                        implicitHeight: Math.min(parent.height - 40, appCol.implicitHeight + 26)
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colLayer0
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        transformOrigin: Item.Center
                        scale: root.appPopupOpen ? 1.0 : 0.94
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        MouseArea { anchors.fill: parent }   // block click-through

                        // Snapshot of the profile being edited. Read once per
                        // change so every control below shares one view of it.
                        readonly property string appId: root.appPopupId
                        readonly property var prof: root.appPopupId.length > 0
                            ? AppDisplay.get(root.appPopupId) : AppDisplay.defaults
                        readonly property bool windowScope: prof.scope === "window"

                        StyledFlickable {
                            id: appFlick
                            anchors.fill: parent
                            anchors.margins: 13
                            contentHeight: appCol.implicitHeight
                            clip: true

                            ColumnLayout {
                                id: appCol
                                width: appFlick.width
                                spacing: 10

                                // ── Header ──────────────────────────────
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    IconImage {
                                        implicitSize: 26
                                        source: Quickshell.iconPath(
                                            AppSearch.guessIcon(root.appPopupId), "image-missing")
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: -3
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.appPopupId
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            font.bold: true
                                            color: Appearance.colors.colOnLayer0
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: AppDisplay.enabled
                                                ? (AppDisplay.triggerMatches(root.appPopupId)
                                                    ? "active now" : "waiting for trigger")
                                                : "per-app display is off"
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: AppDisplay.enabled && AppDisplay.triggerMatches(root.appPopupId)
                                                ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                        }
                                    }
                                    Rectangle {
                                        width: 26; height: 26; radius: 13
                                        color: apcHov.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover)
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        HoverHandler { margin: Appearance.sizes.touchSlop; id: apcHov; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { margin: Appearance.sizes.touchSlop; onTapped: root.appPopupId = "" }
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "close"; iconSize: 15
                                            color: Appearance.colors.colSubtext
                                        }
                                    }
                                }

                                // ── Scope ───────────────────────────────
                                StyledText {
                                    text: "Where it applies"
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                                SegChoice {
                                    options: [
                                        { label: "Whole screen", icon: "fullscreen", value: "screen" },
                                        { label: "Only the app", icon: "crop_free", value: "window" }
                                    ]
                                    current: appCard.prof.scope
                                    onPicked: v => AppDisplay.update(root.appPopupId, "scope", v)
                                }

                                // ── Trigger ─────────────────────────────
                                StyledText {
                                    text: "When it applies"
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                                SegChoice {
                                    options: [
                                        { label: "On focus", icon: "center_focus_strong", value: "focus" },
                                        { label: "On workspace", icon: "select_window", value: "workspace" }
                                    ]
                                    current: appCard.prof.trigger
                                    onPicked: v => AppDisplay.update(root.appPopupId, "trigger", v)
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 1
                                    color: Qt.alpha(Appearance.colors.colOnLayer0, 0.10)
                                }

                                // ── Window-scope controls ───────────────
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: appCard.windowScope
                                    text: "A surface sits on top of the window, so it can darken "
                                        + "and tint it — but nothing outside the window changes."
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                    wrapMode: Text.WordWrap
                                }
                                SettingSlider {
                                    visible: appCard.windowScope
                                    label: "Dim"
                                    icon: "brightness_low"
                                    from: 0.0; to: 0.9
                                    editScale: 100; decimals: 0; unit: "%"
                                    value: appCard.prof.dim
                                    onMovedValue: v => AppDisplay.update(root.appPopupId, "dim", v)
                                }
                                SettingSlider {
                                    visible: appCard.windowScope
                                    label: "Tint strength"
                                    icon: "opacity"
                                    from: 0.0; to: 0.8
                                    editScale: 100; decimals: 0; unit: "%"
                                    value: appCard.prof.tintStrength
                                    onMovedValue: v => AppDisplay.update(root.appPopupId, "tintStrength", v)
                                }
                                // Animated effect from a pack — window scope
                                // only, because we draw it ourselves on the
                                // overlay rather than asking the compositor.
                                RippleButton {
                                    Layout.fillWidth: true
                                    visible: appCard.windowScope
                                    implicitHeight: 38
                                    colBackground: Appearance.colors.colLayer1
                                    contentItem: RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8
                                        MaterialSymbol {
                                            text: "animation"; iconSize: 16
                                            color: appCard.prof.effect.length > 0
                                                ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: -3
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: "Effect"
                                                font.pixelSize: 11
                                                color: Appearance.colors.colOnLayer1
                                                elide: Text.ElideRight
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: appCard.prof.effect.length > 0
                                                    ? AppDisplay.effectName(appCard.prof.effect)
                                                    : "None"
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: appCard.prof.effect.length > 0
                                                    ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                                elide: Text.ElideRight
                                            }
                                        }
                                        MaterialSymbol {
                                            text: "chevron_right"; iconSize: 15
                                            color: Appearance.colors.colSubtext
                                        }
                                    }
                                    onClicked: root.effectTarget = root.appPopupId
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    visible: appCard.windowScope
                                    spacing: 7
                                    Repeater {
                                        model: ["#000000", "#FF6B35", "#FFC145", "#4CAF50",
                                                "#2196F3", "#7E57C2", "#EC407A", "#FFFFFF"]
                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property bool sel:
                                                appCard.prof.tint === modelData
                                            width: 26; height: 26; radius: 13
                                            color: modelData
                                            border.width: sel ? 3 : 1
                                            border.color: sel ? Appearance.colors.colPrimary
                                                              : Qt.alpha(Appearance.colors.colOnLayer0, 0.25)
                                            Behavior on border.width { NumberAnimation { duration: 120 } }
                                            HoverHandler { margin: Appearance.sizes.touchSlop; cursorShape: Qt.PointingHandCursor }
                                            TapHandler {
                                                margin: Appearance.sizes.touchSlop
                                                onTapped: AppDisplay.update(root.appPopupId, "tint", modelData)
                                            }
                                        }
                                    }
                                }

                                // ── Screen-scope controls ───────────────
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: !appCard.windowScope
                                    text: "Grading needs to read the pixels underneath, which only "
                                        + "the compositor can do — so it covers the whole display."
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                    wrapMode: Text.WordWrap
                                }
                                SettingSlider {
                                    visible: !appCard.windowScope
                                    label: "Saturation"
                                    icon: "invert_colors"
                                    from: 0.0; to: 2.0
                                    editScale: 100; decimals: 0; unit: "%"
                                    value: appCard.prof.saturation
                                    onMovedValue: v => AppDisplay.update(root.appPopupId, "saturation", v)
                                }
                                SettingSlider {
                                    visible: !appCard.windowScope
                                    label: "Contrast"
                                    icon: "contrast"
                                    from: 0.5; to: 2.0
                                    unit: "×"
                                    value: appCard.prof.contrast
                                    onMovedValue: v => AppDisplay.update(root.appPopupId, "contrast", v)
                                }
                                SettingSlider {
                                    visible: !appCard.windowScope
                                    label: "Gain"
                                    icon: "exposure"
                                    from: 0.3; to: 1.8
                                    unit: "×"
                                    value: appCard.prof.gain
                                    onMovedValue: v => AppDisplay.update(root.appPopupId, "gain", v)
                                }
                                SettingSlider {
                                    visible: !appCard.windowScope
                                    label: "Gamma"
                                    icon: "gradient"
                                    from: 0.5; to: 2.4
                                    value: appCard.prof.gamma
                                    onMovedValue: v => AppDisplay.update(root.appPopupId, "gamma", v)
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: !appCard.windowScope
                                    spacing: 10
                                    SettingSwitch {
                                        label: "Invert"
                                        checked: appCard.prof.invert
                                        onToggled: c => AppDisplay.update(root.appPopupId, "invert", c)
                                    }
                                    SettingSwitch {
                                        label: "Grayscale"
                                        checked: appCard.prof.grayscale
                                        onToggled: c => AppDisplay.update(root.appPopupId, "grayscale", c)
                                    }
                                }
                                RippleButton {
                                    Layout.fillWidth: true
                                    visible: !appCard.windowScope
                                    implicitHeight: 34
                                    colBackground: Appearance.colors.colLayer1
                                    contentItem: RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        MaterialSymbol {
                                            text: "auto_awesome"; iconSize: 15
                                            color: Appearance.colors.colOnLayer1
                                        }
                                        StyledText {
                                            text: {
                                                const sh = appCard.prof.shader;
                                                return sh && sh.length > 0
                                                    ? "Shader: " + AppDisplay.shaderName(sh)
                                                    : "Choose a shader…";
                                            }
                                            font.pixelSize: 11
                                            color: Appearance.colors.colOnLayer1
                                        }
                                    }
                                    onClicked: root.openBrowser(root.appPopupId)
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 1
                                    color: Qt.alpha(Appearance.colors.colOnLayer0, 0.10)
                                }

                                RippleButton {
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    colBackground: Appearance.colors.colLayer1
                                    contentItem: RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 5
                                        MaterialSymbol {
                                            text: "delete"; iconSize: 14
                                            color: Appearance.m3colors.m3error
                                        }
                                        StyledText {
                                            text: "Remove profile"
                                            font.pixelSize: 11
                                            color: Appearance.m3colors.m3error
                                        }
                                    }
                                    onClicked: {
                                        AppDisplay.clearProfile(root.appPopupId);
                                        root.appPopupId = "";
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Shader browser popup (WLAN/Bluetooth popup styling) ──
                Rectangle {
                    id: browserDim
                    anchors.fill: parent
                    radius: mainCard.radius
                    color: "#D0000000"
                    z: 300
                    visible: opacity > 0.01
                    opacity: root.shaderBrowserOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.shaderBrowserOpen = false
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 28
                        implicitHeight: Math.min(parent.height - 40, browserCol.implicitHeight + 26)
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colLayer0
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        transformOrigin: Item.Center
                        scale: root.shaderBrowserOpen ? 1.0 : 0.94
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        MouseArea { anchors.fill: parent } // block click-through

                        StyledFlickable {
                            id: browserFlick
                            anchors.fill: parent
                            anchors.margins: 13
                            contentHeight: browserCol.implicitHeight
                            clip: true

                        ColumnLayout {
                            id: browserCol
                            width: browserFlick.width
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 7
                                MaterialSymbol { text: "auto_awesome"; iconSize: 17; color: Appearance.colors.colPrimary }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.browserTarget.length > 0
                                        ? "Shader for " + root.browserTarget
                                        : "Shader Effects"
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.bold: true
                                    color: Appearance.colors.colOnLayer0
                                }
                                Rectangle {
                                    width: 26; height: 26; radius: 13
                                    color: bcHov.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    HoverHandler { margin: Appearance.sizes.touchSlop; id: bcHov }
                                    TapHandler { margin: Appearance.sizes.touchSlop; onTapped: root.shaderBrowserOpen = false }
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "close"; iconSize: 15
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }

                            // "None" — a real choice in per-app mode.
                            Rectangle {
                                Layout.fillWidth: true
                                visible: root.browserTarget.length > 0
                                implicitHeight: 36
                                radius: Appearance.rounding.small
                                readonly property bool sel: root.browserSelection === ""
                                color: sel ? Appearance.colors.colSecondaryContainer
                                    : (noneShHov.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover))
                                Behavior on color { ColorAnimation { duration: 130 } }
                                HoverHandler { id: noneShHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.browserPick("") }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    spacing: 8
                                    MaterialSymbol { text: "block"; iconSize: 15; color: Appearance.colors.colSubtext }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "None (no shader)"
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnLayer0
                                    }
                                }
                            }

                            // ── Shader folders, one container each ──────────
                            Repeater {
                                model: ScriptModel { values: root.shaderGroups }
                                delegate: ColumnLayout {
                                    id: shGroup
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 3

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 4
                                        spacing: 6
                                        MaterialSymbol { text: "folder"; iconSize: 13; color: Appearance.colors.colSubtext }
                                        StyledText {
                                            text: shGroup.modelData.name
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.bold: true
                                            color: Appearance.colors.colSubtext
                                        }
                                        StyledText {
                                            text: shGroup.modelData.items.length
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colSubtext
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 1
                                            color: Qt.alpha(Appearance.colors.colOnLayer0, 0.10)
                                        }
                                    }

                                    Repeater {
                                        model: ScriptModel { values: shGroup.modelData.items }
                                        delegate: Rectangle {
                                            id: shRow
                                            required property var modelData
                                            readonly property bool sel: shRow.modelData === root.browserSelection
                                            Layout.fillWidth: true
                                            implicitHeight: 40
                                            radius: Appearance.rounding.small
                                            color: shRow.sel ? Appearance.colors.colSecondaryContainer
                                                : (itemHov.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover))
                                            Behavior on color { ColorAnimation { duration: 130 } }
                                            HoverHandler { id: itemHov; cursorShape: Qt.PointingHandCursor }
                                            TapHandler { onTapped: root.browserPick(shRow.modelData) }
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                spacing: 8
                                                MaterialSymbol {
                                                    text: shRow.sel ? "check_circle" : "filter_vintage"
                                                    iconSize: 16
                                                    color: shRow.sel ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: -2
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: root.shaderName(shRow.modelData)
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        color: Appearance.colors.colOnLayer0
                                                        elide: Text.ElideRight
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: String(shRow.modelData).replace(Quickshell.env("HOME"), "~")
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        color: Appearance.colors.colSubtext
                                                        elide: Text.ElideMiddle
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Effect packs, shown as containers too ───────
                            // They live in the same list so a pack is visible
                            // where you look for shaders, but they are a
                            // different mechanism: animated, drawn by us, and
                            // only meaningful on a single window.
                            Repeater {
                                model: ScriptModel { values: AppDisplay.packNames }
                                delegate: ColumnLayout {
                                    id: pkGroup
                                    required property var modelData
                                    readonly property bool usable: root.browserTarget.length > 0
                                    Layout.fillWidth: true
                                    spacing: 3

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 6
                                        spacing: 6
                                        MaterialSymbol { text: "animation"; iconSize: 13; color: Appearance.colors.colPrimary }
                                        StyledText {
                                            text: String(pkGroup.modelData)
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.bold: true
                                            color: Appearance.colors.colPrimary
                                        }
                                        Rectangle {
                                            implicitHeight: 15
                                            implicitWidth: animBadge.implicitWidth + 12
                                            radius: 7
                                            color: Qt.alpha(Appearance.colors.colPrimary, 0.16)
                                            StyledText {
                                                id: animBadge
                                                anchors.centerIn: parent
                                                text: pkGroup.usable ? "animated" : "per-app only"
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colPrimary
                                            }
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 1
                                            color: Qt.alpha(Appearance.colors.colPrimary, 0.20)
                                        }
                                    }

                                    Repeater {
                                        model: ScriptModel {
                                            values: AppDisplay.effectsInPack(pkGroup.modelData)
                                        }
                                        delegate: Rectangle {
                                            id: pkRow
                                            required property var modelData
                                            readonly property bool sel: root.browserTarget.length > 0
                                                && AppDisplay.get(root.browserTarget).effect === pkRow.modelData.path
                                            Layout.fillWidth: true
                                            property bool paramsOpen: false
                                            implicitHeight: pkRow.paramsOpen
                                                ? 42 + pkChips.implicitHeight + 8 : 42
                                            Behavior on implicitHeight {
                                                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                            }
                                            radius: Appearance.rounding.small
                                            opacity: pkGroup.usable ? 1.0 : 0.45
                                            color: pkRow.sel ? Appearance.colors.colSecondaryContainer
                                                : (pkHov.hovered && pkGroup.usable
                                                    ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover))
                                            Behavior on color { ColorAnimation { duration: 130 } }
                                            HoverHandler {
                                                id: pkHov
                                                cursorShape: pkGroup.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            }
                                            TapHandler {
                                                enabled: pkGroup.usable
                                                onTapped: root.browserPickEffect(pkRow.modelData.path)
                                            }
                                            TapHandler {
                                                acceptedButtons: Qt.RightButton
                                                enabled: pkGroup.usable
                                                onTapped: pkRow.paramsOpen = !pkRow.paramsOpen
                                            }
                                            RowLayout {
                                                // Pinned to the top band, not filled: the row
                                                // grows when the chips open.
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                height: 42
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 10
                                                spacing: 9
                                                Rectangle {
                                                    implicitWidth: 22; implicitHeight: 22
                                                    radius: 11
                                                    color: Qt.alpha(pkRow.modelData.color, 0.9)
                                                    border.width: 1
                                                    border.color: Qt.alpha(Appearance.colors.colOnLayer0, 0.2)
                                                    MaterialSymbol {
                                                        anchors.centerIn: parent
                                                        text: pkRow.modelData.icon
                                                        iconSize: 12
                                                        color: Appearance.colors.colOnLayer0
                                                    }
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: -2
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: pkRow.modelData.name
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        color: Appearance.colors.colOnLayer0
                                                        elide: Text.ElideRight
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: pkGroup.usable ? pkRow.modelData.desc
                                                            : "open from an app to use this"
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        color: Appearance.colors.colSubtext
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                                MaterialSymbol {
                                                    visible: pkRow.sel
                                                    text: "check_circle"; iconSize: 15
                                                    color: Appearance.colors.colPrimary
                                                }
                                            }

                                            Flow {
                                                id: pkChips
                                                visible: pkRow.paramsOpen
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.topMargin: 44
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 10
                                                spacing: 5
                                                Repeater {
                                                    model: ScriptModel {
                                                        values: pkRow.paramsOpen ? (pkRow.modelData.params ?? []) : []
                                                    }
                                                    delegate: ParamChip {
                                                        required property var modelData
                                                        appId: root.browserTarget
                                                        effectPath: pkRow.modelData.path
                                                        param: modelData
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.shaderFiles.length === 0
                                    && AppDisplay.effects.length === 0 ? 90 : 0
                                visible: root.shaderFiles.length === 0 && AppDisplay.effects.length === 0
                                PagePlaceholder {
                                    anchors.centerIn: parent
                                    icon: "auto_awesome"
                                    title: "No shaders found"
                                    shown: parent.visible
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 7
                                RippleButton {
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    colBackground: Appearance.colors.colLayer1
                                    contentItem: RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        MaterialSymbol { text: "description"; iconSize: 14; color: Appearance.colors.colOnLayer1 }
                                        StyledText { text: "Open file"; font.pixelSize: 11; color: Appearance.colors.colOnLayer1 }
                                    }
                                    onClicked: { root.shaderBrowserOpen = false; filePicker.running = true; }
                                }
                                RippleButton {
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    colBackground: Appearance.colors.colLayer1
                                    contentItem: RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        MaterialSymbol { text: "create_new_folder"; iconSize: 14; color: Appearance.colors.colOnLayer1 }
                                        StyledText { text: "Add folder"; font.pixelSize: 11; color: Appearance.colors.colOnLayer1 }
                                    }
                                    onClicked: folderPicker.running = true
                                }
                                RippleButton {
                                    implicitWidth: 40
                                    implicitHeight: 32
                                    colBackground: Appearance.colors.colLayer1
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "refresh"; iconSize: 15
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    onClicked: root.rescanShaders()
                                }
                            }
                        }
                        }
                    }
                }
            }
        }
    }

    // ── Collapsible section ("deep settings" dropdown) ──────────────────
    component Expander: ColumnLayout {
        id: exp
        property string title: ""
        property string icon: ""
        property bool expanded: false
        // Children declared inside an Expander land in the collapsible body.
        default property alias bodyData: bodyCol.data

        Layout.fillWidth: true
        spacing: 4

        // Scroll the newly-revealed content into view once it has finished
        // expanding. Walks up to the enclosing Flickable rather than naming it,
        // so the component stays self-contained (it can't see `scroller` from
        // this scope anyway).
        onExpandedChanged: if (expanded) revealTimer.restart()

        Timer {
            id: revealTimer
            interval: 240          // just after the 210ms height animation
            repeat: false
            onTriggered: exp.revealSelf()
        }

        function revealSelf() {
            let f = exp.parent;
            while (f && f.contentY === undefined)
                f = f.parent;
            if (!f || f.height <= 0)
                return;
            const top = exp.mapToItem(f.contentItem, 0, 0).y;
            const bottom = top + exp.height;
            const maxY = Math.max(0, f.contentHeight - f.height);
            let target = f.contentY;
            if (bottom > f.contentY + f.height)          // hanging off the bottom
                target = Math.min(bottom - f.height + 12, maxY);
            if (top < target)                             // but keep the header visible
                target = Math.max(0, top - 12);
            if (Math.abs(target - f.contentY) > 1) {
                scrollAnim.target = f;
                scrollAnim.to = target;
                scrollAnim.restart();
            }
        }

        NumberAnimation {
            id: scrollAnim
            property: "contentY"
            duration: 260
            easing.type: Easing.OutCubic
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 34
            radius: Appearance.rounding.small
            color: expHov.hovered ? Qt.alpha(Appearance.colors.colOnLayer0, 0.06) : ColorUtils.transparentize(Qt.alpha(Appearance.colors.colOnLayer0, 0.06))
            Behavior on color { ColorAnimation { duration: 140 } }
            HoverHandler { id: expHov }
            TapHandler { onTapped: exp.expanded = !exp.expanded }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 4
                anchors.rightMargin: 8
                spacing: 7
                MaterialSymbol {
                    text: exp.icon
                    iconSize: 16
                    visible: exp.icon.length > 0
                    color: exp.expanded ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    text: exp.title
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.bold: true
                    color: Appearance.colors.colOnLayer0
                }
                MaterialSymbol {
                    text: "expand_more"
                    iconSize: 18
                    color: Appearance.colors.colSubtext
                    rotation: exp.expanded ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            clip: true
            implicitHeight: exp.expanded ? bodyCol.implicitHeight + 6 : 0
            opacity: exp.expanded ? 1 : 0
            visible: implicitHeight > 0.5
            Behavior on implicitHeight { NumberAnimation { duration: 210; easing.type: Easing.OutCubic } }
            Behavior on opacity        { NumberAnimation { duration: 150 } }

            ColumnLayout {
                id: bodyCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                spacing: 10
            }
        }
    }

    // ── Monitor arrangement (drag monitors like KDE Plasma) ─────────────
    component MonitorArrangement: Rectangle {
        id: arr
        readonly property var mons: HyprlandData.monitors ?? []
        readonly property real pad: 14
        // Emitted on drop. The panel wires this to its applyMonitor(); the
        // component can't call it directly since `win` isn't in scope here.
        signal requestApply(string name, string mode, real x, real y, real scale)
        // Tapping a monitor opens the popup FOR THAT MONITOR. It used to carry
        // no name and fire only from the container, so the popup always edited
        // whichever display happened to be first in Hyprland's list — the
        // reason per-display settings were unreachable rather than merely
        // unimplemented.
        signal requestOpen(string name)
        // Right-click. Coordinates are in THIS item's space, so the panel can
        // anchor the menu to the arrangement without knowing about the boxes.
        signal requestMenu(string name, real x, real y)

        Layout.fillWidth: true
        implicitHeight: 150
        radius: Appearance.rounding.normal
        color: Qt.alpha(Appearance.colors.colOnLayer0, arrHov.hovered ? 0.09 : 0.05)
        Behavior on color { ColorAnimation { duration: 140 } }
        border.width: 1
        border.color: Qt.alpha(Appearance.colors.colOnLayer0, 0.10)
        clip: true

        HoverHandler { id: arrHov; cursorShape: Qt.PointingHandCursor }
        // Empty background: fall back to the focused monitor, so a tap that
        // misses a box still opens something sensible rather than nothing.
        TapHandler {
            onTapped: arr.requestOpen(
                (arr.mons.find(m => m.focused)?.name) ?? (arr.mons[0]?.name ?? ""))
        }

        // Bounding box of every monitor in LOGICAL coordinates (px / scale).
        readonly property var bounds: {
            const ms = arr.mons;
            if (!ms || ms.length === 0)
                return { x: 0, y: 0, w: 1, h: 1 };
            let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
            for (let i = 0; i < ms.length; i++) {
                const m = ms[i];
                const s = m.scale || 1;
                x0 = Math.min(x0, m.x);
                y0 = Math.min(y0, m.y);
                x1 = Math.max(x1, m.x + m.width / s);
                y1 = Math.max(y1, m.y + m.height / s);
            }
            return { x: x0, y: y0, w: Math.max(x1 - x0, 1), h: Math.max(y1 - y0, 1) };
        }
        // Scale factor that fits the whole layout into this container.
        readonly property real fit: Math.min(
            (width  - pad * 2) / arr.bounds.w,
            (height - pad * 2) / arr.bounds.h)
        // Centre the layout in the container.
        readonly property real offX: (width  - arr.bounds.w * fit) / 2
        readonly property real offY: (height - arr.bounds.h * fit) / 2

        Repeater {
            model: arr.mons
            delegate: Rectangle {
                id: box
                required property var modelData
                readonly property real sc: modelData.scale || 1
                readonly property real logW: modelData.width / sc
                readonly property real logH: modelData.height / sc

                width: logW * arr.fit
                height: logH * arr.fit
                radius: 6
                readonly property bool selected: root.selectedMonitor === modelData.name
                readonly property int overrides: DisplayProfiles.overrideCount(modelData.name)

                color: drag.active
                    ? Appearance.colors.colPrimary
                    : (selected ? Appearance.colors.colPrimaryContainer
                                : Appearance.colors.colSecondaryContainer)
                // Selection is carried by the border weight as well as the fill,
                // because at this size the two container colours are close
                // enough to be ambiguous on a bright panel.
                border.width: selected ? 2 : 1
                border.color: Appearance.colors.colPrimary
                Behavior on color { ColorAnimation { duration: 140 } }
                Behavior on border.width { NumberAnimation { duration: 140 } }

                // Tapping a monitor selects it AND opens its settings.
                //
                // gesturePolicy matters here. With the default (DragThreshold)
                // a TapHandler keeps only a PASSIVE grab, so the container's
                // handler behind it also fired — the box set HDMI-A-1 and the
                // container immediately overwrote it with the focused monitor,
                // which is why clicking the external display kept opening the
                // internal one. WithinBounds takes an exclusive grab, so the
                // tap stops here.
                TapHandler {
                    gesturePolicy: TapHandler.WithinBounds
                    onTapped: arr.requestOpen(box.modelData.name)
                }

                // Right-click opens the per-monitor menu. Separate handler
                // rather than widening the one above: that one must stay
                // left-only, or a right-click would ALSO open the settings
                // popup behind the menu.
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    gesturePolicy: TapHandler.WithinBounds
                    onTapped: eventPoint => {
                        const p = box.mapToItem(arr, eventPoint.position.x, eventPoint.position.y);
                        arr.requestMenu(box.modelData.name, p.x, p.y);
                    }
                }

                // Marker: this display has settings of its own saved, rather
                // than running on Hyprland's defaults.
                //
                // It used to print the COUNT. Nobody reads "8" as "eight saved
                // overrides" — it reads as a workspace number, a port number,
                // anything but what it meant, and the exact figure is not
                // actionable anyway. A plain dot says the one thing that
                // matters (this one is customised); the tooltip and the
                // right-click menu carry the number for when you want it.
                Rectangle {
                    id: overrideBadge
                    visible: box.overrides > 0 && !drag.active
                    anchors { top: parent.top; right: parent.right; margins: 5 }
                    width: 7; height: 7; radius: width / 2
                    color: Appearance.colors.colPrimary
                    StyledToolTip {
                        text: Translation.tr("%1 saved setting(s) override the defaults here. Right-click for options.")
                            .arg(box.overrides)
                    }
                }

                // Position from Hyprland unless the user is dragging it.
                x: drag.active ? x : arr.offX + (modelData.x - arr.bounds.x) * arr.fit
                y: drag.active ? y : arr.offY + (modelData.y - arr.bounds.y) * arr.fit

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 0
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: box.modelData.name
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.bold: true
                        color: Appearance.m3colors.m3onSecondaryContainer
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: box.modelData.width + "×" + box.modelData.height
                            + " · " + Math.round(box.modelData.refreshRate) + "Hz"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.m3colors.m3onSecondaryContainer
                        opacity: 0.75
                    }
                    // Boxes are laid out in logical space; without this a
                    // 2560-wide panel draws smaller than a 1920 one.
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        visible: box.sc !== 1
                        text: Math.round(box.logW) + "×" + Math.round(box.logH)
                            + " @" + box.sc + "×"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.m3colors.m3onSecondaryContainer
                        opacity: 0.5
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        readonly property var check: MonitorAutoMode.inspect(box.modelData)
                        visible: check && (!check.modeOk || !check.scaleOk)
                        text: !check ? ""
                            : !check.modeOk && check.wantMode ? Translation.tr("↑ %1 available").arg(check.wantMode.str)
                            : Translation.tr("blurry: scale %1 doesn't divide evenly").arg(box.sc)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.m3colors.m3error
                    }
                }

                DragHandler {
                    id: drag
                    onActiveChanged: {
                        if (active)
                            return;
                        // Pixels back to logical coords, then snap to the edges
                        // of the other monitors so displays sit flush.
                        let nx = arr.bounds.x + (box.x - arr.offX) / arr.fit;
                        let ny = arr.bounds.y + (box.y - arr.offY) / arr.fit;
                        const snap = 60 / arr.fit;   // ~60px on screen
                        for (let i = 0; i < arr.mons.length; i++) {
                            const o = arr.mons[i];
                            if (o.name === box.modelData.name)
                                continue;
                            const os = o.scale || 1;
                            const ow = o.width / os, oh = o.height / os;
                            // horizontal: right-of / left-of
                            if (Math.abs(nx - (o.x + ow)) < snap) nx = o.x + ow;
                            if (Math.abs(nx + box.logW - o.x) < snap) nx = o.x - box.logW;
                            // vertical: below / above
                            if (Math.abs(ny - (o.y + oh)) < snap) ny = o.y + oh;
                            if (Math.abs(ny + box.logH - o.y) < snap) ny = o.y - box.logH;
                            // edge alignment
                            if (Math.abs(ny - o.y) < snap) ny = o.y;
                            if (Math.abs(nx - o.x) < snap) nx = o.x;
                        }
                        const mode = box.modelData.width + "x" + box.modelData.height
                            + "@" + box.modelData.refreshRate.toFixed(2);
                        arr.requestApply(box.modelData.name, mode, nx, ny, box.sc);
                    }
                }
            }
        }

        StyledText {
            anchors.centerIn: parent
            visible: arr.mons.length === 0
            text: "No monitors detected"
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    // ── Reusable rows ───────────────────────────────────────────────────
    component SettingSlider: ColumnLayout {
        id: srow
        property string label: ""
        property string icon: ""
        property real from: 0
        property real to: 1
        property real stepSize: 0
        property alias value: slider.value
        signal movedValue(real v)

        // ── Readout / typed entry ────────────────────────────────────────
        // The number shown (and typed) is the slider value scaled for human
        // units: brightness is a 0–1 slider shown as 0–100 %, so editScale
        // is 100 there and 1 for the ratio sliders.
        property real editScale: 1
        property int decimals: 2
        property string unit: ""
        readonly property real editValue: value * editScale
        readonly property string readout: editValue.toFixed(decimals) + unit

        // Apply a typed string: parse, unscale, clamp, snap to stepSize.
        // Anything unparseable just reverts the field to the live value.
        function commitText(t) {
            const n = parseFloat(String(t).replace(",", "."));
            if (!isFinite(n)) { readoutField.sync(); return; }
            let v = n / srow.editScale;
            v = Math.max(srow.from, Math.min(srow.to, v));
            if (srow.stepSize > 0)
                v = Math.round(v / srow.stepSize) * srow.stepSize;
            slider.value = v;
            srow.movedValue(v);
            readoutField.sync();
        }

        Layout.fillWidth: true
        spacing: 1
        opacity: enabled ? 1.0 : 0.45

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            MaterialSymbol {
                text: srow.icon
                iconSize: 15
                visible: srow.icon.length > 0
                color: Appearance.colors.colSubtext
            }
            StyledText {
                text: srow.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer0
            }
            Item { Layout.fillWidth: true }

            // Editable readout: shows the formatted value ("85%", "1.20×")
            // when idle, and the bare number while you're typing in it.
            Rectangle {
                Layout.preferredWidth: readoutField.implicitWidth + 12
                Layout.preferredHeight: readoutField.implicitHeight + 4
                radius: Appearance.rounding.verysmall
                color: readoutField.activeFocus
                    ? Qt.alpha(Appearance.colors.colPrimary, 0.14)
                    : (readoutHov.hovered ? Qt.alpha(Appearance.colors.colOnLayer0, 0.08)
                                          : ColorUtils.transparentize(Qt.alpha(Appearance.colors.colOnLayer0, 0.08)))
                Behavior on color { ColorAnimation { duration: 120 } }

                HoverHandler { id: readoutHov; cursorShape: Qt.IBeamCursor }

                TextInput {
                    id: readoutField
                    anchors.fill: parent
                    horizontalAlignment: TextInput.AlignHCenter
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colPrimary
                    selectionColor: Appearance.colors.colSecondaryContainer
                    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                    activeFocusOnTab: false
                    // Loose filter — the real clamp/snap happens in commitText().
                    validator: RegularExpressionValidator {
                        regularExpression: /-?\d*[.,]?\d*/
                    }

                    // text is assigned, never bound: focus flips it between the
                    // formatted readout and the raw editable number.
                    function sync() {
                        text = activeFocus ? srow.editValue.toFixed(srow.decimals)
                                           : srow.readout;
                    }
                    Component.onCompleted: sync()
                    onActiveFocusChanged: { sync(); if (activeFocus) selectAll(); }
                    Connections {
                        target: srow
                        function onReadoutChanged() {
                            if (!readoutField.activeFocus) readoutField.sync();
                        }
                    }

                    // Enter commits and releases focus; focus loss commits too.
                    onEditingFinished: srow.commitText(text)
                    onAccepted: focus = false
                }
            }
        }
        StyledSlider {
            id: slider
            Layout.fillWidth: true
            from: srow.from
            to: srow.to
            stepSize: srow.stepSize
            onMoved: srow.movedValue(value)
        }
    }

    // Segmented picker — two or three mutually exclusive choices, with the
    // selection indicated by a filled pill that slides between them.
    // One tunable variable of an effect, rendered inline on its row.
    // Numbers are drag-or-type pills, colours are a swatch that cycles a
    // palette, toggles are a chip — all narrow enough to sit in a row.
    // One tunable variable of an effect, rendered inline on its row.
    //
    // Drag scrubs, DOUBLE-CLICK types. Both are needed: dragging is how you
    // find a value by feel, typing is how you set one you already know — and
    // a single click cannot do both, because on a colour chip it already
    // means "next swatch".
    //
    // Colours accept a literal (#RRGGBB) or a THEME ROLE (@primary). The role
    // is stored verbatim rather than resolved here, so the effect keeps
    // following the wallpaper when the theme changes.
    component ParamChip: Rectangle {
        id: chip
        property string appId: ""
        property string effectPath: ""
        property var param: null
        property bool editing: false
        // StyledToolTip treats an undefined parent.hovered as "show", so
        // this must be exposed or the tip is permanently on screen.
        property bool hovered: chipHov.hovered

        readonly property var val: chip.param
            ? AppDisplay.paramValue(chip.appId, chip.effectPath, chip.param) : 0
        readonly property bool isFloat: chip.param?.type === "float"
        readonly property bool isColor: chip.param?.type === "color"
        readonly property bool isToggle: chip.param?.type === "toggle"
        // A theme role resolves for display but is stored as written.
        readonly property color shownColor: chip.isColor
            ? AppDisplay.resolveColor(String(chip.val)) : "transparent"

        readonly property var swatches: ["@primary", "@secondary", "@tertiary",
                                         "#0093FF", "#FE5F55", "#FFC500",
                                         "#4BC292", "#8867A6", "#16171F", "#F4EEE0"]

        function commit(text) {
            if (!chip.param) return;
            const t = String(text).trim();
            if (chip.isColor) {
                // Accept "@role", "#rrggbb", or a bare role name.
                let v = t;
                if (v.length === 0) { chip.editing = false; return; }
                if (!v.startsWith("@") && !v.startsWith("#")) v = "@" + v;
                AppDisplay.setParam(chip.appId, chip.effectPath, chip.param.id, v);
            } else {
                const n = parseFloat(t.replace(",", "."));
                if (isFinite(n)) {
                    let v = Math.max(chip.param.min, Math.min(chip.param.max, n));
                    if (chip.param.step > 0) v = Math.round(v / chip.param.step) * chip.param.step;
                    AppDisplay.setParam(chip.appId, chip.effectPath, chip.param.id, v);
                }
            }
            chip.editing = false;
        }

        implicitHeight: 22
        implicitWidth: chipRow.implicitWidth + 14
        radius: Appearance.rounding.verysmall
        color: chip.editing ? Qt.alpha(Appearance.colors.colPrimary, 0.18)
             : chipHov.hovered ? Appearance.colors.colLayer1Hover
                               : Appearance.colors.colLayer1
        Behavior on color { ColorAnimation { duration: 120 } }
        border.width: chip.editing ? 1 : 0
        border.color: Appearance.colors.colPrimary

        HoverHandler {
            id: chipHov
            cursorShape: chip.editing ? Qt.IBeamCursor
                       : chip.isFloat ? Qt.SizeHorCursor : Qt.PointingHandCursor
        }

        // Scrub. Disabled while typing so a stray drag can't fight the caret.
        DragHandler {
            enabled: chip.isFloat && !chip.editing
            yAxis.enabled: false
            target: null
            property real startVal: 0
            onActiveChanged: if (active) startVal = chip.val
            onTranslationChanged: {
                if (!active || !chip.param) return;
                const span = (chip.param.max - chip.param.min);
                let v = startVal + (translation.x / 140) * span;
                v = Math.max(chip.param.min, Math.min(chip.param.max, v));
                if (chip.param.step > 0) v = Math.round(v / chip.param.step) * chip.param.step;
                AppDisplay.setParam(chip.appId, chip.effectPath, chip.param.id, v);
            }
        }

        TapHandler {
            enabled: !chip.editing
            onTapped: {
                if (chip.isColor) {
                    const i = chip.swatches.indexOf(String(chip.val));
                    AppDisplay.setParam(chip.appId, chip.effectPath, chip.param.id,
                                        chip.swatches[(i + 1) % chip.swatches.length]);
                } else if (chip.isToggle) {
                    AppDisplay.setParam(chip.appId, chip.effectPath, chip.param.id,
                                        chip.val > 0.5 ? 0 : 1);
                }
            }
            onDoubleTapped: {
                if (chip.isToggle) return;
                chip.editing = true;
                chipField.text = chip.isColor ? String(chip.val)
                                              : Number(chip.val).toFixed(chip.param.step >= 1 ? 0 : 2);
                chipField.forceActiveFocus();
                chipField.selectAll();
            }
        }

        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 5

            Rectangle {
                visible: chip.isColor
                implicitWidth: 11; implicitHeight: 11
                radius: 6
                color: chip.shownColor
                border.width: 1
                border.color: Qt.alpha(Appearance.colors.colOnLayer0, 0.3)
            }
            Rectangle {
                visible: chip.isToggle
                implicitWidth: 16; implicitHeight: 10
                radius: 5
                color: chip.val > 0.5 ? Appearance.colors.colPrimary
                                      : Qt.alpha(Appearance.colors.colOnLayer0, 0.25)
                Behavior on color { ColorAnimation { duration: 140 } }
                Rectangle {
                    width: 8; height: 8; radius: 4
                    y: 1
                    x: chip.val > 0.5 ? parent.width - 9 : 1
                    color: Appearance.colors.colLayer0
                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }
            }
            StyledText {
                text: chip.param?.label ?? ""
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnLayer1
            }
            // Idle display.
            StyledText {
                visible: !chip.editing && !chip.isToggle
                text: chip.isColor ? String(chip.val)
                                   : Number(chip.val).toFixed(chip.param?.step >= 1 ? 0 : 2)
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colPrimary
            }
            // Typing.
            TextInput {
                id: chipField
                visible: chip.editing
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colPrimary
                selectionColor: Appearance.colors.colSecondaryContainer
                selectByMouse: true
                activeFocusOnTab: false
                // Colours take "@role" and "#hex", so no numeric validator.
                onEditingFinished: if (chip.editing) chip.commit(text)
                onAccepted: chip.commit(text)
                Keys.onEscapePressed: chip.editing = false
            }
        }

        StyledToolTip {
            text: chip.isColor
                ? "Click cycles · double-click to type  #RRGGBB  or  @primary / @secondary / @tertiary / @surface / @outline / @accent / @text / @bg"
                : chip.isToggle ? "Click to toggle"
                : "Drag to scrub · double-click to type"
        }
    }

    component SegChoice: RowLayout {
        id: segRoot
        property var options: []        // [{ label, icon, value }]
        property string current: ""
        signal picked(string value)

        Layout.fillWidth: true
        spacing: 0

        Repeater {
            model: segRoot.options
            delegate: Rectangle {
                id: segCell
                required property var modelData
                readonly property bool sel: segCell.modelData.value === segRoot.current
                Layout.fillWidth: true
                implicitHeight: 32
                radius: Appearance.rounding.small
                color: segCell.sel ? Appearance.colors.colPrimary
                    : (segHov.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1)
                Behavior on color { ColorAnimation { duration: 150 } }
                HoverHandler { id: segHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: segRoot.picked(segCell.modelData.value) }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 5
                    MaterialSymbol {
                        text: segCell.modelData.icon ?? ""
                        iconSize: 14
                        visible: text.length > 0
                        color: segCell.sel ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: segCell.modelData.label
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: segCell.sel ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }

    component SettingSwitch: RowLayout {
        id: swrow
        property string label: ""
        property alias checked: sw.checked
        signal toggled(bool c)
        spacing: 5
        StyledSwitch {
            id: sw
            onCheckedChanged: swrow.toggled(checked)
        }
        StyledText {
            text: swrow.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer0
        }
    }
}



























