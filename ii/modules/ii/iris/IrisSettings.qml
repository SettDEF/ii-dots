pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Keyboard backlight panel.
 *
 * The folio is a single-zone RGB backlight (ASUS's spec, confirmed by testing
 * both HID transports on every interface), so there is deliberately no per-key
 * editor here — one colour applies to the whole board.
 *
 * Colour and effects go over direct HID; brightness goes through asusd so the
 * slider and the Fn key stay in agreement. All of that lives in the Iris
 * service — this file is only presentation.
 */
Scope {
    id: root

    IpcHandler {
        target: "iris"
        function toggle(): void { GlobalStates.irisOpen = !GlobalStates.irisOpen }
        function open(): void   { GlobalStates.irisOpen = true }
        function close(): void  { GlobalStates.irisOpen = false }
    }

    GlobalShortcut {
        name: "irisToggle"
        description: "Toggle keyboard lighting panel"
        onPressed: GlobalStates.irisOpen = !GlobalStates.irisOpen
    }

    StackedPanelLoader {
        isOpen: GlobalStates.irisOpen

        sourceComponent: StackedSettingsPanel {
            panelId: "iris"
            title: Translation.tr("Keyboard light")
            icon: "keyboard"
            onClosed: GlobalStates.irisOpen = false

            Component.onCompleted: Iris.refresh()

            // ── Brightness ────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: brightCol.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: brightCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 8

                    RowLayout {
                        spacing: 8
                        MaterialSymbol {
                            text: "brightness_medium"
                            iconSize: 17
                            color: Iris.brightness > 0
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: Translation.tr("Brightness")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            // Monospace so the row does not jitter as it changes.
                            text: `${Iris.brightness}/${Iris.maxBrightness}`
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }

                    StyledSlider {
                        Layout.fillWidth: true
                        from: 0
                        to: Iris.maxBrightness
                        stepSize: 1
                        value: Iris.brightness
                        // Four hardware levels, so mark each one on the track.
                        stopIndicatorValues: [0, 1, 2, 3]
                        onMoved: Iris.setBrightness(value)
                    }
                }
            }

            // ── Colour ────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: colourCol.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: colourCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 8

                    RowLayout {
                        spacing: 8
                        MaterialSymbol {
                            text: "palette"
                            iconSize: 17
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: Translation.tr("Colour")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            implicitWidth: 20; implicitHeight: 20
                            radius: Appearance.rounding.full
                            color: Iris.currentColor || Appearance.colors.colLayer2
                            border.width: 1
                            border.color: Appearance.colors.colLayer0Border
                        }
                    }

                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        materialIcon: "wallpaper"
                        mainText: Translation.tr("Follow wallpaper")
                        onClicked: Iris.followWallpaper()
                        StyledToolTip {
                            text: Translation.tr("Re-apply the current palette colour")
                        }
                    }

                    // Fixed swatches for when you want a colour that is not the
                    // wallpaper's. Saturated on purpose — pastels read as white
                    // on an LED.
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: ["#ff0000", "#ff6a00", "#ffd400", "#00ff44",
                                    "#00e5ff", "#0066ff", "#aa00ff", "#ff00aa", "#ffffff"]
                            delegate: Rectangle {
                                required property string modelData
                                implicitWidth: 30; implicitHeight: 30
                                radius: Appearance.rounding.full
                                color: modelData
                                border.width: Iris.currentColor === modelData ? 2 : 1
                                border.color: Iris.currentColor === modelData
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colLayer0Border
                                Behavior on border.width { NumberAnimation { duration: 140 } }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Iris.setColor(parent.modelData)
                                }
                            }
                        }
                    }
                }
            }

            // ── Effects ───────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: fxCol.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: fxCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 8

                    RowLayout {
                        spacing: 8
                        MaterialSymbol {
                            text: "animation"
                            iconSize: 17
                            color: Iris.activeEffect !== ""
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: Translation.tr("Effects")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            visible: Iris.activeEffect !== ""
                            text: Translation.tr("running")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 5
                        Repeater {
                            model: Iris.effects
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool sel: Iris.activeEffect === modelData.name
                                implicitWidth: fxRow.implicitWidth + 18
                                implicitHeight: 32
                                radius: Appearance.rounding.small
                                color: sel ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                                Behavior on color { ColorAnimation { duration: 140 } }

                                RowLayout {
                                    id: fxRow
                                    anchors.centerIn: parent
                                    spacing: 5
                                    MaterialSymbol {
                                        text: modelData.icon
                                        iconSize: 15
                                        color: parent.parent.sel
                                            ? Appearance.colors.colOnPrimary
                                            : Appearance.colors.colOnLayer2
                                    }
                                    StyledText {
                                        text: modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: parent.parent.sel
                                            ? Appearance.colors.colOnPrimary
                                            : Appearance.colors.colOnLayer2
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: parent.sel
                                        ? Iris.stopEffect()
                                        : Iris.runEffect(parent.modelData.name)
                                }
                            }
                        }
                    }

                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        visible: Iris.activeEffect !== ""
                        materialIcon: "stop"
                        mainText: Translation.tr("Stop effect")
                        onClicked: Iris.stopEffect()
                    }
                }
            }
        }
    }
}
