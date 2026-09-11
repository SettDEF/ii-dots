pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Settings panel for the stats overlay.
 *
 * Separate from the overlay because the overlay is click-through by design —
 * it can never host its own controls. Placement is the exception: dragging is
 * a better way to position something than typing numbers, so that lives in
 * the overlay's edit mode and this panel just launches it.
 */
Scope {
    id: root

    readonly property var cfg: Config.options.statsHud

    // Which stat's unit dropdown is expanded inline (only one at a time).
    property string openUnit: ""

    // Uppercase group heading with a hairline above it.
    component SectionHeader: ColumnLayout {
        id: sh
        property string text: ""
        Layout.fillWidth: true
        Layout.topMargin: 10
        spacing: 7
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Qt.alpha(Appearance.colors.colOnLayer0, 0.08)
        }
        StyledText {
            text: sh.text
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.bold: true
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.5
            color: Appearance.colors.colSubtext
        }
    }

    // Clickable header + animated body. Children go into the body.
    component Collapsible: ColumnLayout {
        id: coll
        property string title: ""
        property bool expanded: false
        default property alias content: body.data
        Layout.fillWidth: true
        spacing: 4
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 28
            radius: Appearance.rounding.verysmall
            color: chHov.hovered ? Appearance.colors.colLayer1Hover : "transparent"
            HoverHandler { id: chHov; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: coll.expanded = !coll.expanded }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 2
                anchors.rightMargin: 6
                StyledText {
                    Layout.fillWidth: true
                    text: coll.title
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.bold: true
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.85
                }
                MaterialSymbol {
                    text: "expand_more"
                    iconSize: 18
                    color: Appearance.colors.colSubtext
                    rotation: coll.expanded ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 150 } }
                }
            }
        }
        Item {
            Layout.fillWidth: true
            clip: true
            implicitHeight: coll.expanded ? body.implicitHeight : 0
            Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            ColumnLayout {
                id: body
                width: parent.width
                spacing: 8
            }
        }
    }

    // One selectable stat chip with its unit sub-button.
    component StatChip: Rectangle {
        id: schip
        property string statId: ""
        readonly property var info: StatsHudBridge.statFor(schip.statId)
        readonly property bool on: StatsHudBridge.fields(Config.options.statsHud.layout).indexOf(schip.statId) >= 0
        property bool hovered: schipHov.hovered
        implicitHeight: 26
        implicitWidth: srow.implicitWidth + 16
        radius: height / 2
        color: schip.on ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
        Behavior on color { ColorAnimation { duration: 130 } }
        HoverHandler { id: schipHov; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            onTapped: {
                // On a preset, adopt its stats and switch to custom so the
                // tap actually changes what's shown.
                let cur;
                if (Config.options.statsHud.layout !== "custom") {
                    cur = StatsHudBridge.fields(Config.options.statsHud.layout).slice();
                    Config.options.statsHud.layout = "custom";
                } else {
                    cur = (Config.options.statsHud.fields ?? []).slice();
                }
                const i = cur.indexOf(schip.statId);
                if (i >= 0) cur.splice(i, 1); else cur.push(schip.statId);
                Config.options.statsHud.fields = cur;
            }
        }
        StyledToolTip {
            text: StatsHudBridge.formats[schip.statId]
                ? "Tap the unit to change it ("
                  + StatsHudBridge.formats[schip.statId].join(" / ") + ")"
                : schip.info.label
        }
        RowLayout {
            id: srow
            anchors.centerIn: parent
            spacing: 4
            MaterialSymbol {
                text: schip.info.icon; iconSize: 12
                color: schip.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
            }
            StyledText {
                text: schip.info.label
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: schip.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
            }
            // Inline unit dropdown: collapsed shows the current format; click
            // expands the segmented row in place (no popup), pick one to set it.
            Rectangle {
                id: unitDrop
                readonly property var opts: StatsHudBridge.formats[schip.statId] ?? []
                readonly property bool expanded: root.openUnit === schip.statId
                readonly property string cur: StatsHudBridge.unitOf(schip.statId)
                visible: opts.length > 0
                implicitHeight: 16
                implicitWidth: unitRow.implicitWidth + 8
                radius: 8
                clip: true
                color: Qt.alpha(schip.on ? Appearance.colors.colOnPrimary
                                         : Appearance.colors.colOnLayer1, unitDrop.expanded ? 0.28 : 0.18)
                Behavior on implicitWidth { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 130 } }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openUnit = unitDrop.expanded ? "" : schip.statId
                }
                Row {
                    id: unitRow
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    spacing: 3
                    Repeater {
                        model: unitDrop.opts
                        delegate: Rectangle {
                            id: opt
                            required property var modelData
                            readonly property bool isCur: modelData === unitDrop.cur
                            visible: unitDrop.expanded || opt.isCur
                            implicitHeight: 13
                            implicitWidth: oLabel.implicitWidth + 8
                            radius: 6
                            // Primary/on-primary is a guaranteed-contrast pair in
                            // any theme, so the current format is always legible —
                            // colOnLayer1 could sit too close to the chip fill.
                            color: opt.isCur ? (schip.on ? Appearance.colors.colOnPrimary
                                                         : Appearance.colors.colPrimary)
                                             : "transparent"
                            StyledText {
                                id: oLabel
                                anchors.centerIn: parent
                                text: opt.modelData
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: opt.isCur ? (schip.on ? Appearance.colors.colPrimary
                                                             : Appearance.colors.colOnPrimary)
                                                 : (schip.on ? Appearance.colors.colOnPrimary
                                                             : Appearance.colors.colOnLayer1)
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!unitDrop.expanded) root.openUnit = schip.statId;
                                    else { StatsHudBridge.setUnit(schip.statId, opt.modelData); root.openUnit = ""; }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // A labelled dropdown row for a single-choice setting. opts is a list of
    // { id, label }; current is the selected id; onPicked(id) fires on change.
    component LabeledDropdown: ColumnLayout {
        property string label: ""
        property var opts: []
        property string current: ""
        signal picked(string id)
        Layout.fillWidth: true
        spacing: 4
        StyledText {
            text: parent.label
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
        StyledComboBox {
            Layout.fillWidth: true
            // Neutral surface, not the themed accent container.
            colBackground: Appearance.colors.colLayer1
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colBackgroundActive: Appearance.colors.colLayer1Active
            model: parent.opts
            textRole: "label"
            currentIndex: Math.max(0, parent.opts.findIndex(o => o.id === parent.current))
            onActivated: idx => parent.picked(parent.opts[idx].id)
        }
    }

    IpcHandler {
        target: "statsHudSettings"
        function toggle(): void { GlobalStates.statsHudSettingsOpen = !GlobalStates.statsHudSettingsOpen }
        function open(): void   { GlobalStates.statsHudSettingsOpen = true }
        function close(): void  { GlobalStates.statsHudSettingsOpen = false }
    }

    GlobalShortcut {
        name: "statsHudSettingsToggle"
        description: "Toggle stats overlay settings"
        onPressed: GlobalStates.statsHudSettingsOpen = !GlobalStates.statsHudSettingsOpen
    }

    StackedPanelLoader {
        isOpen: GlobalStates.statsHudSettingsOpen

        sourceComponent: StackedSettingsPanel {
            id: win
            panelId: "statsHudSettings"
            title: Translation.tr("System Monitor")
            icon: "monitoring"
            onRequestClose: GlobalStates.statsHudSettingsOpen = false

            // Turning the overlay on when its settings open: configuring
            // something you cannot see is pointless.
            Component.onCompleted: GlobalStates.statsHudOpen = true
            Component.onDestruction: GlobalStates.statsHudEdit = false

            headerItems: [
                StyledSwitch {
                    checked: GlobalStates.statsHudOpen
                    onToggled: GlobalStates.statsHudOpen = checked
                }
            ]


            // ── Content ─────────────────────────────────────
            SectionHeader { text: "Content" }

            LabeledDropdown {
                label: "Layout"
                opts: [
                    { id: "bar",      label: "Bar — horizontal strip" },
                    { id: "stack",    label: "Stack — vertical column" },
                    { id: "compact",  label: "Compact — FPS only" },
                    { id: "detailed", label: "Detailed — with labels" },
                    { id: "custom",   label: "Custom — pick your own" }
                ]
                current: root.cfg.layout
                onPicked: id => Config.options.statsHud.layout = id
            }

            // ── Stat picker ─────────────────────────────────
            StyledText {
                text: "Stats  (" + StatsHudBridge.fields(root.cfg.layout).length + " shown"
                      + (root.cfg.layout === "custom" ? "" : " · preset") + ")"
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                Layout.fillWidth: true
            }
            Repeater {
                model: StatsHudBridge.categories
                delegate: ColumnLayout {
                    id: cat
                    required property var modelData
                    // Only stats that actually exist in the catalogue.
                    readonly property var ids: (modelData.ids ?? [])
                        .filter(id => StatsHudBridge.catalogue.indexOf(id) >= 0)
                    readonly property int activeCount: cat.ids.filter(
                        id => StatsHudBridge.fields(root.cfg.layout).indexOf(id) >= 0).length
                    property bool expanded: false
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 4
                    visible: cat.ids.length > 0

                    // Collapsible header — click to expand the chips below.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: Appearance.rounding.verysmall
                        color: hdrHov.hovered ? Appearance.colors.colLayer1Hover : "transparent"
                        HoverHandler { id: hdrHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: cat.expanded = !cat.expanded }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 2
                            anchors.rightMargin: 6
                            spacing: 6
                            StyledText {
                                text: cat.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.bold: true
                                color: Appearance.colors.colOnLayer0
                                opacity: 0.85
                            }
                            Rectangle {
                                visible: cat.activeCount > 0
                                implicitWidth: cntTxt.implicitWidth + 10
                                implicitHeight: 15
                                radius: 7
                                color: Appearance.colors.colPrimary
                                StyledText {
                                    id: cntTxt
                                    anchors.centerIn: parent
                                    text: cat.activeCount
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.bold: true
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                            Item { Layout.fillWidth: true }
                            MaterialSymbol {
                                text: "expand_more"
                                iconSize: 18
                                color: Appearance.colors.colSubtext
                                rotation: cat.expanded ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 150 } }
                            }
                        }
                    }
                    // Collapsible chip area — height animates from 0.
                    Item {
                        Layout.fillWidth: true
                        clip: true
                        implicitHeight: cat.expanded ? chipFlow.implicitHeight : 0
                        Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Flow {
                            id: chipFlow
                            width: parent.width
                            spacing: 5
                            Repeater {
                                model: cat.ids
                                delegate: StatChip {
                                    required property var modelData
                                    statId: modelData
                                }
                            }
                        }
                    }
                }
            }
            // ── Position ────────────────────────────────────
            SectionHeader { text: "Position" }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                LabeledDropdown {
                    Layout.fillWidth: true
                    label: "Placement"
                    opts: [
                        { id: "top-left",     label: "Top left" },
                        { id: "top-right",    label: "Top right" },
                        { id: "bottom-left",  label: "Bottom left" },
                        { id: "bottom-right", label: "Bottom right" }
                    ]
                    current: root.cfg.position
                    onPicked: id => Config.options.statsHud.position = id
                }
                RippleButton {
                    Layout.alignment: Qt.AlignBottom
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.small
                    colBackground: GlobalStates.statsHudEdit
                        ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
                    onClicked: GlobalStates.statsHudEdit = !GlobalStates.statsHudEdit
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: GlobalStates.statsHudEdit ? "check" : "drag_indicator"
                        iconSize: 18
                        color: GlobalStates.statsHudEdit
                            ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                    }
                    StyledToolTip {
                        text: GlobalStates.statsHudEdit
                            ? "Finish placing" : "Drag to place freely"
                    }
                }
            }

            // Placement-only helpers, folded away until needed.
            Collapsible {
                title: "Snapping & grid"
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StyledSwitch {
                        checked: root.cfg.snapGrid
                        onToggled: Config.options.statsHud.snapGrid = checked
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Snap to edges & centre"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer0
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StyledSwitch {
                        checked: root.cfg.snapDots
                        onToggled: Config.options.statsHud.snapDots = checked
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Snap to grid dots"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer0
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StyledSwitch {
                        checked: root.cfg.showGrid
                        onToggled: Config.options.statsHud.showGrid = checked
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Show grid while placing"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer0
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.cfg.showGrid || root.cfg.snapDots
                    spacing: 8
                    StyledText {
                        text: "Grid size"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledSlider {
                        Layout.fillWidth: true
                        from: 8; to: 120
                        value: root.cfg.gridSize
                        onMoved: Config.options.statsHud.gridSize = Math.round(value)
                    }
                    StyledText {
                        text: root.cfg.gridSize + "px"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colPrimary
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.cfg.snapGrid || root.cfg.snapDots
                    spacing: 8
                    StyledText {
                        text: "Snap strength"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledSlider {
                        Layout.fillWidth: true
                        from: 2; to: 60
                        value: root.cfg.snapPx
                        onMoved: Config.options.statsHud.snapPx = Math.round(value)
                    }
                    StyledText {
                        text: root.cfg.snapPx + "px"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colPrimary
                    }
                }
            }

            // ── Appearance ──────────────────────────────────
            SectionHeader { text: "Appearance" }

            LabeledDropdown {
                label: "Display mode"
                opts: [
                    { id: "always", label: "Always — floating, click-through" },
                    { id: "peek",   label: "Peek — opens on hover" },
                    { id: "dock",   label: "Dock — full-width edge strip" }
                ]
                current: Config.options.statsHud.mode ?? "always"
                onPicked: id => Config.options.statsHud.mode = id
            }

            RowLayout {
                Layout.fillWidth: true
                visible: (Config.options.statsHud.mode ?? "always") === "dock"
                spacing: 8
                StyledSwitch {
                    checked: Config.options.statsHud.dockReserve
                    onToggled: Config.options.statsHud.dockReserve = checked
                }
                StyledText {
                    Layout.fillWidth: true
                    text: "Reserve space (windows tile around it)"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer0
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                StyledText {
                    text: "Opacity"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer0
                }
                StyledSlider {
                    Layout.fillWidth: true
                    from: 0.0; to: 1.0
                    value: root.cfg.opacity
                    onMoved: Config.options.statsHud.opacity = value
                }
                StyledText {
                    text: Math.round(root.cfg.opacity * 100) + "%"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colPrimary
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                StyledSwitch {
                    checked: root.cfg.showIcons
                    onToggled: Config.options.statsHud.showIcons = checked
                }
                StyledText {
                    Layout.fillWidth: true
                    text: "Show icons"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer0
                }
            }

            // ── Sources ─────────────────────────────────────
            SectionHeader { text: "Sources" }

            // ── Network interface ───────────────────────────
            LabeledDropdown {
                label: "Network interface"
                opts: [{ id: "", label: "Auto — busiest interface" }]
                    .concat((SysStats.interfaces ?? []).map(n => ({ id: n, label: n })))
                current: root.cfg.iface ?? ""
                onPicked: id => Config.options.statsHud.iface = id
            }

            // ── This app ────────────────────────────────────
            // A profile is "whatever is on screen right now,
            // remembered for this app" — building one by ticking
            // boxes in the abstract is far more work than setting
            // it up once and pressing save.
            Rectangle {
                Layout.fillWidth: true
                visible: StatsHudBridge.focusedApp.length > 0
                implicitHeight: appCol.implicitHeight + 18
                radius: Appearance.rounding.small
                color: StatsHudBridge.profileActive
                    ? Qt.alpha(Appearance.colors.colPrimary, 0.14)
                    : Qt.alpha(Appearance.colors.colOnLayer0, 0.06)
                ColumnLayout {
                    id: appCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 9
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        MaterialSymbol {
                            text: "apps"; iconSize: 14
                            color: StatsHudBridge.profileActive
                                ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: StatsHudBridge.focusedApp
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.bold: true
                            color: Appearance.colors.colOnLayer0
                            elide: Text.ElideRight
                        }
                        StyledText {
                            text: StatsHudBridge.profileActive ? "has profile" : "using defaults"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: StatsHudBridge.profileActive
                                ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        RippleButton {
                            Layout.fillWidth: true
                            implicitHeight: 28
                            colBackground: Appearance.colors.colLayer1
                            contentItem: StyledText {
                                anchors.centerIn: parent
                                text: "Save current for this app"
                                font.pixelSize: 11
                                color: Appearance.colors.colOnLayer1
                            }
                            onClicked: StatsHudBridge.saveAppProfile(
                                StatsHudBridge.focusedApp, {
                                    layout: root.cfg.layout,
                                    position: root.cfg.position,
                                    opacity: root.cfg.opacity,
                                    showIcons: root.cfg.showIcons,
                                    fields: root.cfg.fields
                                })
                        }
                        RippleButton {
                            visible: StatsHudBridge.profileActive
                            implicitWidth: 34
                            implicitHeight: 28
                            colBackground: Appearance.colors.colLayer1
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "delete"; iconSize: 14
                                color: Appearance.m3colors.m3error
                            }
                            onClicked: StatsHudBridge.clearAppProfile(StatsHudBridge.focusedApp)
                        }
                    }
                }
            }

            // ── FPS source ──────────────────────────────────
            // Stated plainly, because the honest answer is that a
            // game's frame rate is unobservable from outside its
            // process — and a HUD that quietly shows the panel's
            // refresh rate instead would be lying.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: fpsCol.implicitHeight + 18
                radius: Appearance.rounding.small
                color: SysStats.fpsAvailable
                    ? Qt.alpha(Appearance.colors.colPrimary, 0.14)
                    : Qt.alpha(Appearance.colors.colOnLayer0, 0.06)
                ColumnLayout {
                    id: fpsCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 9
                    spacing: 3
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        MaterialSymbol {
                            text: SysStats.fpsAvailable ? "sports_esports" : "info"
                            iconSize: 14
                            color: SysStats.fpsAvailable
                                ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: SysStats.fpsAvailable
                                ? ("Game FPS from " + (SysStats.fpsApp || "a Vulkan layer"))
                                : "No game FPS source"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.bold: true
                            color: SysStats.fpsAvailable
                                ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: !SysStats.fpsAvailable
                        text: "A game's frame rate only exists inside its process, so it "
                            + "needs a Vulkan layer. Run  statshud-fps-setup  in a "
                            + "terminal for the one command and the launch option."
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Panel refresh: " + Math.round(SysStats.refreshHz) + " Hz"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 32
                colBackground: Appearance.colors.colLayer1
                contentItem: StyledText {
                    anchors.centerIn: parent
                    text: "Close"
                    font.pixelSize: 11
                    color: Appearance.colors.colOnLayer1
                }
                onClicked: GlobalStates.statsHudSettingsOpen = false
            }
        }
    }
}
