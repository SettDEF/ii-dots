import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * HUD Media · Equalizer — a live 10-band graphic equalizer driven by the
 * Equalizer service (native PipeWire filter-chain). Vertical sliders per
 * band, eight tone presets, and a routing toggle.
 */
Item {
    id: root
    implicitHeight: col.implicitHeight + 28
    readonly property color accent: Appearance.m3colors.m3primary

    // ── Vertical band slider — centre-origin fill (0 dB in the middle) ──
    component VSlider: Item {
        id: vs
        property int bandIndex: 0
        readonly property real value: Equalizer.bands[bandIndex] ?? 0
        readonly property real handle: 17
        readonly property real travel: Math.max(1, height - handle)
        readonly property real frac:
            (value - Equalizer.minGain) / (Equalizer.maxGain - Equalizer.minGain)
        readonly property real handleCY: (1 - frac) * travel + handle / 2
        readonly property real zeroCY: 0.5 * travel + handle / 2
        implicitWidth: 26

        Rectangle {   // track
            anchors.horizontalCenter: parent.horizontalCenter
            width: 5; radius: 2.5
            y: vs.handle / 2; height: vs.travel
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.87)
        }
        Rectangle {   // fill from the 0 dB line to the handle
            anchors.horizontalCenter: parent.horizontalCenter
            width: 5; radius: 2.5
            y: Math.min(vs.handleCY, vs.zeroCY)
            height: Math.abs(vs.handleCY - vs.zeroCY)
            color: root.accent
        }
        Rectangle {   // handle
            width: vs.handle; height: vs.handle; radius: vs.handle / 2
            x: (vs.width - vs.handle) / 2
            y: vs.handleCY - vs.handle / 2
            color: dragMa.pressed ? Qt.lighter(root.accent, 1.25) : "#f3f3f3"
            border.width: 2; border.color: root.accent
            Behavior on y {
                enabled: !dragMa.pressed
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
        }
        MouseArea {
            id: dragMa
            anchors.fill: parent
            cursorShape: Qt.SizeVerCursor
            function setFromY(y) {
                const t = 1 - Math.max(0, Math.min(1, (y - vs.handle / 2) / vs.travel))
                Equalizer.setBand(vs.bandIndex,
                    Equalizer.minGain + t * (Equalizer.maxGain - Equalizer.minGain))
            }
            onPressed: mouse => setFromY(mouse.y)
            onPositionChanged: mouse => { if (pressed) setFromY(mouse.y) }
        }
    }

    // ── A pill button ───────────────────────────────────────────────────
    component Pill: Rectangle {
        id: pill
        property string label: ""
        property bool on: false
        signal clicked()
        implicitHeight: 30
        implicitWidth: pillText.implicitWidth + 26
        radius: 9
        color: on ? root.accent
             : pillHov.hovered ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
        border.width: 1
        border.color: on ? root.accent : Appearance.colors.colLayer0Border
        Behavior on color { ColorAnimation { duration: 130 } }
        StyledText {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: pill.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
        }
        HoverHandler { id: pillHov }
        TapHandler { onTapped: pill.clicked() }
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 14

        // ── Setup prompt (before the PipeWire sink is installed) ─────────
        Rectangle {
            Layout.fillWidth: true
            visible: !Equalizer.installed
            implicitHeight: setupCol.implicitHeight + 36
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1; border.color: Appearance.colors.colLayer0Border
            ColumnLayout {
                id: setupCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
                spacing: 8
                RowLayout {
                    spacing: 10
                    MaterialSymbol { text: "graphic_eq"; iconSize: 26; fill: 1; color: root.accent }
                    StyledText {
                        text: "Equalizer not set up"
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer0
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Creates a native PipeWire “Equalizer” sink with 10 biquad "
                        + "bands. PipeWire restarts once during setup (a brief audio drop). "
                        + "Your normal output stays available — switch any time."
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                Pill {
                    Layout.topMargin: 4
                    implicitWidth: 200
                    label: Equalizer.busy ? "Setting up…  PipeWire restarting"
                                          : "Set up equalizer"
                    on: !Equalizer.busy
                    onClicked: if (!Equalizer.busy) Equalizer.install()
                }
            }
        }

        // ── The equalizer ────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            visible: Equalizer.installed
            spacing: 14

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                StyledText {
                    Layout.fillWidth: true
                    text: "Equalizer"
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer0
                }
                Pill {
                    label: Equalizer.active ? "●  Routing audio" : "Bypassed"
                    on: Equalizer.active
                    onClicked: Equalizer.setActive(!Equalizer.active)
                }
                Pill {
                    label: "Reset"
                    onClicked: Equalizer.applyPreset("Flat")
                }
            }

            // Band sliders
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 252
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1; border.color: Appearance.colors.colLayer0Border

                RowLayout {
                    anchors { fill: parent; topMargin: 14; bottomMargin: 12; leftMargin: 8; rightMargin: 8 }
                    spacing: 0
                    Repeater {
                        model: 10
                        delegate: ColumnLayout {
                            required property int index
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 5
                            StyledText {   // dB readout
                                Layout.alignment: Qt.AlignHCenter
                                readonly property real g: Equalizer.bands[index] ?? 0
                                text: (g > 0 ? "+" : "") + Math.round(g)
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Math.round(g) === 0
                                    ? Appearance.colors.colSubtext : root.accent
                            }
                            VSlider {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.fillHeight: true
                                bandIndex: index
                            }
                            StyledText {   // frequency label
                                Layout.alignment: Qt.AlignHCenter
                                text: Equalizer.freqLabels[index]
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }

            // Presets
            GridLayout {
                Layout.fillWidth: true
                columns: 4
                columnSpacing: 8
                rowSpacing: 8
                Repeater {
                    model: Equalizer.presetNames
                    delegate: Pill {
                        required property string modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        implicitWidth: 0
                        label: modelData
                        on: Equalizer.activePreset === modelData
                        onClicked: Equalizer.applyPreset(modelData)
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: !Equalizer.active
                text: "Tip: enable “Routing audio” to hear the equalizer — "
                    + "it sets the Equalizer sink as your default output."
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                opacity: 0.7
            }
        }
    }
}
