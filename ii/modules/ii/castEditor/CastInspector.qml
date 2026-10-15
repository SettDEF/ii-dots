import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.walltune
import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell.Io

/// Right-hand inspector: the selected timeline block, then one tab of
/// settings (look, cursor, zoom, camera, export).
Rectangle {
    id: insp
    required property var doc
    property string tab: "look"
    signal exportRequested()
    color: Appearance.colors.colLayer0

    readonly property var t: doc.tl
    readonly property var cam: doc.tl && doc.tl.webcam ? doc.tl.webcam : null
    function ed(fn) { insp.doc.edit(fn); }

    /// Installed cursor themes (`tinct-cast cursors`), loaded when the Cursor tab opens.
    property var cursorThemes: null
    Process {
        id: cursorsProc
        running: insp.tab === "cursor" && insp.cursorThemes === null
        command: insp.doc.cli(["cursors"])
        stdout: StdioCollector { onStreamFinished: { try { insp.cursorThemes = JSON.parse(text); } catch (e) { insp.cursorThemes = { active: "", themes: [] }; } } }
    }
    function cardMenu(item, x, y, card) {
        const names = { background: "background", frame: "frame", cursor: "cursor settings", zoom: "zoom settings", follow: "follow settings", camera: "camera settings" };
        insp.doc.menu(item, x, y, [{ icon: "restart_alt", label: "Reset " + names[card], enabled: !!insp.doc.defaults, onTriggered: () => insp.doc.resetCard(card) }]);
    }
    function pct(v) { return Math.round(v * 100) + "%"; }
    readonly property var transitions: [{ id: "smooth", label: "Smooth" }, { id: "fade", label: "Fade" }, { id: "slide", label: "Slide" }, { id: "zoom", label: "Zoom" }, { id: "cut", label: "Cut" }]

    // Background presets from the live tinct palette (roles, never hex).
    readonly property var gradients: [
        { from: Appearance.m3colors.m3primaryContainer, to: Appearance.m3colors.m3tertiary, label: "Primary → tertiary" },
        { from: Appearance.m3colors.m3secondaryContainer, to: Appearance.m3colors.m3primary, label: "Secondary → primary" },
        { from: Appearance.m3colors.m3surfaceContainerHigh, to: Appearance.m3colors.m3tertiaryContainer, label: "Surface → tertiary" },
        { from: Appearance.m3colors.m3primary, to: Appearance.m3colors.m3tertiary, label: "Primary → tertiary (bright)" },
        { from: Appearance.m3colors.m3tertiaryContainer, to: Appearance.m3colors.m3secondaryContainer, label: "Tertiary → secondary" },
        { from: Appearance.m3colors.m3surfaceContainerLowest, to: Appearance.m3colors.m3primaryContainer, label: "Deep → primary" }
    ]
    readonly property var solids: [
        { c: Appearance.m3colors.m3surfaceContainer, label: "Surface" },
        { c: Appearance.m3colors.m3primaryContainer, label: "Primary container" },
        { c: Appearance.m3colors.m3secondaryContainer, label: "Secondary container" },
        { c: Appearance.m3colors.m3tertiaryContainer, label: "Tertiary container" },
        { c: Appearance.m3colors.m3inverseSurface, label: "Inverse surface" },
        { c: Appearance.m3colors.m3surfaceContainerLowest, label: "Deepest" }
    ]
    function same(a, c) {
        if (!a || !c) return false;
        const b = insp.doc.rgb(c);
        return Math.abs(a[0] - b[0]) + Math.abs(a[1] - b[1]) + Math.abs(a[2] - b[2]) < 0.02;
    }
    /// Gradients then solids, with look-alikes dropped: palettes often give
    /// two roles the same colour, which showed as two identical swatches
    /// that were both "selected".
    readonly property var presets: {
        const all = gradients.map(g => ({ kind: "gradient", from: g.from, to: g.to, label: g.label }))
            .concat(solids.map(s => ({ kind: "solid", from: s.c, to: s.c, label: s.label })));
        const out = [];
        for (const p of all) {
            const dup = out.some(q => q.kind === p.kind && same(insp.doc.rgb(q.from), p.from) && same(insp.doc.rgb(q.to), p.to));
            if (!dup) out.push(p);
        }
        return out;
    }
    /// The one preset matching the current background, or -1.
    readonly property int presetIndex: {
        const b = t ? t.style.background : null;
        if (!b) return -1;
        return presets.findIndex(p => p.kind === b.kind && (b.kind === "solid" ? same(b.color, p.from) : same(b.from, p.from) && same(b.to, p.to)));
    }

    // Created only when used: an idle dialog (and its file-name field) should
    // not exist, nor take part in focus handling, while nobody picks a file.
    Loader {
        id: imageDialog
        active: false
        function open() { active = true; item.open(); }
        sourceComponent: FileDialog {
            title: "Background image"
            nameFilters: ["Images (*.png *.jpg *.jpeg *.webp)"]
            onAccepted: insp.ed(t => t.style.background = { kind: "image", path: selectedFile.toString().replace(/^file:\/\//, "") })
            onRejected: imageDialog.active = false
        }
    }

    // ── Media: layers, inserts, presets (tinct-cast media does the maths,
    // the result comes back as a normal, undoable edit) ─────────────────────
    readonly property var media: doc.tl && doc.tl.media ? doc.tl.media : null
    readonly property var layers: media ? media.layers : []
    readonly property var inserts: media ? media.inserts : []
    property bool mediaFlip: false
    readonly property var lay: doc.layerSel >= 0 && doc.layerSel < layers.length ? layers[doc.layerSel] : null
    readonly property var ins: doc.insertSel >= 0 && doc.insertSel < inserts.length ? inserts[doc.insertSel] : null
    Connections { target: insp.doc; function onShowTab(name) { insp.tab = name; } }
    /// The export second at the playhead.
    function outNow() { return Math.round(insp.doc.srcToOut(insp.doc.playhead) * 10) / 10; }
    function fileName(p) { return (p || "").replace(/^.*\//, ""); }
    function mediaRun(args) {
        const extra = insp.media ? ["--media", JSON.stringify(insp.media)] : [];
        mediaProc.command = insp.doc.cli(["media", insp.doc.dir].concat(args).concat(["--print"]).concat(extra));
        mediaProc.running = true;
    }
    Process {
        id: mediaProc
        property string err: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length === 0) return;
                try {
                    const m = JSON.parse(text);
                    insp.ed(t => { t.media = m; delete t.compare; });
                } catch (e) { console.warn("castEditor: media: " + e); }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim().length > 0) console.warn("castEditor: media: " + text.trim()) }
    }
    // an older "compare" reference becomes a media layer when the tab opens
    Timer {
        running: insp.tab === "media" && insp.t !== null && !!insp.t.compare && !insp.media && !mediaProc.running
        interval: 50
        onTriggered: insp.mediaRun(["show"])
    }
    // length of the selected layer's / insert's source, for its section sliders
    property real srcDur: 0
    Process {
        id: srcProbe
        running: false
        stdout: StdioCollector { onStreamFinished: { try { insp.srcDur = JSON.parse(text).duration || 0; } catch (e) { insp.srcDur = 0; } } }
    }
    readonly property string probeFile: lay ? lay.file : (ins ? ins.file : "")
    onProbeFileChanged: {
        insp.srcDur = 0;
        if (probeFile.length > 0) {
            srcProbe.command = insp.doc.cli(["media", insp.doc.dir, "probe", probeFile]);
            srcProbe.running = true;
        }
    }
    property bool addAsInsert: false
    Loader {
        id: mediaDialog
        active: false
        function open(insert) { insp.addAsInsert = insert; active = true; item.open(); }
        sourceComponent: FileDialog {
            title: insp.addAsInsert ? "Cut in a video or image" : "Add a video or image"
            nameFilters: ["Videos and images (*.mp4 *.webm *.mkv *.mov *.avi *.gif *.png *.jpg *.jpeg *.webp)", "All files (*)"]
            onAccepted: {
                const f = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""));
                const n = insp.addAsInsert ? insp.inserts.length : insp.layers.length;
                insp.mediaRun(["add", f, "--at", String(insp.outNow())].concat(insp.addAsInsert ? ["--insert"] : []));
                if (insp.addAsInsert) { insp.doc.insertSel = n; insp.doc.layerSel = -1; } else { insp.doc.layerSel = n; insp.doc.insertSel = -1; }
                mediaDialog.active = false;
            }
            onRejected: mediaDialog.active = false
        }
    }
    function edLay(fn) { const i = insp.doc.layerSel; insp.ed(t => fn(t.media.layers[i])); }
    function edIns(fn) { const i = insp.doc.insertSel; insp.ed(t => fn(t.media.inserts[i])); }

    ColumnLayout {
        anchors { fill: parent; margins: 12 }
        spacing: 12

        SegmentedButtons {
            Layout.fillWidth: true
            segmentHeight: 34
            // Eight tabs: only the open one shows its name.
            model: [
                { id: "look", label: "Look", icon: "wallpaper" },
                { id: "cursor", label: "Cursor", icon: "arrow_selector_tool" },
                { id: "zoom", label: "Zoom", icon: "zoom_in" },
                { id: "audio", label: "Audio", icon: "graphic_eq" },
                { id: "camera", label: "Camera", icon: "videocam" },
                { id: "window", label: "Window", icon: "select_window" },
                { id: "media", label: "Media", icon: "video_library" },
                { id: "export", label: "Export", icon: "ios_share" }
            ].map(x => ({ id: x.id, icon: x.icon, label: x.id === insp.tab ? x.label : "" }))
            currentId: insp.tab
            onSelected: id => insp.tab = id
        }

        StyledFlickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: col.implicitHeight
            clip: true

            ColumnLayout {
                id: col
                width: flick.width
                spacing: 12

                // ── Selected block ──────────────────────────────────────
                Loader {
                    Layout.fillWidth: true
                    active: insp.doc.selection !== null && insp.t !== null
                    visible: active
                    sourceComponent: PaletteCard {
                        readonly property var sel: insp.doc.selection
                        readonly property var item: {
                            const t = insp.t, s = sel;
                            if (!t || !s) return null;
                            if (s.track === "zoom") return t.segments[s.index];
                            if (s.track === "cut") return (t.clip.cuts || [])[s.index];
                            if (s.track === "speed") return (t.clip.speed || [])[s.index];
                            if (s.track === "camera") return t.webcam ? t.webcam.segments[s.index] : null;
                            if (s.track === "cursor") return t.cursor && t.cursor.segments ? t.cursor.segments[s.index] : null;
                            if (s.track === "window") return t.window && t.window.segments ? t.window.segments[s.index] : null;
                            return null;
                        }
                        PaletteRow {
                            glyph: ({ zoom: "zoom_in", cut: "content_cut", speed: "speed", camera: "videocam", cursor: "visibility_off", window: "select_window" })[sel.track]
                            lit: true
                            title: ({ zoom: "Zoom segment", cut: "Cut", speed: "Speed change", camera: "Camera segment", cursor: item && item.visible ? "Cursor shown" : "Cursor hidden", window: "Window mode span" })[sel.track]
                            subtitle: item ? insp.doc.fmt(item.start) + " – " + insp.doc.fmt(item.end) : ""
                            trailing: ""
                            value: "Delete"
                            onClicked: insp.doc.deleteSelection()
                        }
                        PaletteDivider { visible: sel.track !== "cut" }
                        PaletteSlider {
                            visible: sel.track === "zoom" && item !== null
                            title: "Zoom level"
                            from: 1.1; to: 5; stepSize: 0.1
                            value: item && sel.track === "zoom" ? item.zoom : 2
                            valueText: value.toFixed(1) + "×"
                            onMoved: v => insp.ed(t => { t.segments[sel.index].zoom = v; t.segments[sel.index].kind = "manual"; })
                        }
                        PaletteRow {
                            visible: sel.track === "zoom" && item !== null
                            glyph: "my_location"
                            title: "Follow cursor"
                            subtitle: item && item.focus ? "Aimed at " + Math.round(item.focus[0]) + ", " + Math.round(item.focus[1]) + " (click the preview to move)" : "Click the preview to aim instead"
                            trailing: "switch"
                            isOn: item ? !item.focus : true
                            lit: isOn
                            onSwitched: {
                                const i = sel.index;
                                const f = insp.doc.frameInfo;
                                const centre = f ? [Math.round(f.view[0] + f.view[2] / 2), Math.round(f.view[1] + f.view[3] / 2)]
                                                 : [Math.round(insp.t.source.width / 2), Math.round(insp.t.source.height / 2)];
                                insp.ed(t => { t.segments[i].focus = t.segments[i].focus ? null : centre; });
                            }
                        }
                        SegmentedButtons {
                            visible: sel.track === "speed"
                            Layout.fillWidth: true
                            Layout.margins: 8
                            model: [{ id: 0.5, label: "0.5×" }, { id: 1.5, label: "1.5×" }, { id: 2, label: "2×" }, { id: 4, label: "4×" }, { id: 8, label: "8×" }]
                            currentId: item && sel.track === "speed" ? item.speed : 2
                            onSelected: id => insp.ed(t => t.clip.speed[sel.index].speed = id)
                        }
                        SegmentedButtons {
                            visible: sel.track === "window"
                            Layout.fillWidth: true
                            Layout.margins: 8
                            model: [{ id: "screen", label: "Screen", icon: "desktop_windows" }, { id: "follow", label: "Follow", icon: "ads_click" }, { id: "pin", label: "Pin", icon: "push_pin" }]
                            currentId: item && sel.track === "window" ? item.mode : "screen"
                            onSelected: id => insp.ed(t => t.window.segments[sel.index].mode = id)
                        }
                        SegmentedButtons {
                            visible: sel.track === "camera"
                            Layout.fillWidth: true
                            Layout.margins: 8
                            model: [{ id: "hidden", label: "Hidden", icon: "videocam_off" }, { id: "bubble", label: "Bubble", icon: "account_circle" }, { id: "fullscreen", label: "Full", icon: "fullscreen" }]
                            currentId: item && sel.track === "camera" ? item.mode : "bubble"
                            onSelected: id => insp.ed(t => t.webcam.segments[sel.index].mode = id)
                        }
                    }
                }

                // ── Look ────────────────────────────────────────────────
                ColumnLayout {
                    visible: insp.tab === "look" && insp.t !== null
                    Layout.fillWidth: true
                    spacing: 12
                    PaletteCard {
                        TapHandler { acceptedButtons: Qt.RightButton; onTapped: (ev) => insp.cardMenu(parent, ev.position.x, ev.position.y, "background") }
                        PaletteRow { glyph: "gradient"; title: "Background"; subtitle: "From your tinct palette"; trailing: ""; lit: true }
                        Flow {
                            Layout.fillWidth: true
                            Layout.margins: 8
                            spacing: 6
                            Repeater {
                                model: insp.presets
                                CastSwatch {
                                    required property var modelData
                                    required property int index
                                    objectName: "swatch-" + index
                                    from: modelData.from; to: modelData.to; label: modelData.label
                                    selected: index === insp.presetIndex
                                    onPicked: insp.ed(t => t.style.background = modelData.kind === "solid"
                                        ? { kind: "solid", color: insp.doc.rgb(modelData.from) }
                                        : { kind: "gradient", from: insp.doc.rgb(modelData.from), to: insp.doc.rgb(modelData.to), angle: 35 })
                                }
                            }
                        }
                        PaletteDivider {}
                        PaletteRow {
                            glyph: "image"
                            title: "Image"
                            subtitle: insp.t && insp.t.style.background.kind === "image" ? insp.t.style.background.path.split("/").pop() : "Choose a picture"
                            lit: insp.t && insp.t.style.background.kind === "image"
                            onClicked: imageDialog.open()
                        }
                    }
                    PaletteCard {
                        TapHandler { acceptedButtons: Qt.RightButton; onTapped: (ev) => insp.cardMenu(parent, ev.position.x, ev.position.y, "frame") }
                        PaletteRow { glyph: "crop_free"; title: "Frame"; trailing: ""; lit: true }
                        PaletteSlider {
                            title: "Padding"; from: 0; to: 0.25; value: insp.t ? insp.t.style.padding : 0
                            valueText: insp.pct(value); onMoved: v => insp.ed(t => t.style.padding = v)
                        }
                        PaletteSlider {
                            title: "Corner radius"; from: 0; to: 0.08; value: insp.t ? insp.t.style.radius : 0
                            valueText: insp.pct(value / 0.08); onMoved: v => insp.ed(t => t.style.radius = v)
                        }
                        PaletteSlider {
                            title: "Shadow size"; from: 0; to: 0.15; value: insp.t ? insp.t.style.shadow : 0
                            valueText: insp.pct(value / 0.15); onMoved: v => insp.ed(t => t.style.shadow = v)
                        }
                        PaletteSlider {
                            title: "Shadow strength"; from: 0; to: 1; value: insp.t ? insp.t.style.shadow_opacity : 0
                            valueText: insp.pct(value); onMoved: v => insp.ed(t => t.style.shadow_opacity = v)
                        }
                    }
                }

                // ── Cursor ──────────────────────────────────────────────
                PaletteCard {
                    visible: insp.tab === "cursor" && insp.t !== null
                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: (ev) => insp.cardMenu(parent, ev.position.x, ev.position.y, "cursor") }
                    PaletteRow {
                        glyph: "arrow_selector_tool"; title: "Show cursor"; trailing: "switch"
                        isOn: insp.t ? insp.t.cursor.visible : true; lit: isOn
                        onSwitched: insp.ed(t => t.cursor.visible = !t.cursor.visible)
                    }
                    PaletteDivider {}
                    PaletteSlider {
                        title: "Size"; from: 0.015; to: 0.09; value: insp.t ? insp.t.cursor.size : 0.035
                        valueText: (value / 0.035).toFixed(1) + "×"; onMoved: v => insp.ed(t => t.cursor.size = v)
                    }
                    PaletteSlider {
                        // Softer = lower spring frequency.
                        title: "Smoothing"; from: 0; to: 1
                        value: insp.t ? (40 - insp.t.cursor.spring.omega) / 34 : 0.35
                        valueText: insp.pct(value); onMoved: v => insp.ed(t => t.cursor.spring.omega = 40 - v * 34)
                    }
                    PaletteDivider {}
                    PaletteRow {
                        glyph: "visibility_off"; title: "Hide when idle"; subtitle: "Fade out when the mouse rests"; trailing: "switch"
                        isOn: insp.t ? insp.t.cursor.hide_idle > 0 : false; lit: isOn
                        onSwitched: insp.ed(t => t.cursor.hide_idle = t.cursor.hide_idle > 0 ? 0 : 1.5)
                    }
                    PaletteSlider {
                        visible: insp.t ? insp.t.cursor.hide_idle > 0 : false
                        title: "After"; from: 0.5; to: 5; stepSize: 0.25; value: insp.t ? Math.max(0.5, insp.t.cursor.hide_idle) : 1.5
                        valueText: value.toFixed(2) + " s"; onMoved: v => insp.ed(t => t.cursor.hide_idle = v)
                    }
                    PaletteSlider {
                        objectName: "cursorFade"
                        title: "Fade"; from: 0; to: 1; stepSize: 0.05; value: insp.t ? (insp.t.cursor.fade ?? 0.25) : 0.25
                        valueText: Math.round(value * 1000) + " ms"; onMoved: v => insp.ed(t => t.cursor.fade = v)
                    }
                    PaletteDivider {}
                    PaletteRow {
                        glyph: "ads_click"; title: "Click ripple"; trailing: "switch"
                        isOn: insp.t ? insp.t.cursor.ripple : true; lit: isOn
                        onSwitched: insp.ed(t => t.cursor.ripple = !t.cursor.ripple)
                    }
                    PaletteRow {
                        objectName: "keepRipples"
                        glyph: "touch_app"; title: "Ripples while hidden"; subtitle: "Show clicks where the cursor is hidden"; trailing: "switch"
                        isOn: insp.t ? !!insp.t.cursor.keep_ripples : false; lit: isOn
                        onSwitched: insp.ed(t => t.cursor.keep_ripples = !t.cursor.keep_ripples)
                    }
                }

                // Cursor theme: the system one, the built-in arrow or any installed theme.
                PaletteCard {
                    objectName: "cursorThemeCard"
                    visible: insp.tab === "cursor" && insp.t !== null
                    PaletteRow {
                        glyph: "palette"; title: "Cursor theme"; trailing: ""; lit: true
                        subtitle: insp.cursorThemes === null ? "Looking for themes…" : "Drawn with its hotspot on the pointer; arrow only (the live shape is not recorded)"
                    }
                    Flow {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8; Layout.rightMargin: 8; Layout.bottomMargin: 8
                        spacing: 6
                        Repeater {
                            model: insp.cursorThemes ? [{ name: null, label: "System · " + insp.cursorThemes.active, preview: (insp.cursorThemes.themes.find(x => x.name === insp.cursorThemes.active) || {}).preview || null, ok: true }].concat(insp.cursorThemes.themes.filter(x => x.ok)) : []
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool chosen: insp.t && (insp.t.cursor.theme ?? null) === modelData.name
                                objectName: "cursorTheme:" + (modelData.name ?? "system")
                                width: 92; height: 76
                                radius: Appearance.rounding.small
                                color: chosen ? Appearance.colors.colSecondaryContainer : (tileHover.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)
                                border.width: chosen ? 2 : 0
                                border.color: Appearance.colors.colPrimary
                                Image {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 8; width: 36; height: 36
                                    source: parent.modelData.preview ? "file://" + parent.modelData.preview : ""
                                    fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true
                                }
                                StyledText {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 6 }
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    text: parent.modelData.label.replace(/[-_]cursors?$/i, "")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: parent.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                }
                                HoverHandler { id: tileHover }
                                TapHandler { onTapped: insp.ed(t => t.cursor.theme = parent.modelData.name) }
                                StyledToolTip { text: parent.modelData.label; visible: tileHover.hovered }
                            }
                        }
                    }
                }

                // ── Window mode ─────────────────────────────────────────
                PaletteCard {
                    visible: insp.tab === "window" && insp.t !== null && !(insp.doc.windowsInfo && insp.doc.windowsInfo.has_windows)
                    PaletteRow {
                        glyph: "web_asset_off"; title: "No window data in this recording"
                        subtitle: "Recorded before window logging existed; record again to frame windows"; trailing: ""
                    }
                }
                ColumnLayout {
                    id: winSec
                    objectName: "windowSection"
                    visible: insp.tab === "window" && insp.t !== null && !!(insp.doc.windowsInfo && insp.doc.windowsInfo.has_windows)
                    Layout.fillWidth: true
                    spacing: 12
                    readonly property var w: insp.t && insp.t.window ? insp.t.window : ({})
                    PaletteCard {
                        PaletteRow { glyph: "select_window"; title: "Frame"; subtitle: "The whole screen, the focused window or one window"; trailing: ""; lit: true }
                        SegmentedButtons {
                            objectName: "windowMode"
                            Layout.fillWidth: true
                            Layout.margins: 8
                            model: [{ id: "screen", label: "Screen", icon: "desktop_windows" }, { id: "follow", label: "Follow focus", icon: "ads_click" }, { id: "pin", label: "Pin window", icon: "push_pin" }]
                            currentId: winSec.w.mode ?? "screen"
                            onSelected: id => insp.ed(t => { t.window.mode = id; if (id === "pin" && !t.window.pin && insp.doc.windowsInfo.windows.length) t.window.pin = insp.doc.windowsInfo.windows[0].address; })
                        }
                        Repeater {
                            model: (winSec.w.mode === "pin" && insp.doc.windowsInfo) ? insp.doc.windowsInfo.windows : []
                            PaletteRow {
                                required property var modelData
                                objectName: "pin:" + modelData.class
                                glyph: "web_asset"; title: modelData.class; subtitle: modelData.address; trailing: ""
                                isOn: insp.t && (insp.t.window.pin === modelData.address || insp.t.window.pin === modelData.class); lit: isOn
                                onClicked: insp.ed(t => t.window.pin = modelData.address)
                            }
                        }
                    }
                    PaletteCard {
                        PaletteRow { glyph: "web"; title: "Decorations"; subtitle: "Title bar and border"; trailing: ""; lit: true }
                        SegmentedButtons {
                            objectName: "windowDecorations"
                            Layout.fillWidth: true
                            Layout.margins: 8
                            model: [{ id: "with", label: "With" }, { id: "without", label: "Without" }, { id: "clean", label: "Clean" }]
                            currentId: winSec.w.decorations ?? "with"
                            onSelected: id => insp.ed(t => t.window.decorations = id)
                        }
                        PaletteDivider {}
                        PaletteSlider {
                            title: "Margin"; from: 0; to: 0.2; value: winSec.w.margin ?? 0.04
                            valueText: insp.pct(value); onMoved: v => insp.ed(t => t.window.margin = v)
                        }
                        PaletteRow {
                            objectName: "windowIsolate"
                            glyph: "filter_center_focus"; title: "Isolate"; subtitle: "Background around the window instead of the desktop"; trailing: "switch"
                            isOn: winSec.w.isolate !== false; lit: isOn
                            onSwitched: insp.ed(t => t.window.isolate = !(t.window.isolate !== false))
                        }
                        PaletteRow {
                            glyph: "rounded_corner"; title: "Window rounding"; subtitle: "Use the window's own corner radius"; trailing: "switch"
                            isOn: winSec.w.keep_rounding !== false; lit: isOn
                            onSwitched: insp.ed(t => t.window.keep_rounding = !(t.window.keep_rounding !== false))
                        }
                        SegmentedButtons {
                            Layout.fillWidth: true
                            Layout.margins: 8
                            model: [{ id: "fit", label: "Fit window" }, { id: "fill", label: "Fill output" }]
                            currentId: winSec.w.aspect ?? "fit"
                            onSelected: id => insp.ed(t => t.window.aspect = id)
                        }
                    }
                    PaletteCard {
                        PaletteRow { glyph: "transition_slide"; title: "Switching windows"; trailing: ""; lit: true; subtitle: "Right-click a switch on the Window track to change one" }
                        SegmentedButtons {
                            objectName: "windowTransition"
                            Layout.fillWidth: true
                            Layout.margins: 8
                            model: insp.transitions
                            currentId: winSec.w.transition ?? "smooth"
                            onSelected: id => insp.ed(t => t.window.transition = id)
                        }
                        PaletteSlider {
                            title: "Duration"; from: 0.15; to: 1.5; stepSize: 0.05; value: winSec.w.duration ?? 0.6
                            valueText: Math.round(value * 1000) + " ms"; onMoved: v => insp.ed(t => t.window.duration = v)
                        }
                        PaletteSlider {
                            title: "Ignore focus shorter than"; from: 0; to: 1.5; stepSize: 0.05; value: winSec.w.min_focus ?? 0.4
                            valueText: Math.round(value * 1000) + " ms"; onMoved: v => insp.ed(t => t.window.min_focus = v)
                        }
                        PaletteDivider {}
                        PaletteRow { glyph: "view_carousel"; title: "Workspace switch"; trailing: ""; subtitle: "Hyprland's own animation stays in the video" }
                        SegmentedButtons {
                            Layout.fillWidth: true
                            Layout.margins: 8
                            model: insp.transitions
                            currentId: winSec.w.workspace_transition ?? "slide"
                            onSelected: id => insp.ed(t => t.window.workspace_transition = id)
                        }
                        RippleButton {
                            objectName: "cutWorkspaceAnims"
                            Layout.margins: 8
                            implicitHeight: 32
                            implicitWidth: cwRow.implicitWidth + 24
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            enabled: insp.doc.windowsInfo && insp.doc.windowsInfo.switches.length > 0
                            onClicked: insp.doc.cutWorkspaceAnimations(0.35)
                            contentItem: Item {
                                RowLayout {
                                    id: cwRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    MaterialSymbol { text: "content_cut"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer2 }
                                    StyledText { text: "Cut workspace animations (" + (insp.doc.windowsInfo ? insp.doc.windowsInfo.switches.length : 0) + ")"; color: Appearance.colors.colOnLayer2; font.pixelSize: Appearance.font.pixelSize.small }
                                }
                            }
                            StyledToolTip { text: "Adds a 0.35 s cut where each workspace change animates" }
                        }
                        PaletteDivider {}
                        PaletteRow { glyph: "visibility_off"; title: "Window not visible"; trailing: ""; subtitle: "Pinned window on another workspace, or none focused" }
                        SegmentedButtons {
                            Layout.fillWidth: true
                            Layout.margins: 8
                            model: [{ id: "keep", label: "Keep framing" }, { id: "screen", label: "Whole screen" }]
                            currentId: winSec.w.offscreen ?? "keep"
                            onSelected: id => insp.ed(t => t.window.offscreen = id)
                        }
                    }
                }

                // ── Zoom ────────────────────────────────────────────────
                ColumnLayout {
                    visible: insp.tab === "zoom" && insp.t !== null
                    Layout.fillWidth: true
                    spacing: 12
                    PaletteCard {
                        TapHandler { acceptedButtons: Qt.RightButton; onTapped: (ev) => insp.cardMenu(parent, ev.position.x, ev.position.y, "zoom") }
                        PaletteRow {
                            glyph: "auto_awesome"; title: "Auto zoom"; subtitle: "On clicks and typing"; trailing: "switch"
                            isOn: insp.t ? insp.t.zoom.auto : true; lit: isOn
                            onSwitched: insp.ed(t => t.zoom.auto = !t.zoom.auto)
                        }
                        PaletteDivider {}
                        PaletteSlider {
                            title: "Default level"; from: 1.2; to: 4; stepSize: 0.1; value: insp.t ? insp.t.zoom.level : 2
                            valueText: value.toFixed(1) + "×"; onMoved: v => insp.ed(t => t.zoom.level = v)
                        }
                        PaletteRow {
                            glyph: "done_all"; title: "Apply to all segments"
                            onClicked: insp.ed(t => t.segments.forEach(s => s.zoom = t.zoom.level))
                        }
                        PaletteRow {
                            glyph: "add"; title: "Add zoom at playhead"
                            onClicked: insp.doc.addAt("zoom")
                        }
                    }
                    PaletteCard {
                        TapHandler { acceptedButtons: Qt.RightButton; onTapped: (ev) => insp.cardMenu(parent, ev.position.x, ev.position.y, "follow") }
                        PaletteRow { glyph: "my_location"; title: "Follow"; subtitle: "How the zoomed view tracks the cursor"; trailing: ""; lit: true }
                        PaletteSlider {
                            title: "Free area"; from: 0.2; to: 0.9; value: insp.t ? insp.t.camera.dead_zone : 0.5
                            valueText: insp.pct(value); onMoved: v => insp.ed(t => t.camera.dead_zone = v)
                        }
                        PaletteSlider {
                            title: "Pan speed"; from: 3; to: 12; value: insp.t ? insp.t.camera.pan_spring.omega : 6.5
                            valueText: value.toFixed(1); onMoved: v => insp.ed(t => t.camera.pan_spring.omega = v)
                        }
                        PaletteSlider {
                            title: "Zoom speed"; from: 3; to: 14; value: insp.t ? insp.t.camera.zoom_spring.omega : 7
                            valueText: value.toFixed(1); onMoved: v => insp.ed(t => t.camera.zoom_spring.omega = v)
                        }
                    }
                }

                // ── Audio ───────────────────────────────────────────────
                PaletteCard {
                    visible: insp.tab === "audio" && insp.t !== null && insp.t.audio.tracks.length === 0
                    PaletteRow {
                        glyph: "volume_off"; title: "No audio in this recording"
                        subtitle: "New recordings take system sound and the mic as two tracks"; trailing: ""
                    }
                }
                ColumnLayout {
                    visible: insp.tab === "audio" && insp.t !== null && insp.t.audio.tracks.length > 0
                    Layout.fillWidth: true
                    spacing: 12
                    // One card per recorded track (system, mic, an app…).
                    Repeater {
                        model: insp.t ? insp.t.audio.tracks.length : 0
                        delegate: PaletteCard {
                            id: trackCard
                            required property int index
                            readonly property var a: insp.t ? insp.t.audio.tracks[index] : null
                            Layout.fillWidth: true
                            PaletteRow {
                                glyph: trackCard.a && trackCard.a.voice ? "mic" : "speaker"
                                title: trackCard.a ? (trackCard.a.label || ("Track " + (trackCard.index + 1))) : ""
                                subtitle: trackCard.a && trackCard.a.muted ? "Muted" : "In the mix"
                                trailing: "switch"
                                isOn: trackCard.a ? !trackCard.a.muted : true; lit: isOn
                                onSwitched: insp.ed(t => t.audio.tracks[trackCard.index].muted = !t.audio.tracks[trackCard.index].muted)
                            }
                            PaletteDivider {}
                            PaletteSlider {
                                title: "Volume"; from: 0; to: 2; stepSize: 0.05
                                value: trackCard.a ? trackCard.a.volume : 1
                                valueText: Math.round(value * 100) + "%"
                                onMoved: v => insp.ed(t => t.audio.tracks[trackCard.index].volume = v)
                            }
                            PaletteRow {
                                glyph: "noise_aware"; title: "Noise reduction"; subtitle: "Fan, hiss, room hum"; trailing: "switch"
                                isOn: trackCard.a ? trackCard.a.denoise : false; lit: isOn
                                onSwitched: insp.ed(t => t.audio.tracks[trackCard.index].denoise = !t.audio.tracks[trackCard.index].denoise)
                            }
                            PaletteRow {
                                glyph: "record_voice_over"; title: "Voice track"; subtitle: "The other tracks duck under it"; trailing: "switch"
                                isOn: trackCard.a ? trackCard.a.voice : false; lit: isOn
                                // one voice at a time
                                onSwitched: insp.ed(t => { const on = !t.audio.tracks[trackCard.index].voice; t.audio.tracks.forEach((x, i) => x.voice = on && i === trackCard.index); })
                            }
                        }
                    }
                    PaletteCard {
                        PaletteRow { glyph: "tune"; title: "Mix"; subtitle: "Applies to the whole export"; trailing: ""; lit: true }
                        PaletteSlider {
                            title: "Fade in"; from: 0; to: 5; stepSize: 0.1; value: insp.t ? insp.t.audio.fade_in : 0
                            valueText: value.toFixed(1) + " s"; onMoved: v => insp.ed(t => t.audio.fade_in = v)
                        }
                        PaletteSlider {
                            title: "Fade out"; from: 0; to: 5; stepSize: 0.1; value: insp.t ? insp.t.audio.fade_out : 0
                            valueText: value.toFixed(1) + " s"; onMoved: v => insp.ed(t => t.audio.fade_out = v)
                        }
                        PaletteSlider {
                            title: "Duck under voice"; from: 0; to: 1; stepSize: 0.05; value: insp.t ? insp.t.audio.duck : 0
                            valueText: value <= 0 ? "Off" : insp.pct(value); onMoved: v => insp.ed(t => t.audio.duck = v)
                        }
                        PaletteRow {
                            glyph: "equalizer"; title: "Even out loudness"; subtitle: "-16 LUFS, like streaming platforms"; trailing: "switch"
                            isOn: insp.t ? insp.t.audio.normalize : false; lit: isOn
                            onSwitched: insp.ed(t => t.audio.normalize = !t.audio.normalize)
                        }
                    }
                }

                // ── Camera ──────────────────────────────────────────────
                PaletteCard {
                    visible: insp.tab === "camera" && insp.t !== null && !insp.doc.hasWebcam
                    PaletteRow {
                        glyph: "videocam_off"; title: "No webcam in this recording"
                        subtitle: "Record with tinct-cast record --camera"; trailing: ""
                    }
                }
                ColumnLayout {
                    visible: insp.tab === "camera" && insp.doc.hasWebcam
                    Layout.fillWidth: true
                    spacing: 12
                    PaletteCard {
                        TapHandler { acceptedButtons: Qt.RightButton; onTapped: (ev) => insp.cardMenu(parent, ev.position.x, ev.position.y, "camera") }
                        PaletteRow {
                            glyph: "videocam"; title: "Show camera"; trailing: "switch"
                            isOn: insp.cam ? insp.cam.visible !== false : true; lit: isOn
                            onSwitched: insp.ed(t => t.webcam.visible = t.webcam.visible === false)
                        }
                        PaletteDivider {}
                        SegmentedButtons {
                            Layout.fillWidth: true
                            Layout.margins: 8
                            model: [{ id: "circle", label: "Circle", icon: "circle" }, { id: "rounded", label: "Rounded", icon: "rounded_corner" }]
                            currentId: insp.cam ? insp.cam.shape : "circle"
                            onSelected: id => insp.ed(t => t.webcam.shape = id)
                        }
                        PaletteSlider {
                            title: "Size"; from: 0.12; to: 0.5; value: insp.cam ? insp.cam.size : 0.28
                            valueText: insp.pct(value); onMoved: v => insp.ed(t => t.webcam.size = v)
                        }
                        PaletteSlider {
                            title: "Size while zoomed"; from: 0.3; to: 1; value: insp.cam ? insp.cam.zoomed_scale : 0.65
                            valueText: insp.pct(value); onMoved: v => insp.ed(t => t.webcam.zoomed_scale = v)
                        }
                    }
                    PaletteCard {
                        TapHandler { acceptedButtons: Qt.RightButton; onTapped: (ev) => insp.cardMenu(parent, ev.position.x, ev.position.y, "camera") }
                        PaletteRow { glyph: "picture_in_picture"; title: "Position"; trailing: ""; lit: true }
                        GridLayout {
                            Layout.margins: 8
                            Layout.alignment: Qt.AlignHCenter
                            columns: 2
                            rowSpacing: 6; columnSpacing: 6
                            Repeater {
                                model: [
                                    { id: "top-left", icon: "north_west" }, { id: "top-right", icon: "north_east" },
                                    { id: "bottom-left", icon: "south_west" }, { id: "bottom-right", icon: "south_east" }
                                ]
                                RippleButton {
                                    required property var modelData
                                    readonly property bool sel: insp.cam !== null && insp.cam.corner === modelData.id
                                    implicitWidth: 120; implicitHeight: 40
                                    buttonRadius: Appearance.rounding.small
                                    colBackground: sel ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                                    colBackgroundHover: sel ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
                                    onClicked: insp.ed(t => t.webcam.corner = modelData.id)
                                    contentItem: MaterialSymbol {
                                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                        text: modelData.icon
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: parent.sel ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                    }
                                }
                            }
                        }
                        PaletteDivider {}
                        PaletteRow {
                            glyph: "swap_horiz"; title: "Move away from cursor"; trailing: "switch"
                            isOn: insp.cam ? insp.cam.dodge : true; lit: isOn
                            onSwitched: insp.ed(t => t.webcam.dodge = !t.webcam.dodge)
                        }
                        PaletteRow {
                            glyph: "flip"; title: "Mirror"; trailing: "switch"
                            isOn: insp.cam ? insp.cam.mirror : true; lit: isOn
                            onSwitched: insp.ed(t => t.webcam.mirror = !t.webcam.mirror)
                        }
                        PaletteRow {
                            glyph: "add"; title: "Full screen at playhead"
                            onClicked: insp.doc.addAt("camera")
                        }
                    }
                }

                // ── Media ───────────────────────────────────────────────
                ColumnLayout {
                    visible: insp.tab === "media" && insp.t !== null
                    Layout.fillWidth: true
                    spacing: 12
                    PaletteCard {
                        PaletteRow {
                            glyph: "video_library"; title: "Media"; trailing: ""; lit: true
                            subtitle: insp.layers.length + insp.inserts.length === 0 ? "Videos or images with the recording, or cut in between" : insp.layers.length + " on the canvas · " + insp.inserts.length + " cut in"
                        }
                        PaletteDivider {}
                        PaletteRow { glyph: "add_photo_alternate"; title: "Add video or image…"; subtitle: "A layer on the canvas, from the playhead"; onClicked: mediaDialog.open(false) }
                        PaletteRow { glyph: "splitscreen_add"; title: "Cut in at the playhead…"; subtitle: "Intro, cut-in, outro: the recording waits"; onClicked: mediaDialog.open(true) }
                    }
                    PaletteCard {
                        visible: insp.layers.length > 0
                        PaletteRow { glyph: "dashboard"; title: "Layout"; subtitle: "Then fine-tune each layer"; trailing: ""; lit: true }
                        SegmentedButtons {
                            Layout.fillWidth: true
                            Layout.margins: 8
                            model: [{ id: "none", label: "Free", icon: "open_with" }, { id: "side", label: "Side", icon: "view_column_2" }, { id: "stack", label: "Stack", icon: "view_agenda" },
                                    { id: "corner", label: "Corner", icon: "picture_in_picture" }, { id: "grid", label: "2×2", icon: "grid_view" }]
                            currentId: ""
                            onSelected: id => insp.mediaRun(["preset", id].concat(insp.mediaFlip ? ["--flip"] : []))
                        }
                        PaletteRow {
                            glyph: "flip"; title: "Media first"; subtitle: "Left (side) or on top (stack)"; trailing: "switch"
                            isOn: insp.mediaFlip; lit: isOn
                            onSwitched: insp.mediaFlip = !insp.mediaFlip
                        }
                    }
                    // one row per layer; the selected one opens its settings below
                    PaletteCard {
                        visible: insp.layers.length > 0
                        PaletteRow { glyph: "layers"; title: "Layers"; subtitle: "Top of the list is drawn last (on top)"; trailing: ""; lit: true }
                        Repeater {
                            model: insp.layers.length
                            delegate: PaletteRow {
                                required property int index
                                readonly property var l: insp.layers[index]
                                glyph: l && insp.fileName(l.file).match(/\.(png|jpe?g|webp|bmp)$/i) ? "image" : "movie"
                                title: l ? (l.name || insp.fileName(l.file)) : ""
                                subtitle: l ? (l.visible ? "From " + insp.doc.fmt(l.at) + (l.dur > 0 ? " for " + l.dur.toFixed(1) + " s" : " to the end") : "Hidden") : ""
                                trailing: "switch"
                                isOn: l ? l.visible : true
                                lit: insp.doc.layerSel === index
                                onSwitched: { const i = index; insp.ed(t => t.media.layers[i].visible = !t.media.layers[i].visible); }
                                onClicked: { insp.doc.layerSel = insp.doc.layerSel === index ? -1 : index; insp.doc.insertSel = -1; }
                            }
                        }
                    }
                    // ── the selected layer ──
                    PaletteCard {
                        visible: insp.lay !== null
                        PaletteRow {
                            glyph: "tune"; title: insp.lay ? (insp.lay.name || insp.fileName(insp.lay.file)) : ""
                            subtitle: insp.srcDur > 0 ? "Source " + insp.doc.fmt(insp.srcDur) : "Image"; trailing: ""; lit: true
                        }
                        PaletteDivider {}
                        PaletteRow { glyph: "start"; title: "Starts at"; value: insp.lay ? insp.doc.fmt(insp.lay.at) : ""; subtitle: "Click: move to the playhead"; onClicked: { const v = insp.outNow(); insp.edLay(l => l.at = v); } }
                        PaletteSlider {
                            title: "Shows for"; from: 0; to: Math.max(insp.doc.outDuration, 1); stepSize: 0.1
                            value: insp.lay ? insp.lay.dur : 0
                            valueText: value <= 0 ? "To the end" : value.toFixed(1) + " s"
                            onMoved: v => insp.edLay(l => l.dur = v < 0.2 ? 0 : v)
                        }
                        PaletteSlider {
                            visible: insp.srcDur > 0
                            title: "Section start"; from: 0; to: Math.max(insp.srcDur, 1); stepSize: 0.1
                            value: insp.lay ? insp.lay.src_start : 0
                            valueText: insp.doc.fmt(value)
                            onMoved: v => insp.edLay(l => { l.src_start = v; if (l.src_end > 0 && l.src_end <= v) l.src_end = Math.min(v + 1, insp.srcDur); })
                        }
                        PaletteSlider {
                            visible: insp.srcDur > 0
                            title: "Section end"; from: 0; to: Math.max(insp.srcDur, 1); stepSize: 0.1
                            value: insp.lay ? (insp.lay.src_end > 0 ? insp.lay.src_end : insp.srcDur) : 0
                            valueText: insp.lay && insp.lay.src_end > 0 ? insp.doc.fmt(value) : "End of video"
                            onMoved: v => insp.edLay(l => l.src_end = v >= insp.srcDur - 0.05 ? 0 : Math.max(v, l.src_start + 0.2))
                        }
                        PaletteRow {
                            visible: insp.srcDur > 0
                            glyph: "repeat"; title: "Loop the section"; subtitle: "Else it holds its last frame"; trailing: "switch"
                            isOn: insp.lay ? insp.lay.loop : true; lit: isOn
                            onSwitched: insp.edLay(l => l.loop = !l.loop)
                        }
                        PaletteSlider {
                            visible: insp.srcDur > 0
                            title: "Speed"; from: 0.25; to: 3; stepSize: 0.05
                            value: insp.lay ? insp.lay.speed : 1
                            valueText: value.toFixed(2) + "×"
                            onMoved: v => insp.edLay(l => l.speed = v)
                        }
                        PaletteSlider {
                            visible: insp.srcDur > 0
                            title: "Sound"; from: 0; to: 1.5; stepSize: 0.05
                            value: insp.lay ? insp.lay.volume : 0
                            valueText: value <= 0 ? "Muted" : insp.pct(value)
                            onMoved: v => insp.edLay(l => l.volume = v)
                        }
                    }
                    PaletteCard {
                        visible: insp.lay !== null
                        PaletteRow { glyph: "crop_free"; title: "Box"; subtitle: "Or drag it in the preview"; trailing: ""; lit: true }
                        SegmentedButtons {
                            Layout.fillWidth: true
                            Layout.margins: 8
                            model: [{ id: "contain", label: "Whole", icon: "fit_screen" }, { id: "cover", label: "Fill", icon: "crop" }]
                            currentId: insp.lay ? insp.lay.fit : "contain"
                            onSelected: id => insp.edLay(l => l.fit = id)
                        }
                        Repeater {
                            model: [{ k: 0, t: "Left" }, { k: 1, t: "Top" }, { k: 2, t: "Width" }, { k: 3, t: "Height" }]
                            delegate: PaletteSlider {
                                required property var modelData
                                title: modelData.t; from: modelData.k < 2 ? -0.5 : 0.05; to: modelData.k < 2 ? 1 : 1; stepSize: 0.005
                                value: insp.lay ? insp.lay.rect[modelData.k] : 0
                                valueText: insp.pct(value)
                                onMoved: v => { const k = modelData.k; insp.edLay(l => l.rect[k] = v); }
                            }
                        }
                        PaletteRow {
                            glyph: "flip"; title: "Mirror"; trailing: "switch"
                            isOn: insp.lay ? insp.lay.mirror : false; lit: isOn
                            onSwitched: insp.edLay(l => l.mirror = !l.mirror)
                        }
                    }
                    PaletteCard {
                        visible: insp.lay !== null
                        PaletteRow { glyph: "auto_awesome"; title: "Look"; trailing: ""; lit: true }
                        PaletteSlider {
                            title: "Corner radius"; from: 0; to: 0.5; stepSize: 0.01
                            value: insp.lay ? insp.lay.radius : 0
                            valueText: value <= 0 ? "Square" : insp.pct(value * 2); onMoved: v => insp.edLay(l => l.radius = v)
                        }
                        PaletteSlider {
                            title: "Shadow"; from: 0; to: 1; stepSize: 0.05
                            value: insp.lay ? insp.lay.shadow : 0
                            valueText: value <= 0 ? "None" : insp.pct(value); onMoved: v => insp.edLay(l => l.shadow = v)
                        }
                        PaletteSlider {
                            title: "Opacity"; from: 0.1; to: 1; stepSize: 0.05
                            value: insp.lay ? insp.lay.opacity : 1
                            valueText: insp.pct(value); onMoved: v => insp.edLay(l => l.opacity = v)
                        }
                        PaletteSlider {
                            title: "Fade in"; from: 0; to: 3; stepSize: 0.1
                            value: insp.lay ? insp.lay.fade_in : 0
                            valueText: value <= 0 ? "Cut" : value.toFixed(1) + " s"; onMoved: v => insp.edLay(l => l.fade_in = v)
                        }
                        PaletteSlider {
                            title: "Fade out"; from: 0; to: 3; stepSize: 0.1
                            value: insp.lay ? insp.lay.fade_out : 0
                            valueText: value <= 0 ? "Cut" : value.toFixed(1) + " s"; onMoved: v => insp.edLay(l => l.fade_out = v)
                        }
                        MaterialTextField {
                            Layout.fillWidth: true; Layout.leftMargin: 8; Layout.rightMargin: 8
                            placeholderText: "Caption (empty = none)"
                            text: insp.lay ? insp.lay.caption : ""
                            onEditingFinished: if (insp.lay && text !== insp.lay.caption) { const v = text; insp.edLay(l => l.caption = v); }
                        }
                        PaletteRow {
                            glyph: "arrow_upward"; title: "Bring forward"; visible: insp.doc.layerSel >= 0 && insp.doc.layerSel < insp.layers.length - 1
                            onClicked: { const i = insp.doc.layerSel; insp.ed(t => { const a = t.media.layers; [a[i], a[i + 1]] = [a[i + 1], a[i]]; }); insp.doc.layerSel = i + 1; }
                        }
                        PaletteRow {
                            glyph: "delete"; title: "Remove layer"
                            onClicked: { const i = insp.doc.layerSel; insp.doc.layerSel = -1; insp.ed(t => t.media.layers.splice(i, 1)); }
                        }
                    }
                    // ── clips cut in between ──
                    PaletteCard {
                        visible: insp.inserts.length > 0
                        PaletteRow { glyph: "splitscreen_add"; title: "Cut in"; subtitle: "The recording waits while these play"; trailing: ""; lit: true }
                        Repeater {
                            model: insp.inserts.length
                            delegate: PaletteRow {
                                required property int index
                                readonly property var c: insp.inserts[index]
                                glyph: "movie_edit"
                                title: c ? (c.name || insp.fileName(c.file)) : ""
                                subtitle: c ? "At " + insp.doc.fmt(c.at) + " · " + c.transition : ""
                                trailing: ""
                                lit: insp.doc.insertSel === index
                                onClicked: { insp.doc.insertSel = insp.doc.insertSel === index ? -1 : index; insp.doc.layerSel = -1; }
                            }
                        }
                    }
                    PaletteCard {
                        visible: insp.ins !== null
                        PaletteRow { glyph: "tune"; title: insp.ins ? (insp.ins.name || insp.fileName(insp.ins.file)) : ""; subtitle: insp.srcDur > 0 ? "Source " + insp.doc.fmt(insp.srcDur) : "Image"; trailing: ""; lit: true }
                        PaletteDivider {}
                        PaletteRow { glyph: "start"; title: "Cut in at"; value: insp.ins ? insp.doc.fmt(insp.ins.at) : ""; subtitle: "Click: move to the playhead"; onClicked: { const v = insp.outNow(); insp.edIns(c => c.at = v); } }
                        SegmentedButtons {
                            Layout.fillWidth: true
                            Layout.margins: 8
                            model: [{ id: "cut", label: "Cut", icon: "content_cut" }, { id: "fade", label: "Fade", icon: "gradient" }, { id: "slide", label: "Slide", icon: "swipe_left" }]
                            currentId: insp.ins ? insp.ins.transition : "fade"
                            onSelected: id => insp.edIns(c => c.transition = id)
                        }
                        PaletteSlider {
                            visible: insp.ins !== null && insp.ins.transition !== "cut"
                            title: "Transition"; from: 0.1; to: 2; stepSize: 0.05
                            value: insp.ins ? insp.ins.blend : 0.4
                            valueText: value.toFixed(2) + " s"; onMoved: v => insp.edIns(c => c.blend = v)
                        }
                        PaletteSlider {
                            title: insp.srcDur > 0 ? "Section start" : "Shows for"; from: 0; to: insp.srcDur > 0 ? Math.max(insp.srcDur, 1) : 15; stepSize: 0.1
                            value: insp.ins ? (insp.srcDur > 0 ? insp.ins.src_start : insp.ins.src_end - insp.ins.src_start) : 0
                            valueText: insp.srcDur > 0 ? insp.doc.fmt(value) : value.toFixed(1) + " s"
                            onMoved: v => insp.edIns(c => { if (insp.srcDur > 0) { c.src_start = v; if (c.src_end > 0 && c.src_end <= v) c.src_end = 0; } else { c.src_start = 0; c.src_end = Math.max(v, 0.5); } })
                        }
                        PaletteSlider {
                            visible: insp.srcDur > 0
                            title: "Section end"; from: 0; to: Math.max(insp.srcDur, 1); stepSize: 0.1
                            value: insp.ins ? (insp.ins.src_end > 0 ? insp.ins.src_end : insp.srcDur) : 0
                            valueText: insp.ins && insp.ins.src_end > 0 ? insp.doc.fmt(value) : "End of video"
                            onMoved: v => insp.edIns(c => c.src_end = v >= insp.srcDur - 0.05 ? 0 : Math.max(v, c.src_start + 0.2))
                        }
                        PaletteSlider {
                            visible: insp.srcDur > 0
                            title: "Speed"; from: 0.25; to: 3; stepSize: 0.05
                            value: insp.ins ? insp.ins.speed : 1
                            valueText: value.toFixed(2) + "×"; onMoved: v => insp.edIns(c => c.speed = v)
                        }
                        PaletteSlider {
                            visible: insp.srcDur > 0
                            title: "Sound"; from: 0; to: 1.5; stepSize: 0.05
                            value: insp.ins ? insp.ins.volume : 1
                            valueText: value <= 0 ? "Muted" : insp.pct(value); onMoved: v => insp.edIns(c => c.volume = v)
                        }
                        PaletteRow {
                            glyph: "delete"; title: "Remove"
                            onClicked: { const i = insp.doc.insertSel; insp.doc.insertSel = -1; insp.ed(t => t.media.inserts.splice(i, 1)); }
                        }
                    }
                }

                // ── Export ──────────────────────────────────────────────
                PaletteCard {
                    visible: insp.tab === "export"
                    PaletteRow { glyph: "movie"; title: "Format"; value: insp.doc.exportFormat.toUpperCase(); onClicked: insp.exportRequested() }
                    PaletteRow { glyph: "aspect_ratio"; title: "Resolution"; value: insp.doc.exportRes === 2160 ? "4K" : insp.doc.exportRes + "p"; onClicked: insp.exportRequested() }
                    PaletteRow { glyph: "speed"; title: "Frame rate"; value: insp.doc.exportFps + " fps"; onClicked: insp.exportRequested() }
                    PaletteRow { glyph: "high_quality"; title: "Quality"; value: insp.doc.exportQuality; onClicked: insp.exportRequested() }
                    PaletteRow { glyph: "memory"; title: "Encoder"; value: insp.doc.exportEncoder; onClicked: insp.exportRequested() }
                    PaletteDivider {}
                    PaletteRow {
                        glyph: "timer"; title: "Length"; trailing: ""
                        value: insp.doc.fmt(insp.doc.outDuration)
                    }
                }
                Item { implicitHeight: 8 }
            }
        }
    }
}
