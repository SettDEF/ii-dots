// The drawing tools' colour picker.
//
// A saturation×value field over a hue rail. The version before this froze
// saturation at 0.62 — no grey, no white, no deep ink was reachable — and
// carried two "+" boxes wired to three names the file never defined.
//
// Properties:
//   selectedColor   — current colour, opaque (alpha lives in selectedOpacity)
//   selectedOpacity — alpha applied to the emitted colour
//
// Signal:
//   picked(color c) — fires on every field drag, swatch tap and opacity change
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import QtQuick.Layouts

Rectangle {
    id: root

    property color selectedColor: "#ff5a5a"
    property real selectedOpacity: 1.0

    signal picked(color c)

    // ── Colour state ───────────────────────────────────────────────────
    // HSV is the source of truth: a desaturated colour has no hue to come back
    // to, so a round trip through rgb snaps the hue rail to red.
    property real hueValue: 0
    property real satValue: 0.65
    property real valValue: 1.0

    // Guard so syncing from an external selectedColor does not loop back
    // through the h/s/v writers.
    property bool _syncing: false

    function _applyHsv() {
        root._syncing = true;
        root.selectedColor = Qt.hsva(root.hueValue, root.satValue, root.valValue, 1);
        root._syncing = false;
        root.emitColour();
    }

    onSelectedColorChanged: {
        if (root._syncing) return;
        // Externally assigned (a caller binding drawColor in, or a swatch tap).
        // hsvHue is -1 for greys; keep the hue we had rather than jumping.
        const h = root.selectedColor.hsvHue;
        if (h >= 0) root.hueValue = h;
        root.satValue = root.selectedColor.hsvSaturation;
        root.valValue = root.selectedColor.hsvValue;
    }

    function emitColour() {
        root.picked(Qt.rgba(root.selectedColor.r, root.selectedColor.g,
                            root.selectedColor.b, root.selectedOpacity));
    }

    function hex(c) {
        const f = v => Math.round(v * 255).toString(16).padStart(2, "0");
        return "#" + f(c.r) + f(c.g) + f(c.b);
    }

    /// Pick a readable ink for a swatch. A white tick on a pale yellow is
    /// invisible, and this grid deliberately spans light to dark.
    function inkOn(c) {
        return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.6 ? "#000000" : "#ffffff";
    }

    // ── Rail geometry ──────────────────────────────────────────────────
    // Both rails place a thumb wider than a pixel, so mapping 0..1 straight to
    // 0..width puts half the thumb outside the track at each end. The usable
    // travel is inset by half a thumb, and both directions go through these so
    // the maths cannot drift apart.
    readonly property real railHandleWidth: 14

    function railX(railWidth, handleWidth, fraction) {
        return handleWidth / 2 + fraction * (railWidth - handleWidth) - handleWidth / 2;
    }

    function railFraction(railWidth, mx) {
        const span = railWidth - root.railHandleWidth;
        if (span <= 0) return 0;
        return Math.max(0, Math.min(1, (mx - root.railHandleWidth / 2) / span));
    }

    // Not execDetached: the whole point is the answer it prints.
    property bool pickingFromScreen: false

    Process {
        id: eyedropper
        command: ["hyprpicker", "--no-fancy", "--format", "hex"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (/^#?[0-9a-fA-F]{6}$/.test(t)) {
                    root.useColour(t.startsWith("#") ? t : "#" + t);
                    root.rememberRecent(root.selectedColor);
                }
            }
        }
        onExited: root.pickingFromScreen = false
    }

    function pickFromScreen() {
        if (root.pickingFromScreen) return;
        root.pickingFromScreen = true;
        eyedropper.running = true;
    }

    function useColour(c) {
        root.selectedColor = c;
        root.emitColour();
    }

    // ── Palettes ───────────────────────────────────────────────────────
    // Hues are spread rather than harmonised: these colours exist to be told
    // apart on top of a screenshot, so a harmonious set defeats the point.
    readonly property var palettes: [
        { id: "studio", name: "Studio", colors: [
            "#a9b4d1","#8a84bd","#bca9d1","#b484bd","#d1a9c8","#bd849b","#d1a9aa","#bd9884",
            "#d1c5a9","#b8bd84","#bed1a9","#8dbd84","#a9d1b2","#84bda6","#a9d1cf","#84a9bd",
            "#d1555a","#d1835a","#d1b955","#9dc955","#56cd66","#55b9c9","#5a84d1","#9a5ad1"] },
        { id: "vivid", name: "Vivid", colors: [
            "#e74c4c","#e8823f","#e8c23f","#a8d43f","#3fd48a","#3fc4d4","#4a7fe0","#8a4ae0",
            "#d4573f","#d4973f","#c9d43f","#6ed43f","#3fd4b0","#3f9fd4","#5f5fe0","#b03fd4",
            "#b8383d","#b86a2e","#b8a02e","#7fb82e","#2eb87a","#2e9bb8","#3d5fb8","#7a2eb8"] },
        { id: "mono", name: "Mono", colors: [
            "#ffffff","#e0e0e0","#c9c9cd","#aeaeb4","#93939c","#787884","#5a5a5a","#000000",
            "#c8ccd2","#9aa0aa","#7a8aa0","#5f5f6e","#3a3a3e","#2c2c2e","#262628","#1a1a1c",
            "#6e5f5f","#6a6e5f","#5f6e6a","#6b6b78","#868690","#a1a1a8","#bcbcc0","#333335"] }
    ]

    readonly property var customPalettes: {
        try { return JSON.parse(Persistent.states.draw.customPalettes); }
        catch (e) { return []; }
    }

    readonly property var allPalettes: root.palettes.concat(root.customPalettes)
    readonly property string activeId: Persistent.states.draw.activePalette
    readonly property var activePalette: {
        const found = root.allPalettes.find(p => p.id === root.activeId);
        return found ? found : root.allPalettes[0];
    }
    readonly property bool activeIsCustom: !root.palettes.some(p => p.id === root.activeId)
    readonly property int gridColumns: 8
    /// Cell edge, derived so the grid always fills the picker's width exactly.
    property real gridWidth: root.implicitWidth - 24
    readonly property real swatchSize:
        (root.gridWidth - (root.gridColumns - 1) * 5) / root.gridColumns

    function saveCustom(list) {
        Persistent.states.draw.customPalettes = JSON.stringify(list);
    }

    function newPalette() {
        const list = root.customPalettes.slice();
        const palette = { id: "custom-" + Date.now(),
                          name: "Custom " + (list.length + 1), colors: [] };
        list.push(palette);
        root.saveCustom(list);
        Persistent.states.draw.activePalette = palette.id;
        root.addRowToActive();
    }

    function deletePalette(id) {
        root.saveCustom(root.customPalettes.filter(p => p.id !== id));
        Persistent.states.draw.activePalette = "studio";
    }

    // The three built-ins are read-only. Rather than refuse an edit on one,
    // fork it into a custom copy and apply the edit there, so every entry in
    // the grid is editable.
    function forkActive() {
        const src = root.activePalette;
        const list = root.customPalettes.slice();
        const palette = { id: "custom-" + Date.now(),
                          name: (src.name || "Palette") + " copy",
                          colors: (src.colors || []).slice() };
        list.push(palette);
        root.saveCustom(list);
        Persistent.states.draw.activePalette = palette.id;
    }

    function _editTarget() {
        if (!root.activeIsCustom) root.forkActive();
        const list = root.customPalettes.slice();
        const target = list.find(p => p.id === Persistent.states.draw.activePalette);
        return target ? { list: list, target: target } : null;
    }

    // A half-filled row reads as a broken grid, so rows — not single swatches
    // — are the unit you add and remove.
    function addRowToActive() {
        const e = root._editTarget();
        if (!e) return;
        const row = Math.floor(e.target.colors.length / root.gridColumns);
        const val = [1.0, 0.78, 0.56, 0.36][row % 4];
        for (let i = 0; i < root.gridColumns; i++)
            e.target.colors.push(root.hex(
                Qt.hsva((root.hueValue + i / root.gridColumns) % 1,
                        Math.max(0.2, root.satValue), val, 1)));
        root.saveCustom(e.list);
    }

    function setColorAt(index, c) {
        const e = root._editTarget();
        if (!e || index < 0 || index >= e.target.colors.length) return;
        e.target.colors[index] = String(c);
        root.saveCustom(e.list);
    }

    function removeRowAt(index) {
        const e = root._editTarget();
        if (!e) return;
        const row = Math.floor(index / root.gridColumns);
        e.target.colors.splice(row * root.gridColumns, root.gridColumns);
        root.saveCustom(e.list);
    }

    function removeColorAt(index) {
        const e = root._editTarget();
        if (!e || index < 0 || index >= e.target.colors.length) return;
        e.target.colors.splice(index, 1);
        root.saveCustom(e.list);
    }

    function paletteMenu() {
        const items = root.allPalettes.map(pal => ({
            icon: pal.id === root.activeId ? "check" : "palette",
            label: pal.name,
            onTriggered: () => Persistent.states.draw.activePalette = pal.id
        }));
        items.push({
            icon: "playlist_add",
            label: root.activeIsCustom ? Translation.tr("Add a row of 8")
                                       : Translation.tr("Duplicate and add a row"),
            onTriggered: () => root.addRowToActive()
        });
        items.push({
            icon: "add", label: Translation.tr("New palette"),
            onTriggered: () => root.newPalette()
        });
        if (root.activeIsCustom)
            items.push({
                icon: "delete", label: Translation.tr("Delete this palette"),
                onTriggered: () => root.deletePalette(root.activeId)
            });
        return items;
    }

    function menuForSwatch(index, hex) {
        const items = [{
            icon: "format_color_fill", label: Translation.tr("Set to current colour"),
            onTriggered: () => root.setColorAt(index, root.selectedColor)
        }, {
            icon: "content_copy", label: Translation.tr("Copy hex"),
            onTriggered: () => Quickshell.clipboardText = String(hex)
        }, {
            icon: "close", label: Translation.tr("Remove colour"),
            onTriggered: () => root.removeColorAt(index)
        }, {
            icon: "playlist_add", label: Translation.tr("Add row"),
            onTriggered: () => root.addRowToActive()
        }, {
            icon: "playlist_remove", label: Translation.tr("Remove row"),
            onTriggered: () => root.removeRowAt(index)
        }];
        if (!root.activeIsCustom)
            items.push({
                icon: "file_copy", label: Translation.tr("Duplicate palette to edit"),
                onTriggered: () => root.forkActive()
            });
        return items;
    }

    // ── Recents ────────────────────────────────────────────────────────
    // Mixing a colour by hand is the expensive act, so what is worth keeping
    // is what you mixed — automatically, with no button to remember.
    readonly property var recentColors: {
        try { return JSON.parse(Persistent.states.draw.recentColors); }
        catch (e) { return []; }
    }

    function rememberRecent(c) {
        const h = root.hex(c);
        const list = root.recentColors.filter(x => x !== h);
        list.unshift(h);
        Persistent.states.draw.recentColors = JSON.stringify(list.slice(0, 8));
    }

    function forgetRecent(h) {
        Persistent.states.draw.recentColors =
            JSON.stringify(root.recentColors.filter(x => x !== String(h)));
    }

    // Commit to recents when a drag ENDS, not on every pixel: dragging across
    // the field would otherwise fill the row with eight shades of one gesture.
    function commitRecent() { root.rememberRecent(root.selectedColor) }

    implicitWidth: 320
    implicitHeight: layout.implicitHeight + 2 * root.panelPadding
    radius: Appearance.rounding.large
    color: Appearance.m3colors.m3surfaceContainerHigh
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    readonly property int panelPadding: 16
    readonly property int cardPadding: 12

    // ── Colour models ──────────────────────────────────────────────────
    // CSS wants rgb()/hsl(), and an alpha that cannot be copied is unusable
    // elsewhere. One cycling control: there are not four rows to spare.
    readonly property var formats: ["HEX", "RGB", "HSL"]
    property int formatIndex: 0
    readonly property string formatName: root.formats[root.formatIndex]

    function _i(v) { return Math.round(v * 255) }

    /// The current colour in the active format. Alpha is only included when it
    /// is actually doing something, so the common case stays short.
    function formatted() {
        const c = root.selectedColor;
        const a = root.selectedOpacity;
        const hasAlpha = a < 0.999;
        if (root.formatName === "RGB")
            return hasAlpha ? `rgba(${root._i(c.r)}, ${root._i(c.g)}, ${root._i(c.b)}, ${a.toFixed(2)})`
                            : `rgb(${root._i(c.r)}, ${root._i(c.g)}, ${root._i(c.b)})`;
        if (root.formatName === "HSL") {
            const h = Math.round((c.hslHue >= 0 ? c.hslHue : root.hueValue) * 360);
            const sl = Math.round(c.hslSaturation * 100);
            const l = Math.round(c.hslLightness * 100);
            return hasAlpha ? `hsla(${h}, ${sl}%, ${l}%, ${a.toFixed(2)})`
                            : `hsl(${h}, ${sl}%, ${l}%)`;
        }
        // HEX, with the 8-digit form when there is alpha to carry.
        return hasAlpha
            ? root.hex(c) + root._i(a).toString(16).padStart(2, "0")
            : root.hex(c);
    }

    /// Parse anything the formats above can produce, plus bare hex and #rgb.
    /// Used by the text field and by paste, so what the picker writes it can
    /// always read back.
    function parseColour(str) {
        const t = String(str).trim().toLowerCase();
        let m = t.match(/^#?([0-9a-f]{3})$/);
        if (m) {
            const d = m[1];
            return { c: "#" + d[0] + d[0] + d[1] + d[1] + d[2] + d[2], a: 1 };
        }
        m = t.match(/^#?([0-9a-f]{6})([0-9a-f]{2})?$/);
        if (m) return { c: "#" + m[1], a: m[2] ? parseInt(m[2], 16) / 255 : 1 };
        m = t.match(/^rgba?\(\s*(\d+)\D+(\d+)\D+(\d+)(?:\D+([\d.]+))?\s*\)$/);
        if (m) return {
            c: Qt.rgba(+m[1] / 255, +m[2] / 255, +m[3] / 255, 1),
            a: m[4] !== undefined ? Math.max(0, Math.min(1, +m[4])) : 1
        };
        m = t.match(/^hsla?\(\s*([\d.]+)\D+([\d.]+)%\D+([\d.]+)%(?:\D+([\d.]+))?\s*\)$/);
        if (m) return {
            c: Qt.hsla((+m[1] % 360) / 360, +m[2] / 100, +m[3] / 100, 1),
            a: m[4] !== undefined ? Math.max(0, Math.min(1, +m[4])) : 1
        };
        return null;
    }

    function applyParsed(str) {
        const r = root.parseColour(str);
        if (!r) return false;
        root.selectedOpacity = r.a;
        root.useColour(r.c);
        root.rememberRecent(root.selectedColor);
        return true;
    }

    // ── Contrast ───────────────────────────────────────────────────────
    // These get drawn ON screenshots, where legibility is the whole job.
    function _lin(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }

    function luminance(c) {
        return 0.2126 * root._lin(c.r) + 0.7152 * root._lin(c.g) + 0.0722 * root._lin(c.b);
    }

    function contrastWith(c, other) {
        const a = root.luminance(c), b = root.luminance(other);
        return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
    }

    readonly property real contrastOnWhite: root.contrastWith(root.selectedColor, "#ffffff")
    readonly property real contrastOnBlack: root.contrastWith(root.selectedColor, "#000000")
    /// The better of the two backgrounds, which is the one worth reporting:
    /// nobody draws on a screenshot that is both.
    readonly property real bestContrast: Math.max(root.contrastOnWhite, root.contrastOnBlack)

    // ── Harmonies and ramps ────────────────────────────────────────────
    // Generated from the current colour rather than stored, so they follow the
    // field as it moves. Every standard scheme a colour tool offers.
    readonly property var harmonies: [
        { id: "complement", name: "Complement", offsets: [0, 0.5] },
        { id: "analogous",  name: "Analogous",  offsets: [-0.083, -0.042, 0, 0.042, 0.083] },
        { id: "triadic",    name: "Triadic",    offsets: [0, 0.333, 0.667] },
        { id: "tetradic",   name: "Tetradic",   offsets: [0, 0.25, 0.5, 0.75] },
        { id: "split",      name: "Split",      offsets: [0, 0.417, 0.583] }
    ]
    property string harmonyId: "analogous"

    function harmonyColors() {
        const h = root.harmonies.find(x => x.id === root.harmonyId) ?? root.harmonies[1];
        return h.offsets.map(o => root.hex(
            Qt.hsva((root.hueValue + o + 1) % 1, root.satValue, root.valValue, 1)));
    }

    /// Tints up to white and shades down to black, through the current colour.
    function rampColors() {
        const out = [];
        for (let i = 0; i < 8; i++) {
            const t = i / 7;                     // 0 = lightest, 1 = darkest
            const sat = root.satValue * (t < 0.5 ? (0.35 + 1.3 * t) : 1);
            const val = 1 - t * 0.92;
            out.push(root.hex(Qt.hsva(root.hueValue, Math.min(1, sat), val, 1)));
        }
        return out;
    }

    // Which set of swatches the lower half shows. A segmented switch rather
    // than three stacked sections: stacked, the panel was taller than the
    // screen it has to sit above.
    property string swatchMode: "palette"

    StyledRectangularShadow { target: root }

    // Four identical round icon buttons in the header; declared once.
    component HeaderButton: RippleButton {
        // Not `icon`: Button already owns that name as a FINAL group property.
        property string symbolName: ""
        property string tip: ""
        signal triggered()
        implicitWidth: 28
        implicitHeight: 28
        buttonRadius: Appearance.rounding.full
        onClicked: triggered()
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: symbolName
            iconSize: 16
            color: Appearance.colors.colOnLayer1
        }
        StyledToolTip { text: tip }
    }

    // A checkerboard, so a colour with alpha reads as translucent rather than
    // as a slightly different colour. Drawn once and tiled by the two places
    // that show alpha.
    component Checker: Item {
        id: checkerRoot
        property real radius: 0

        Canvas {
            id: checkerCanvas
            anchors.fill: parent
            renderStrategy: Canvas.Cooperative
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                const s = 5;
                for (let y = 0; y < height; y += s)
                    for (let x = 0; x < width; x += s) {
                        const odd = ((x / s) + (y / s)) % 2 === 0;
                        ctx.fillStyle = odd ? "rgba(255,255,255,0.22)" : "rgba(0,0,0,0.22)";
                        ctx.fillRect(x, y, s, s);
                    }
            }
            layer.enabled: checkerRoot.radius > 0
            layer.smooth: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: checkerCanvas.width
                    height: checkerCanvas.height
                    radius: checkerRoot.radius
                }
            }
        }
    }

    ColumnLayout {
        id: layout
        // Deliberately NOT anchors.fill: the root's implicitHeight is derived
        // from this layout, and filling the parent closes that into a loop.
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.panelPadding
        spacing: 14

        // ── Header ─────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Bigger and rounder than the old 40px square: this is the one
            // element that answers "what am I about to draw with", so it gets
            // to be the largest thing in the header.
            Rectangle {
                implicitWidth: 44
                implicitHeight: 44
                radius: Appearance.rounding.normal
                color: "transparent"
                Checker {
                    anchors.fill: parent
                    radius: Appearance.rounding.normal
                    visible: root.selectedOpacity < 0.999
                }
                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.normal
                    color: Qt.rgba(root.selectedColor.r, root.selectedColor.g,
                                   root.selectedColor.b, root.selectedOpacity)
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    // Tap to cycle HEX → RGB → HSL. The label is the control,
                    // so the format costs no extra row.
                    RippleButton {
                        implicitHeight: 18
                        implicitWidth: fmtLabel.implicitWidth + 14
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: root.formatIndex = (root.formatIndex + 1) % root.formats.length
                        contentItem: StyledText {
                            id: fmtLabel
                            anchors.centerIn: parent
                            text: root.formatName
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledToolTip { text: Translation.tr("Switch colour format") }
                    }

                    // Legibility over a screenshot is the whole job, so the
                    // ratio lives in the header rather than behind anything.
                    Item { Layout.fillWidth: true }

                    Rectangle {
                        readonly property bool pass: root.bestContrast >= 4.5
                        implicitWidth: contrastLabel.implicitWidth + 14
                        implicitHeight: 18
                        radius: Appearance.rounding.full
                        color: pass ? Appearance.colors.colLayer2
                                    : ColorUtils.transparentize(Appearance.m3colors.m3error, 0.82)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        StyledText {
                            id: contrastLabel
                            anchors.centerIn: parent
                            text: root.bestContrast.toFixed(1) + ":1 "
                                  + (root.bestContrast >= 7 ? "AAA"
                                  : root.bestContrast >= 4.5 ? "AA"
                                  : root.bestContrast >= 3 ? "AA+" : "low")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.monospace
                            color: parent.pass ? Appearance.colors.colOnLayer2
                                               : Appearance.m3colors.m3error
                        }
                        StyledToolTip {
                            text: Translation.tr("Contrast against the better of white or black — how readable this will be on a screenshot")
                        }
                    }
                }

                // Accepts anything the formats above produce, so what it shows
                // you can always paste straight back in.
                StyledTextInput {
                    id: hexField
                    Layout.fillWidth: true
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                    // Only overwritten while not being typed into, or every
                    // keystroke would fight the binding.
                    text: hexField.activeFocus ? hexField.text : root.formatted()
                    onAccepted: {
                        root.applyParsed(text);
                        text = root.formatted();
                        focus = false;
                    }
                }
            }

            ColumnLayout {
                spacing: 2
                RowLayout {
                    spacing: 2
                    HeaderButton {
                        symbolName: "colorize"
                        tip: Translation.tr("Pick a colour from the screen")
                        enabled: !root.pickingFromScreen
                        onTriggered: root.pickFromScreen()
                    }
                    HeaderButton {
                        symbolName: "content_copy"
                        tip: Translation.tr("Copy in this format")
                        onTriggered: Quickshell.clipboardText = root.formatted()
                    }
                }
                RowLayout {
                    spacing: 2
                    HeaderButton {
                        symbolName: "content_paste"
                        tip: Translation.tr("Paste a colour")
                        onTriggered: root.applyParsed(Quickshell.clipboardText)
                    }
                    HeaderButton {
                        symbolName: "casino"
                        tip: Translation.tr("Random colour")
                        onTriggered: {
                            root.hueValue = Math.random();
                            root.satValue = 0.45 + Math.random() * 0.5;
                            root.valValue = 0.55 + Math.random() * 0.45;
                            root._applyHsv();
                            root.commitRecent();
                        }
                    }
                }
            }
        }

        // ── Mixer ──────────────────────────────────────────────────────
        // Field and rails inside one surface: they are one control, and on the
        // bare panel background they read as three unrelated bars.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: mixer.implicitHeight + 2 * root.cardPadding
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1

        ColumnLayout {
            id: mixer
            anchors { left: parent.left; right: parent.right; top: parent.top
                      margins: root.cardPadding }
            spacing: 10

        // ── Saturation × value field, over a hue rail ───────────────────
        // The standard arrangement, and the reason for the rework: the old
        // field was hue × lightness with saturation frozen, so grey, white and
        // deep shades could not be produced at all.
        // An Item, not the gradient Rectangle itself: the handle has to be a
        // sibling of the clipped artwork rather than a child of it, or picking
        // pure white parks it half outside the clip and the handle is sliced in
        // two at every edge of the field.
        Item {
            id: field
            Layout.fillWidth: true
            implicitHeight: 150

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.normal
                clip: true
                color: Qt.hsva(root.hueValue, 1, 1, 1)

                // White across (saturation), black down (value).
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#ffffffff" }
                        GradientStop { position: 1.0; color: "#00ffffff" }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#00000000" }
                        GradientStop { position: 1.0; color: "#ff000000" }
                    }
                }
            }

            MouseArea {
                id: fieldArea
                anchors.fill: parent
                onPressed: mouse => updateFrom(mouse.x, mouse.y)
                onPositionChanged: mouse => { if (pressed) updateFrom(mouse.x, mouse.y) }
                onReleased: root.commitRecent()
                function updateFrom(mx, my) {
                    root.satValue = Math.max(0, Math.min(1, mx / field.width));
                    root.valValue = 1 - Math.max(0, Math.min(1, my / field.height));
                    root._applyHsv();
                }
            }

            // Position derives FROM the colour, so the handle is always where
            // the current colour actually sits — including on reopen, which
            // the old one got wrong by parking the dot in the middle.
            Rectangle {
                id: handle
                width: 22
                height: 22
                radius: 11
                x: root.satValue * field.width - width / 2
                y: (1 - root.valValue) * field.height - height / 2
                color: root.selectedColor
                border.width: 2.5
                border.color: "#ffffff"
                scale: fieldArea.pressed ? 1.2 : 1.0
                Behavior on scale {
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
                // A white ring vanishes on a white field. The shadow, not a
                // second outline, is what keeps it findable in every corner.
                StyledRectangularShadow { target: handle }
            }
        }

        // Hue rail.
        Rectangle {
            id: hueRail
            Layout.fillWidth: true
            implicitHeight: 18
            radius: Appearance.rounding.full
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.000; color: "#ff0000" }
                GradientStop { position: 0.167; color: "#ffff00" }
                GradientStop { position: 0.333; color: "#00ff00" }
                GradientStop { position: 0.500; color: "#00ffff" }
                GradientStop { position: 0.667; color: "#0000ff" }
                GradientStop { position: 0.833; color: "#ff00ff" }
                GradientStop { position: 1.000; color: "#ff0000" }
            }

            Rectangle {
                id: hueThumb
                x: root.railX(hueRail.width, width, root.hueValue)
                anchors.verticalCenter: parent.verticalCenter
                width: root.railHandleWidth
                height: 24
                radius: Appearance.rounding.full
                color: Qt.hsva(root.hueValue, 1, 1, 1)
                border.width: 2.5
                border.color: "#ffffff"
                StyledRectangularShadow { target: hueThumb }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                onPressed: mouse => setFrom(mouse.x)
                onPositionChanged: mouse => { if (pressed) setFrom(mouse.x) }
                onReleased: root.commitRecent()
                function setFrom(mx) {
                    root.hueValue = Math.min(0.9999,
                        root.railFraction(hueRail.width, mx - 6));
                    root._applyHsv();
                }
            }
        }

        // Alpha rail, over a checkerboard so the effect is visible in the
        // control itself rather than only once you draw with it.
        Rectangle {
            id: alphaRail
            Layout.fillWidth: true
            implicitHeight: 18
            radius: Appearance.rounding.full
            color: "transparent"

            // Masked, not clipped, for the same reason as the header swatch -
            // and kept off the thumb, which stands proud of the rail and would
            // be sliced in half by clipping the whole item.
            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: alphaRail.width
                        height: alphaRail.height
                        radius: Appearance.rounding.full
                    }
                }
                Checker { anchors.fill: parent }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(root.selectedColor.r, root.selectedColor.g, root.selectedColor.b, 0) }
                    GradientStop { position: 1.0; color: Qt.rgba(root.selectedColor.r, root.selectedColor.g, root.selectedColor.b, 1) }
                }
            }
            }

            Rectangle {
                id: alphaThumb
                x: root.railX(alphaRail.width, width, root.selectedOpacity)
                anchors.verticalCenter: parent.verticalCenter
                width: root.railHandleWidth
                height: 24
                radius: Appearance.rounding.full
                color: root.selectedColor
                border.width: 2.5
                border.color: "#ffffff"
                StyledRectangularShadow { target: alphaThumb }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                onPressed: mouse => setFrom(mouse.x)
                onPositionChanged: mouse => { if (pressed) setFrom(mouse.x) }
                function setFrom(mx) {
                    root.selectedOpacity = root.railFraction(alphaRail.width, mx - 6);
                    root.emitColour();
                }
            }
        }
        }
        }

        // ── What the swatch area shows ─────────────────────────────────
        // Palettes, harmonies and a tint/shade ramp are three answers to the
        // same question, and stacking all three made the panel taller than the
        // screen it has to sit above. One at a time, switched here.
        // One track with an indicator that slides between the three, rather
        // than three separate pills. The movement is what tells you they are
        // alternatives to each other; three pills that merely change colour
        // read as three unrelated buttons.
        Item {
            id: segmented
            Layout.fillWidth: true
            implicitHeight: 34

            readonly property var modes: [
                { id: "palette", name: Translation.tr("Palette") },
                { id: "harmony", name: Translation.tr("Harmony") },
                { id: "shades",  name: Translation.tr("Shades") }
            ]
            readonly property int index:
                Math.max(0, segmented.modes.findIndex(m => m.id === root.swatchMode))
            readonly property real slotWidth: width / segmented.modes.length

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer1
            }

            Rectangle {
                width: segmented.slotWidth
                height: parent.height
                x: segmented.index * segmented.slotWidth
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimary
                Behavior on x {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasized
                    }
                }
            }

            Row {
                anchors.fill: parent
                Repeater {
                    model: segmented.modes
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: segmented.slotWidth
                        height: segmented.height
                        StyledText {
                            anchors.centerIn: parent
                            text: modelData.name
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: parent.index === segmented.index ? Font.Medium : Font.Normal
                            color: parent.index === segmented.index
                                ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                            Behavior on color { ColorAnimation { duration: 140 } }
                        }
                        TapHandler { onTapped: root.swatchMode = parent.modelData.id }
                    }
                }
            }
        }

        // ── Harmony scheme, when that is what is on screen ──────────────
        Flow {
            Layout.fillWidth: true
            spacing: 5
            visible: root.swatchMode === "harmony"
            Repeater {
                model: root.harmonies
                delegate: RippleButton {
                    required property var modelData
                    readonly property bool sel: modelData.id === root.harmonyId
                    implicitHeight: 24
                    implicitWidth: hName.implicitWidth + 20
                    buttonRadius: Appearance.rounding.full
                    colBackground: sel ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    colBackgroundHover: sel ? Appearance.colors.colPrimary : Appearance.colors.colLayer2Hover
                    onClicked: root.harmonyId = modelData.id
                    contentItem: StyledText {
                        id: hName
                        anchors.centerIn: parent
                        text: Translation.tr(modelData.name)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: parent.sel ? Appearance.colors.colOnPrimary
                                          : Appearance.colors.colOnLayer2
                    }
                }
            }
        }

        // ── Generated swatches: harmony or ramp ────────────────────────
        Flow {
            Layout.fillWidth: true
            spacing: 5
            visible: root.swatchMode !== "palette"
            Repeater {
                model: root.swatchMode === "harmony" ? root.harmonyColors()
                     : root.swatchMode === "shades"  ? root.rampColors() : []
                delegate: Rectangle {
                    id: gen
                    required property var modelData
                    width: root.swatchSize
                    height: root.swatchSize
                    radius: Appearance.rounding.small
                    color: modelData
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    scale: genHover.hovered ? 1.1 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    HoverHandler { id: genHover }
                    TapHandler {
                        onTapped: {
                            root.useColour(gen.modelData);
                            root.rememberRecent(gen.modelData);
                        }
                    }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: Quickshell.clipboardText = String(gen.modelData)
                    }
                }
            }
        }

        // ── Palette select ─────────────────────────────────────────────
        // Was a row of chips in a horizontal scroller with two icon buttons
        // wedged against its right edge. A scroller cuts a name off mid-word
        // the moment a palette has a long one, which is exactly what
        // "Studio copy" did — and the harder problem is that the row grows
        // with every palette while the panel width does not. A select does not
        // care how many there are, and its menu is where the palette actions
        // belong anyway.
        RippleButton {
            Layout.fillWidth: true
            visible: root.swatchMode === "palette"
            implicitHeight: 34
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer1
            colBackgroundHover: Appearance.colors.colLayer1Hover
            onClicked: {
                const p = mapToItem(root, 0, height + 4);
                paletteCtx.popup(p.x, p.y, root.paletteMenu());
            }
            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 10
                spacing: 8
                MaterialSymbol {
                    text: "palette"
                    iconSize: 16
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.activePalette?.name ?? ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                }
                MaterialSymbol {
                    text: "expand_more"
                    iconSize: 16
                    color: Appearance.colors.colSubtext
                }
            }
        }

        // ── Swatch grid ────────────────────────────────────────────────
        // Scrolls rather than grows: "Add a row" has no limit, and the picker
        // is anchored above a toolbar, so extra rows pushed it off-screen.
        StyledFlickable {
            id: gridFlick
            visible: root.swatchMode === "palette"
            Layout.fillWidth: true
            Layout.preferredHeight: visible
                ? Math.min(grid.implicitHeight, 4 * (root.swatchSize + 5) - 5) : 0
            contentHeight: grid.implicitHeight
            clip: true
            // Visible whenever there is more below, not only while hovered:
            // capping the grid at four rows hides the rest, and nothing else
            // on the panel says they are there.
            ScrollBar.vertical.policy: contentHeight > height ? ScrollBar.AlwaysOn
                                                              : ScrollBar.AlwaysOff

            GridLayout {
                id: grid
                // Explicit width, not Layout.fillWidth: inside a Flickable
                // nothing lays this out, so a layout-attached property here
                // would leave it zero-width and the grid invisible.
                width: gridFlick.width - (gridFlick.contentHeight > gridFlick.height ? 8 : 0)
                columns: root.gridColumns
                columnSpacing: 5
                rowSpacing: 5
                onWidthChanged: root.gridWidth = width

            Repeater {
                model: root.activePalette.colors
                delegate: Rectangle {
                    id: sw
                    required property var modelData
                    required property int index
                    readonly property bool active: Qt.colorEqual(modelData, root.selectedColor)
                    Layout.preferredWidth: root.swatchSize
                    Layout.preferredHeight: root.swatchSize
                    radius: Appearance.rounding.verysmall
                    color: modelData
                    scale: swHover.hovered ? 1.12 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    // A tick, not a ring: a ring around a swatch whose
                    // neighbour is the same colour is ambiguous about which
                    // one it belongs to, and this grid has near-duplicates by
                    // design.
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: sw.active
                        text: "check"
                        iconSize: 14
                        color: root.inkOn(sw.modelData)
                    }

                    HoverHandler { id: swHover }
                    TapHandler {
                        onTapped: {
                            root.useColour(sw.modelData);
                            root.rememberRecent(sw.modelData);
                        }
                    }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: ev => {
                            const p = sw.mapToItem(root, ev.position.x, ev.position.y);
                            paletteCtx.popup(p.x, p.y, root.menuForSwatch(sw.index, sw.modelData));
                        }
                    }
                }
            }
            }
        }

        // ── Recents ────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 5
            visible: root.recentColors.length > 0

            Flow {
                Layout.fillWidth: true
                spacing: 5

                StyledText {
                    // In the flow, not above it: a caption on its own line for
                    // a handful of swatches is a line the panel cannot spare.
                    height: 26
                    verticalAlignment: Text.AlignVCenter
                    rightPadding: 4
                    text: Translation.tr("Recent")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
                Repeater {
                    model: root.recentColors
                    delegate: Rectangle {
                        id: rc
                        required property var modelData
                        width: 26
                        height: 26
                        radius: Appearance.rounding.verysmall
                        color: modelData
                        scale: rcHover.hovered ? 1.12 : 1.0
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        HoverHandler { id: rcHover }
                        TapHandler { onTapped: root.useColour(rc.modelData) }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: root.forgetRecent(rc.modelData)
                        }
                        StyledToolTip { text: Translation.tr("Right-click to forget") }
                    }
                }
            }
        }
    }

    // Outside the ColumnLayout on purpose: PopupContextMenu anchors itself,
    // and anchors on a layout-managed item are undefined behaviour.
    PopupContextMenu { id: paletteCtx }
}
