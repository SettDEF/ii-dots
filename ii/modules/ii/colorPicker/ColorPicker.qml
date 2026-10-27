pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The picked colour (services/ColorPick.qml), floating in the middle of the focused screen: a big
 * swatch, HEX / RGB / HSL / OKLCH to copy, its contrast on white and black, its shades, the Material
 * roles tinct makes from it, and the colours picked before. 1–4 copy a format, P picks again, Esc closes.
 */
Scope {
    id: root

    GlobalShortcut {
        name: "colorPick"
        description: "Pick a colour from the screen and show it in every format"
        onPressed: ColorPick.pick()
    }

    LazyLoader {
        active: ColorPick.open

        PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
            WlrLayershell.namespace: "quickshell:colorPicker"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            implicitWidth: card.implicitWidth + 40
            implicitHeight: card.implicitHeight + 40

            readonly property string hex: ColorPick.hex
            readonly property var formats: ColorPick.formats(hex)
            readonly property bool darkInk: ColorPick.luminance(hex || "#000000") > 0.4
            readonly property color ink: darkInk ? "#111111" : "#ffffff"
            function copy(text, what) {
                ColorPick.copy(text);
                status.text = Translation.tr("Copied %1").arg(what);
                statusTimer.restart();
            }

            StyledRectangularShadow { target: card }

            Rectangle {
                id: card
                anchors.centerIn: parent
                implicitWidth: 440
                implicitHeight: col.implicitHeight + 32
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                focus: true
                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Escape) ColorPick.open = false;
                    else if (e.key === Qt.Key_P) ColorPick.pick();
                    else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_4) { const f = win.formats[e.key - Qt.Key_1]; if (f) win.copy(f.text, f.name); }
                    else if (e.key === Qt.Key_C && (e.modifiers & Qt.ControlModifier)) win.copy(win.hex.toUpperCase(), "HEX");
                    else return;
                    e.accepted = true;
                }

                ColumnLayout {
                    id: col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                    spacing: 14

                    // the colour itself, big, with its hex in an ink that reads on it
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 132
                        radius: Appearance.rounding.normal
                        color: win.hex || "transparent"
                        Behavior on color { ColorAnimation { duration: 180 } }
                        ColumnLayout {
                            anchors { left: parent.left; bottom: parent.bottom; margins: 16 }
                            spacing: 0
                            StyledText {
                                text: win.hex.toUpperCase()
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: 30
                                font.weight: Font.DemiBold
                                color: win.ink
                            }
                            StyledText {
                                text: win.formats[3]?.text ?? ""
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Qt.alpha(win.ink, 0.75)
                            }
                        }
                        Row {
                            anchors { right: parent.right; top: parent.top; margins: 8 }
                            spacing: 4
                            Repeater {
                                model: [{ icon: "colorize", tip: Translation.tr("Pick again (P)"), run: () => ColorPick.pick() },
                                        { icon: "close", tip: Translation.tr("Close (Esc)"), run: () => { ColorPick.open = false; } }]
                                delegate: RippleButton {
                                    id: hb
                                    required property var modelData
                                    implicitWidth: 34; implicitHeight: 34
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Qt.alpha(win.ink, 0.12)
                                    colBackgroundHover: Qt.alpha(win.ink, 0.22)
                                    onClicked: hb.modelData.run()
                                    contentItem: Item {
                                        MaterialSymbol { anchors.centerIn: parent; text: hb.modelData.icon; iconSize: 20; color: win.ink }
                                    }
                                    StyledToolTip { text: hb.modelData.tip }
                                }
                            }
                        }
                    }

                    // the formats: click (or 1–4) copies
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Repeater {
                            model: win.formats
                            delegate: RippleButton {
                                id: fr
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: 36
                                buttonRadius: Appearance.rounding.small
                                onClicked: win.copy(fr.modelData.text, fr.modelData.name)
                                contentItem: RowLayout {
                                    spacing: 10
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
                                    StyledText {
                                        Layout.preferredWidth: 52
                                        text: fr.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: fr.modelData.text
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer0
                                        elide: Text.ElideRight
                                    }
                                    KeyboardKey { key: String(fr.index + 1) }
                                    MaterialSymbol { text: "content_copy"; iconSize: 17; color: fr.hovered ? Appearance.colors.colPrimary : Appearance.colors.colSubtext }
                                }
                            }
                        }
                    }

                    // contrast: the colour as text on white and on black, and the reverse
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Repeater {
                            model: ["#ffffff", "#000000"]
                            delegate: Rectangle {
                                id: cc
                                required property string modelData
                                readonly property real ratio: ColorPick.contrast(win.hex || "#000000", modelData)
                                Layout.fillWidth: true
                                implicitHeight: 52
                                radius: Appearance.rounding.small
                                color: cc.modelData
                                border.width: 1
                                border.color: Appearance.colors.colLayer0Border
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                    StyledText { text: "Aa"; font.pixelSize: 24; font.weight: Font.Bold; color: win.hex || "gray" }
                                    Item { Layout.fillWidth: true }
                                    ColumnLayout {
                                        spacing: 0
                                        StyledText {
                                            Layout.alignment: Qt.AlignRight
                                            text: cc.ratio.toFixed(2) + ":1"
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: cc.modelData === "#ffffff" ? "#111111" : "#eeeeee"
                                        }
                                        StyledText {
                                            Layout.alignment: Qt.AlignRight
                                            text: cc.ratio >= 7 ? "AAA" : cc.ratio >= 4.5 ? "AA" : cc.ratio >= 3 ? Translation.tr("AA large") : Translation.tr("fails")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: cc.modelData === "#ffffff" ? "#555555" : "#aaaaaa"
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // shades of the same hue (OKLCH lightness): click shows one, right-click copies it
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        StyledText { text: Translation.tr("Shades"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Repeater {
                                model: ColorPick.shades(win.hex)
                                delegate: Swatch { required property string modelData; hex: modelData; Layout.fillWidth: true; implicitHeight: 30 }
                            }
                        }
                    }

                    // tinct's Material roles from it (the dark scheme, as the desktop)
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: ColorPick.roles.length > 0
                        spacing: 6
                        StyledText { text: Translation.tr("Material from it · tinct"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 4
                            columnSpacing: 6
                            rowSpacing: 6
                            Repeater {
                                model: ColorPick.roles.filter(r => ["primary", "primaryContainer", "secondary", "secondaryContainer", "tertiary", "tertiaryContainer", "surfaceContainer", "error"].includes(r.role))
                                delegate: Rectangle {
                                    id: rc
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 44
                                    radius: Appearance.rounding.small
                                    color: rc.modelData.dark
                                    readonly property color ink: ColorPick.luminance(rc.modelData.dark) > 0.4 ? "#111111" : "#ffffff"
                                    Column {
                                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 8; rightMargin: 6 }
                                        StyledText { width: parent.width; elide: Text.ElideRight; text: rc.modelData.role.replace(/([A-Z])/g, " $1").toLowerCase(); font.pixelSize: Appearance.font.pixelSize.smallest; color: Qt.alpha(rc.ink, 0.8) }
                                        StyledText { text: rc.modelData.dark.toUpperCase(); font.family: Appearance.font.family.monospace; font.pixelSize: Appearance.font.pixelSize.smallest; color: rc.ink }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: win.copy(rc.modelData.dark.toUpperCase(), rc.modelData.role)
                                    }
                                }
                            }
                        }
                    }

                    // the colours picked before
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: ColorPick.recent.length > 1
                        spacing: 6
                        StyledText { text: Translation.tr("Picked before"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: Array.from(ColorPick.recent).slice(1)
                                delegate: Swatch { required property string modelData; hex: modelData; implicitWidth: 26; implicitHeight: 26; round: true }
                            }
                        }
                    }

                    // what happened, and the keys
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            id: status
                            Layout.fillWidth: true
                            text: Translation.tr("Click to copy · 1–4 · P picks again · Esc")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                        Timer { id: statusTimer; interval: 1800; onTriggered: status.text = Translation.tr("Click to copy · 1–4 · P picks again · Esc") }
                    }
                }
            }

            // a swatch: click shows it here, right-click copies it
            component Swatch: Rectangle {
                id: sw
                property string hex
                property bool round: false
                radius: round ? height / 2 : Appearance.rounding.verysmall
                color: sw.hex
                border.width: sw.hex === win.hex ? 2 : 0
                border.color: Appearance.colors.colOnLayer0
                MouseArea {
                    id: swm
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: m => m.button === Qt.RightButton ? win.copy(sw.hex.toUpperCase(), sw.hex.toUpperCase()) : ColorPick.show(sw.hex)
                }
                StyledToolTip { extraVisibleCondition: false; alternativeVisibleCondition: swm.containsMouse; text: sw.hex.toUpperCase() }
            }
        }
    }
}
