// Colour picker styled after Zen Browser's workspace theme picker: a dotted
// field with a white-ringed draggable dot, a swatch grid with palette tabs
// below it, and an opacity slider.
//
// Properties:
//   selectedColor   — current colour (hue/lightness from the field)
//   selectedOpacity — alpha applied to the emitted colour
//
// Signal:
//   picked(color c) — fires on every field drag, swatch tap and opacity change
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import QtQuick.Layouts

Rectangle {
    id: root

    property color selectedColor: "#ff5a5a"
    property real selectedOpacity: 1.0

    signal picked(color c)

    // The three curated sets from WAVR's track palettes, 8 per row.
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
            "#c9c9cd","#bcbcc0","#aeaeb4","#a1a1a8","#93939c","#868690","#787884","#6b6b78",
            "#6e5f5f","#6a6e5f","#5f6e6a","#5f5f6e","#3a3a3e","#333335","#2c2c2e","#262628",
            "#ffffff","#e0e0e0","#c8ccd2","#9aa0aa","#7a8aa0","#5a5a5a","#3a3a3a","#000000"] }
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

    function saveCustom(list) {
        Persistent.states.draw.customPalettes = JSON.stringify(list);
    }

    function newPalette() {
        const list = root.customPalettes.slice();
        const palette = {
            id: "custom-" + Date.now(),
            name: "Custom " + (list.length + 1),
            colors: []
        };
        list.push(palette);
        root.saveCustom(list);
        Persistent.states.draw.activePalette = palette.id;
    }

    function addToActive(c) {
        if (!root.activeIsCustom) return;
        const hex = String(c);
        const list = root.customPalettes.slice();
        const target = list.find(p => p.id === root.activeId);
        if (target && !target.colors.includes(hex)) {
            target.colors.push(hex);
            root.saveCustom(list);
        }
    }

    // Hues are spread rather than harmonised: these colours exist to be told
    // apart, so a harmonious set defeats the point.
    function hex(c) {
        const f = v => Math.round(v * 255).toString(16).padStart(2, "0");
        return "#" + f(c.r) + f(c.g) + f(c.b);
    }

    function generate(method, seed) {
        const out = [];
        const baseHue = seed.hslHue >= 0 ? seed.hslHue : 0;
        const baseSat = seed.hslSaturation;
        const lights = [0.72, 0.58, 0.40];
        for (let row = 0; row < 3; row++) {
            for (let i = 0; i < 8; i++) {
                let hue = (baseHue + i / 8) % 1;
                let sat = Math.max(0.25, Math.min(0.85, baseSat));
                if (method === "shuffle") {
                    hue = (hue + Math.random() * 0.06 - 0.03 + 1) % 1;
                    sat = 0.35 + Math.random() * 0.45;
                } else if (method === "pastel") {
                    sat = 0.32;
                }
                out.push(root.hex(Qt.hsla(hue, sat, lights[row], 1)));
            }
        }
        return out;
    }

    function applyMethod(method) {
        if (!root.activeIsCustom) return;
        const list = root.customPalettes.slice();
        const target = list.find(p => p.id === root.activeId);
        if (!target) return;
        const seed = method === "shuffle"
            ? Qt.hsla(Math.random(), 0.6, 0.6, 1)
            : root.selectedColor;
        target.colors = root.generate(method, seed);
        root.saveCustom(list);
    }

    function removeFromActive(hex) {
        if (!root.activeIsCustom) return;
        const list = root.customPalettes.slice();
        const target = list.find(p => p.id === root.activeId);
        if (target) {
            target.colors = target.colors.filter(x => x !== String(hex));
            root.saveCustom(list);
        }
    }

    function deletePalette(id) {
        root.saveCustom(root.customPalettes.filter(p => p.id !== id));
        Persistent.states.draw.activePalette = "studio";
    }

    // ── Editing ────────────────────────────────────────────────────────
    // The three built-ins are read-only. Rather than refuse an edit on one,
    // fork it into a custom copy and apply the edit there, so every entry in
    // the grid is editable from the context menu.
    readonly property int gridColumns: 8

    function forkActive() {
        const src = root.activePalette;
        const list = root.customPalettes.slice();
        const palette = {
            id: "custom-" + Date.now(),
            name: (src.name || "Palette") + " copy",
            colors: (src.colors || []).slice()
        };
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
        const light = [0.72, 0.58, 0.40, 0.26][row % 4];
        const seed = root.selectedColor;
        const baseHue = seed.hslHue >= 0 ? seed.hslHue : 0;
        const sat = Math.max(0.25, Math.min(0.85, seed.hslSaturation));
        for (let i = 0; i < root.gridColumns; i++)
            e.target.colors.push(root.hex(Qt.hsla((baseHue + i / root.gridColumns) % 1, sat, light, 1)));
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

    function menuForSwatch(index, hex) {
        const items = [{
            icon: "colorize", label: Translation.tr("Use this colour"),
            onTriggered: () => { root.selectedColor = hex; root.emitColour(); }
        }, {
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
                icon: "content_copy", label: Translation.tr("Duplicate palette to edit"),
                onTriggered: () => root.forkActive()
            });
        return items;
    }

    implicitWidth: 300
    implicitHeight: layout.implicitHeight + 24
    radius: Appearance.rounding.normal
    color: Appearance.m3colors.m3surfaceContainerHigh
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    function emitColour() {
        root.picked(Qt.rgba(root.selectedColor.r, root.selectedColor.g,
                            root.selectedColor.b, root.selectedOpacity));
    }

    ColumnLayout {
        id: layout
        // Deliberately NOT anchors.fill: the root's implicitHeight is derived
        // from this layout, and filling the parent closes that into a loop.
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 10

        // ── Field: hue across, lightness down, with Zen's dotted overlay.
        Rectangle {
            id: field
            Layout.fillWidth: true
            implicitHeight: 140
            radius: Appearance.rounding.small
            clip: true
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.00; color: "#ff5a5a" }
                GradientStop { position: 0.17; color: "#e8c23f" }
                GradientStop { position: 0.33; color: "#5fcf6a" }
                GradientStop { position: 0.50; color: "#3fc4d4" }
                GradientStop { position: 0.67; color: "#4a7fe0" }
                GradientStop { position: 0.83; color: "#b06cd0" }
                GradientStop { position: 1.00; color: "#e0533a" }
            }

            // Vertical light→dark wash, so the field spans lightness too.
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.55) }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.65) }
                }
            }

            // Zen's dot texture: 1px dots on a 6px grid.
            Canvas {
                id: texture
                anchors.fill: parent
                opacity: 0.35
                renderStrategy: Canvas.Cooperative
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.fillStyle = "rgba(255,255,255,0.30)";
                    for (let x = 3; x < width; x += 6)
                        for (let y = 3; y < height; y += 6)
                            ctx.fillRect(x, y, 1, 1);
                }
            }

            MouseArea {
                id: fieldArea
                anchors.fill: parent
                onPressed: mouse => updateFrom(mouse.x, mouse.y)
                onPositionChanged: mouse => { if (pressed) updateFrom(mouse.x, mouse.y) }
                function updateFrom(mx, my) {
                    const px = Math.max(0, Math.min(field.width, mx));
                    const py = Math.max(0, Math.min(field.height, my));
                    dot.x = px;
                    dot.y = py;
                    const hue = px / field.width;
                    const light = 1.0 - (py / field.height) * 0.85;
                    root.selectedColor = Qt.hsla(hue, 0.62, Math.max(0.12, light), 1);
                    root.emitColour();
                }
            }

            // Zen's dot: round, thick white ring, grows while dragging.
            Rectangle {
                id: dot
                width: 38; height: 38; radius: 19
                x: field.width / 2; y: field.height / 2
                transform: Translate { x: -dot.width / 2; y: -dot.height / 2 }
                color: root.selectedColor
                border.width: 6
                border.color: "#ffffff"
                scale: fieldArea.pressed ? 1.2 : (dotHover.hovered ? 1.05 : 1.0)
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                HoverHandler { id: dotHover }
            }
        }

        // ── Palette tabs
        RowLayout {
            Layout.fillWidth: true
            spacing: 2
            Repeater {
                model: root.allPalettes
                Rectangle {
                    required property int index
                    required property var modelData
                    readonly property bool active: modelData.id === root.activeId
                    readonly property bool isCustom: !root.palettes.some(p => p.id === modelData.id)
                    implicitWidth: tabLabel.implicitWidth + 16
                    implicitHeight: 22
                    radius: 4
                    color: active ? Qt.alpha(Appearance.m3colors.m3onSurface, 0.16)
                                  : (tabHover.hovered ? Qt.alpha(Appearance.m3colors.m3onSurface, 0.10)
                                                      : "transparent")
                    Behavior on color { ColorAnimation { duration: 150 } }
                    StyledText {
                        id: tabLabel
                        anchors.centerIn: parent
                        text: modelData.name
                        font.pixelSize: 12
                        color: Appearance.m3colors.m3onSurface
                        // Tela fades the label rather than recolouring it.
                        opacity: active ? 1.0 : (tabHover.hovered ? 0.9 : 0.6)
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                    HoverHandler { id: tabHover }
                    TapHandler { onTapped: Persistent.states.draw.activePalette = modelData.id }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: { if (isCustom) root.deletePalette(modelData.id) }
                    }
                }
            }

            // New palette
            Rectangle {
                implicitWidth: 22; implicitHeight: 22
                radius: 4
                color: newHover.hovered ? Qt.alpha(Appearance.m3colors.m3onSurface, 0.10) : "transparent"
                border.width: 1
                border.color: Qt.alpha(Appearance.m3colors.m3onSurface, 0.35)
                Behavior on color { ColorAnimation { duration: 150 } }
                StyledText {
                    anchors.centerIn: parent
                    text: "+"
                    font.pixelSize: 13
                    color: Appearance.m3colors.m3onSurface
                }
                HoverHandler { id: newHover }
                TapHandler { onTapped: root.newPalette() }
            }
        }

        // ── Swatch grid — WAVR's metrics: 20px cells, 4px gutters, 4px
        // corners, white ring on the active one. Right-click edits.
        GridLayout {
            Layout.fillWidth: true
            columns: root.gridColumns
            columnSpacing: 4
            rowSpacing: 4
            Repeater {
                model: root.activePalette.colors
                Rectangle {
                    id: sw
                    required property var modelData
                    required property int index
                    readonly property bool active: Qt.colorEqual(modelData, root.selectedColor)
                    implicitWidth: 20; implicitHeight: 20
                    radius: 4
                    color: modelData
                    border.width: 1
                    border.color: sw.active ? "#ffffff" : "transparent"
                    scale: swHover.hovered ? 1.12 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    // WAVR rings the active swatch in the surface colour so the
                    // white border reads against a same-coloured neighbour.
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 4
                        height: parent.height + 4
                        radius: 6
                        z: -1
                        color: "transparent"
                        border.width: 1
                        border.color: sw.active ? root.color : "transparent"
                    }
                    HoverHandler { id: swHover }
                    TapHandler {
                        onTapped: {
                            root.selectedColor = sw.modelData;
                            root.emitColour();
                        }
                    }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: (ev) => {
                            const p = sw.mapToItem(root, ev.position.x, ev.position.y);
                            paletteCtx.popup(p.x, p.y, root.menuForSwatch(sw.index, sw.modelData));
                        }
                    }
                }
            }

            // Append-a-row affordance, sitting in the next free cell.
            Rectangle {
                implicitWidth: 20; implicitHeight: 20
                radius: 4
                color: rowAddHover.hovered
                    ? Qt.alpha(Appearance.m3colors.m3onSurface, 0.10) : "transparent"
                border.width: 1
                border.color: Qt.alpha(Appearance.m3colors.m3onSurface, 0.35)
                Behavior on color { ColorAnimation { duration: 150 } }
                StyledText {
                    anchors.centerIn: parent
                    text: "+"
                    font.pixelSize: 13
                    color: Appearance.m3colors.m3onSurface
                }
                HoverHandler { id: rowAddHover }
                TapHandler { onTapped: root.addRowToActive() }
                StyledToolTip { text: Translation.tr("Add a row of 8") }
            }
        }

        // ── Generators: fill a custom palette from the field's colour.
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: root.activeIsCustom

            Repeater {
                model: [
                    { label: "Spread", id: "spread" },
                    { label: "Pastel", id: "pastel" },
                    { label: "Shuffle", id: "shuffle" }
                ]
                Rectangle {
                    required property var modelData
                    implicitWidth: methodLabel.implicitWidth + 16
                    implicitHeight: 22
                    radius: Appearance.rounding.verysmall
                    color: mHover.hovered ? Qt.alpha(Appearance.m3colors.m3onSurface, 0.16)
                                          : Qt.alpha(Appearance.m3colors.m3onSurface, 0.08)
                    Behavior on color { ColorAnimation { duration: 140 } }
                    StyledText {
                        id: methodLabel
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pixelSize: 11
                        color: Appearance.m3colors.m3onSurface
                    }
                    HoverHandler { id: mHover }
                    TapHandler { onTapped: root.applyMethod(modelData.id) }
                }
            }

            Item { Layout.fillWidth: true }
        }

        // ── Custom colours: whatever the field produced, kept for reuse.
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: root.customColors
                Rectangle {
                    required property var modelData
                    implicitWidth: 20; implicitHeight: 20
                    radius: 4
                    color: modelData
                    border.width: 1
                    border.color: "transparent"
                    scale: cusHover.hovered ? 1.12 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    HoverHandler { id: cusHover }
                    TapHandler {
                        onTapped: {
                            root.selectedColor = modelData;
                            root.emitColour();
                        }
                    }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: root.removeCustom(modelData)
                    }
                }
            }

            Rectangle {
                implicitWidth: 20; implicitHeight: 20
                radius: 4
                color: addHover.hovered ? Qt.alpha(Appearance.m3colors.m3onSurface, 0.10) : "transparent"
                border.width: 1
                border.color: Qt.alpha(Appearance.m3colors.m3onSurface, 0.35)
                Behavior on color { ColorAnimation { duration: 150 } }
                StyledText {
                    anchors.centerIn: parent
                    text: "+"
                    font.pixelSize: 14
                    color: Appearance.m3colors.m3onSurface
                }
                HoverHandler { id: addHover }
                TapHandler { onTapped: root.addCustom(root.selectedColor) }
            }

            Item { Layout.fillWidth: true }
        }

        // ── Opacity
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            StyledText {
                text: "Opacity"
                font.pixelSize: 12
                color: Qt.alpha(Appearance.m3colors.m3onSurface, 0.7)
            }
            Rectangle {
                id: track
                Layout.fillWidth: true
                implicitHeight: 6
                radius: 3
                color: Qt.alpha(Appearance.m3colors.m3onSurface, 0.15)

                Rectangle {
                    width: parent.width * root.selectedOpacity
                    height: parent.height
                    radius: parent.radius
                    color: root.selectedColor
                }

                Rectangle {
                    x: track.width * root.selectedOpacity - width / 2
                    y: (track.height - height) / 2
                    width: 14; height: 14; radius: 7
                    color: root.selectedColor
                    border.width: 3
                    border.color: "#ffffff"
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    onPressed: mouse => setFrom(mouse.x)
                    onPositionChanged: mouse => { if (pressed) setFrom(mouse.x) }
                    function setFrom(mx) {
                        root.selectedOpacity = Math.max(0, Math.min(1, mx / track.width));
                        root.emitColour();
                    }
                }
            }
        }
    }

    // Outside the ColumnLayout on purpose: PopupContextMenu anchors itself,
    // and anchors on a layout-managed item are undefined behaviour.
    PopupContextMenu { id: paletteCtx }
}
