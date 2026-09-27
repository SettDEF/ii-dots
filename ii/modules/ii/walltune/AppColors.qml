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

// Per-application colours — a popup belonging to WallTune.
//
// WallTune tunes the wallpaper, and everything downstream gets one palette.
// This tunes what happens *after* that: each app in tinct's config can take
// the base palette and shift it, render it in the other mode, or have a role
// pinned outright. Terminals want more contrast than a bar; one app always
// wants its brand colour left alone.
//
// Shaped like the connectivity popup rather than the settings panels: a
// floating card that dismisses when you click away. It belongs to WallTune —
// you open it from there, glance, adjust, and it goes — so docking it into
// the panel stack would have made it a place you navigate to instead.
//
// Every control writes to ~/.config/tinct/config.toml through `tinct app`, so
// nothing lives in the shell and hand-editing that file stays first-class.
Scope {
    id: scope

    // Same treatment every other surface here gets: openable without a
    // keybind, so scripts and `qs ipc` can reach it.
    IpcHandler {
        target: "appColors"
        function toggle(): void { GlobalStates.appColorsOpen = !GlobalStates.appColorsOpen }
        function open(): void { GlobalStates.appColorsOpen = true }
        function close(): void { GlobalStates.appColorsOpen = false }
    }

    // A selectable pill. There are enough of these that they'd otherwise be
    // eight copies of the same Rectangle.
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool selected: false
        signal picked

        implicitWidth: chipText.implicitWidth + 18
        implicitHeight: 26
        radius: Appearance.rounding.small
        color: chip.selected ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
        Behavior on color { ColorAnimation { duration: 120 } }
        StyledText {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: chip.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        }
        HoverHandler { margin: Appearance.sizes.touchSlop; cursorShape: Qt.PointingHandCursor }
        TapHandler { margin: Appearance.sizes.touchSlop; onTapped: chip.picked() }
    }

    // A one-of-many setting as a dropdown instead of a chip flow.
    //
    // Scheme alone is ten options; with Style, Colour theory and Practical it
    // came to twenty-five chips over eight rows, and all four are settings you
    // pick once and leave. Spending half the popup on them pushed the sliders
    // and the resulting palette -- the things you actually iterate on -- below
    // the fold. A labelled row each says the same thing in one line.
    component Picker: RowLayout {
        id: pick
        property string label: ""
        property string section: "adjust"
        property string akey: ""
        property var options: []
        property string defaultLabel: qsTr("None")

        readonly property var entries: (pick.options ?? []).map(o => ({
            id: o,
            label: o === "" ? pick.defaultLabel : o
        }))

        Layout.fillWidth: true
        visible: TinctApps.selected !== ""
        spacing: 8

        StyledText {
            Layout.preferredWidth: 104
            text: pick.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer0
        }
        StyledComboBoxSearch {
            Layout.fillWidth: true
            implicitHeight: 34
            model: pick.entries
            textRole: "label"
            colBackground: Appearance.colors.colLayer2
            // Falls back to index 0 (the "" default) when the config carries a
            // value this build does not list, rather than showing a blank box.
            currentIndex: Math.max(0, pick.entries.findIndex(e =>
                e.id === TinctApps.valueOf(pick.section, pick.akey, "")))
            onActivated: idx => TinctApps.set(pick.section, pick.akey, pick.entries[idx].id)
        }
    }

    // A slider that can also be *unset*. An override that isn't there is not
    // the same as one parked in the middle, and the row has to be able to say
    // so — otherwise "reset" and "centre" look identical.
    component Adjust: ColumnLayout {
        id: adj
        property string label: ""
        property string akey: ""
        // `adjust` for the palette-wide nudges, `render` for contrast, which
        // re-runs the scheme rather than shifting the colours it produced.
        property string section: "adjust"
        property real from: 0
        property real to: 100
        property real fallback: 50
        /// Contrast is a fraction; the rest are whole degrees and percents.
        property int decimals: 0
        readonly property bool isSet: TinctApps.valueOf(adj.section, adj.akey, undefined) !== undefined

        Layout.fillWidth: true
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            StyledText {
                text: adj.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer0
            }
            Item { Layout.fillWidth: true }
            StyledText {
                text: adj.isSet
                    ? TinctApps.numberOf(adj.section, adj.akey, adj.fallback).toFixed(adj.decimals)
                    : "—"
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: Appearance.font.family.monospace
                color: adj.isSet ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            MaterialSymbol {
                text: "backspace"
                iconSize: 14
                visible: adj.isSet
                color: Appearance.colors.colSubtext
                HoverHandler { margin: Appearance.sizes.touchSlop; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    margin: Appearance.sizes.touchSlop
                    onTapped: TinctApps.clear(adj.section, adj.akey)
                }
            }
        }
        StyledSlider {
            Layout.fillWidth: true
            from: adj.from
            to: adj.to
            value: TinctApps.numberOf(adj.section, adj.akey, adj.fallback)
            // Queued, not written: a drag would otherwise spawn a process per
            // frame. TinctApps coalesces and flushes once.
            onMoved: TinctApps.queue(adj.section, adj.akey, value.toFixed(adj.decimals))
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: win.modelData
            visible: GlobalStates.appColorsOpen

            exclusiveZone: 0
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:appColors"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors { top: true; bottom: true; left: true; right: true }

            // The scrim covers the screen and takes clicks too, so this is a
            // real modal: tapping anywhere outside the card closes it. That
            // replaces the old dismiss path — with a click-capturing scrim,
            // no click ever reaches the compositor for GlobalFocusGrab to
            // notice — so the grab is kept only for Esc and for the case
            // where something else grabs focus first.
            mask: Region {
                item: scrim
                Region { item: card; intersection: Intersection.Combine }
            }

            onVisibleChanged: {
                if (win.visible) {
                    GlobalFocusGrab.addDismissable(win);
                    // The config may have been hand-edited, or the wallpaper
                    // changed, since this was last open.
                    TinctApps.reload();
                } else {
                    GlobalFocusGrab.removeDismissable(win);
                }
            }
            Component.onDestruction: GlobalFocusGrab.removeDismissable(win)

            Connections {
                target: GlobalFocusGrab
                function onDismissed() { GlobalStates.appColorsOpen = false }
            }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: GlobalStates.appColorsOpen = false
            }

            // Dim everything behind the sheet. Same token every other modal
            // here uses (SelectionDialog, PolkitContent, SystemHub, the todo
            // dialog), so the weight matches rather than being a one-off.
            Rectangle {
                id: scrim
                anchors.fill: parent
                color: Appearance.colors.colScrim
                opacity: GlobalStates.appColorsOpen ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
                TapHandler { onTapped: GlobalStates.appColorsOpen = false }
            }

            Rectangle {
                id: card

                /// Which role has its hex field open, "" for none. One at a
                /// time: fifty open text fields is a form, not a palette.
                property string editingRole: ""

                // Apps for the picker above. The dot is carried over from the
                // old chip row: it marks apps that already differ from the base
                // palette, which is the one thing a name cannot tell you.
                readonly property var appEntries: (TinctApps.apps ?? []).map(a => ({
                    name: a.name,
                    label: (a.has_overrides ? "• " : "") + a.name
                }))
                // A different app is a different set of pins.
                Connections {
                    target: TinctApps
                    function onSelectedChanged() { card.editingRole = "" }
                }

                // A sheet ON TOP of WallTune, not a panel beside it.
                //
                // This used to sit a full panel-width to the left. On a wide
                // screen that put it somewhere else entirely — it read as an
                // unrelated window rather than as something WallTune opened.
                //
                // Same right margin as WallTune, including the PanelStack term
                // so it follows when other panels push the stack left, then
                // inset on every side so WallTune's edge stays visible behind
                // it and the relationship is legible. Both surfaces are on the
                // Overlay layer and this one maps second (you open it from
                // WallTune), so it lands above without needing a layer bump.
                readonly property real inset: 12
                width: ScreenFit.panelWidth - card.inset * 2
                // 540 is what the connectivity popup (Wi-Fi / Bluetooth / VPN)
                // uses, and this should not read as a bigger thing than those.
                // The old cap was 880, which on this screen was nearly full
                // height — a column, not a popup. The body already scrolls, so
                // the extra height bought very little.
                height: Math.min(540, win.height - y - Appearance.sizes.hyprlandGapsOut * 2)
                anchors.right: parent.right
                anchors.rightMargin: Appearance.sizes.hyprlandGapsOut + 8
                    + PanelStack.offsetFor("walltune")
                    + card.inset
                y: Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut + 2
                    + card.inset

                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                opacity: GlobalStates.appColorsOpen ? 1 : 0
                scale: GlobalStates.appColorsOpen ? 1 : 0.94
                transformOrigin: Item.Top
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8

                    // ── header ───────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        MaterialSymbol {
                            text: "palette"
                            iconSize: 18
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: qsTr("App colours")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer0
                        }
                        Rectangle {
                            implicitWidth: 26; implicitHeight: 26
                            radius: 13
                            color: closeHov.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover)
                            Behavior on color { ColorAnimation { duration: 140 } }
                            HoverHandler { id: closeHov; margin: Appearance.sizes.touchSlop; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                margin: Appearance.sizes.touchSlop
                                onTapped: GlobalStates.appColorsOpen = false
                            }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: 15
                                color: Appearance.colors.colOnLayer0
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Shift the palette for one app only.")
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    // tinct refuses bad values and changes nothing, so its
                    // message is the whole explanation and goes on screen.
                    Rectangle {
                        Layout.fillWidth: true
                        visible: TinctApps.error !== ""
                        implicitHeight: errText.implicitHeight + 14
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2
                        StyledText {
                            id: errText
                            anchors { fill: parent; margins: 7 }
                            text: TinctApps.error
                            wrapMode: Text.WordWrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                        }
                    }

                    // ── which app ────────────────────────────────
                    // A searchable dropdown, not a chip per app. There are 24
                    // of these and they wrapped to five rows — the single
                    // largest block in the popup, spent on choosing ONE thing.
                    // Typing beats hunting once a list is this long, and the
                    // rows it frees go to the palette you are actually judging.
                    StyledComboBoxSearch {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        model: card.appEntries
                        textRole: "label"
                        colBackground: Appearance.colors.colLayer2
                        currentIndex: card.appEntries.findIndex(a => a.name === TinctApps.selected)
                        onActivated: idx => TinctApps.select(card.appEntries[idx].name)
                    }

                    // ── what you're getting, always on screen ────────────
                    // Everything below this scrolls, and the swatch table is
                    // long enough that it always ends up out of sight. A row
                    // of chips is enough to judge a change by, and it costs
                    // one line to keep it in view while you make one.
                    Flow {
                        Layout.fillWidth: true
                        visible: TinctApps.selected !== ""
                        spacing: 4
                        Repeater {
                            model: ScriptModel { values: TinctApps.keyRows }
                            delegate: Rectangle {
                                required property var modelData
                                implicitWidth: 26
                                implicitHeight: 26
                                radius: Appearance.rounding.small
                                color: modelData.hex
                                // Pinned outranks merely changed: one is a
                                // decision about this role, the other is a
                                // side effect of a slider.
                                border.width: modelData.pinned ? 2 : (modelData.changed ? 1 : 0)
                                border.color: modelData.pinned ? Appearance.colors.colOnLayer0
                                                               : Appearance.colors.colPrimary
                                StyledToolTip { text: modelData.role + "  " + modelData.hex }
                            }
                        }
                    }

                    // ── the controls, scrolled ───────────────────────────
                    StyledFlickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: width
                        contentHeight: body.implicitHeight
                        clip: true

                        ColumnLayout {
                            id: body
                            width: parent.width
                            spacing: 8

                            StyledText {
                                Layout.fillWidth: true
                                visible: TinctApps.selected !== ""
                                text: qsTr("Mode")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer0
                            }
                            Flow {
                                Layout.fillWidth: true
                                visible: TinctApps.selected !== ""
                                spacing: 4
                                Repeater {
                                    // "invert" is the useful one: the opposite
                                    // of whatever the system currently is,
                                    // without having to know which.
                                    model: [
                                        { id: "", label: qsTr("System") },
                                        { id: "dark", label: qsTr("Dark") },
                                        { id: "light", label: qsTr("Light") },
                                        { id: "invert", label: qsTr("Invert") }
                                    ]
                                    delegate: Chip {
                                        required property var modelData
                                        label: modelData.label
                                        selected: TinctApps.valueOf("render", "mode", "") === modelData.id
                                        onPicked: TinctApps.set("render", "mode", modelData.id)
                                    }
                                }
                            }

                            Picker {
                                label: qsTr("Scheme")
                                section: "render"
                                akey: "scheme"
                                defaultLabel: qsTr("Base")
                                options: ["", "tonal-spot", "vibrant", "expressive", "fruit-salad", "monochrome", "rainbow", "neutral", "fidelity", "content"]
                            }

                            // Lives with the scheme rather than the sliders
                            // because it re-runs the scheme: Material derives
                            // contrast during generation, so it isn't a shift
                            // applied to colours that already exist.
                            Adjust {
                                visible: TinctApps.selected !== ""
                                label: qsTr("Contrast"); akey: "contrast"
                                section: "render"
                                from: -1; to: 1; fallback: 0; decimals: 2
                            }

                            Adjust {
                                visible: TinctApps.selected !== ""
                                label: qsTr("Hue"); akey: "hue"
                                from: 0; to: 360; fallback: 180
                            }
                            Adjust {
                                visible: TinctApps.selected !== ""
                                label: qsTr("Saturation"); akey: "saturation"
                                from: 0; to: 100; fallback: 50
                            }
                            Adjust {
                                visible: TinctApps.selected !== ""
                                label: qsTr("Lightness"); akey: "lightness"
                                from: 0; to: 100; fallback: 50
                            }

                            Picker {
                                label: qsTr("Style")
                                section: "adjust"
                                akey: "style"
                                defaultLabel: qsTr("None")
                                options: ["", "pastel", "muted", "bright", "colorful"]
                            }

                            Picker {
                                label: qsTr("Colour theory")
                                section: "adjust"
                                akey: "theory"
                                defaultLabel: qsTr("None")
                                options: ["", "mono", "analogous", "complementary", "triadic", "split", "tetradic"]
                            }

                            Picker {
                                label: qsTr("Practical")
                                section: "adjust"
                                akey: "practical"
                                defaultLabel: qsTr("None")
                                options: ["", "high-contrast", "duotone"]
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: TinctApps.selected !== ""
                                StyledText {
                                    text: qsTr("Result")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer0
                                }
                                Item { Layout.fillWidth: true }
                                StyledText {
                                    text: TinctApps.showAllRoles ? qsTr("Show less") : qsTr("Show all")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colPrimary
                                    HoverHandler { margin: Appearance.sizes.touchSlop; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        margin: Appearance.sizes.touchSlop
                                        onTapped: TinctApps.showAllRoles = !TinctApps.showAllRoles
                                    }
                                }
                            }

                            // Click a role to set it by hand. This is the layer
                            // the sliders can't reach: everything above moves
                            // all fifty roles together, and sometimes the
                            // answer is "that one, this exact colour".
                            Repeater {
                                model: ScriptModel { values: TinctApps.colorRows }
                                delegate: ColumnLayout {
                                    id: rowItem
                                    required property var modelData
                                    readonly property bool editing:
                                        card.editingRole === rowItem.modelData.role
                                    Layout.fillWidth: true
                                    spacing: 3
                                    visible: TinctApps.selected !== ""

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 7

                                        HoverHandler { id: rowHov; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            onTapped: card.editingRole =
                                                rowItem.editing ? "" : rowItem.modelData.role
                                        }

                                        Rectangle {
                                            implicitWidth: 20; implicitHeight: 20
                                            radius: Appearance.rounding.small
                                            color: rowItem.modelData.hex
                                            border.width: rowItem.modelData.changed ? 2 : 0
                                            border.color: Appearance.colors.colPrimary
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: rowItem.modelData.role
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: rowHov.hovered ? Appearance.colors.colPrimary
                                                                  : Appearance.colors.colOnLayer0
                                        }
                                        StyledText {
                                            text: rowItem.modelData.hex
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.family: Appearance.font.family.monospace
                                            color: rowItem.modelData.changed ? Appearance.colors.colPrimary
                                                                             : Appearance.colors.colSubtext
                                        }
                                        // Pinned and merely changed are
                                        // different things: a slider moved
                                        // every role, a pin holds this one.
                                        MaterialSymbol {
                                            text: "push_pin"
                                            iconSize: 14
                                            visible: rowItem.modelData.pinned
                                            color: Appearance.colors.colPrimary
                                            HoverHandler { margin: Appearance.sizes.touchSlop; cursorShape: Qt.PointingHandCursor }
                                            TapHandler {
                                                margin: Appearance.sizes.touchSlop
                                                onTapped: {
                                                    card.editingRole = "";
                                                    TinctApps.unpin(rowItem.modelData.role);
                                                }
                                            }
                                        }
                                    }

                                    PillTextField {
                                        Layout.fillWidth: true
                                        visible: rowItem.editing
                                        leadingIcon: "palette"
                                        showClear: false
                                        placeholderText: qsTr("#RRGGBB, @role, or {{ … }}")
                                        // Seeded imperatively rather than
                                        // bound: a binding would be broken by
                                        // the first keystroke anyway, and
                                        // would yank the field out from under
                                        // you when the palette reloads.
                                        onVisibleChanged: if (visible) {
                                            text = rowItem.modelData.pinned ? rowItem.modelData.pin
                                                                            : rowItem.modelData.hex;
                                        }
                                        onAccepted: {
                                            card.editingRole = "";
                                            TinctApps.pin(rowItem.modelData.role, text);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        visible: TinctApps.selected !== "" && TinctApps.hasOverrides
                        colBackground: Appearance.colors.colLayer2
                        onClicked: TinctApps.resetAll()
                        contentItem: RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: "restart_alt"; iconSize: 15
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                text: qsTr("Back to the base palette")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                            }
                        }
                    }
                }
            }
        }
    }
}
