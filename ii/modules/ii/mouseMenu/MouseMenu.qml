pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

Scope {
    id: root

    // Reactive flat properties for reliable QML data binding
    property bool mouseConnected: false
    property int mouseDpi: 0
    property bool mouseSmartShiftEnabled: false
    property int mouseSmartShiftThreshold: 10
    property bool mouseHiResScroll: true
    property int mouseBatteryPercentage: 0
    property string mouseBatteryState: "Disconnected"

    // Process to launch the volume mixer
    Process {
        id: pavucontrolProc
        command: ["pavucontrol"]
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panelWindow
            required property var modelData
            screen: modelData
            visible: GlobalStates.mouseMenuOpen
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            implicitWidth: 320
            implicitHeight: 510  // Increased slightly to accommodate the custom DPI input row
            color: "transparent"
            WlrLayershell.namespace: "quickshell:mouseMenu"
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            // Center the overlay panel on the screen
            anchors {
                top: false
                bottom: false
                left: false
                right: false
            }

            mask: Region { item: mainCard }

            onVisibleChanged: {
                if (visible) {
                    GlobalFocusGrab.addDismissable(panelWindow)
                    statusFile.reload()
                } else {
                    GlobalFocusGrab.removeDismissable(panelWindow)
                }
            }
            Component.onDestruction: GlobalFocusGrab.removeDismissable(panelWindow)
            Connections {
                target: GlobalFocusGrab
                function onDismissed() { GlobalStates.mouseMenuOpen = false }
            }

            // Material 3 Dialog Container (Layer 2)
            Rectangle {
                id: mainCard
                anchors.fill: parent
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer2
                border.color: Appearance.colors.colLayer0Border
                border.width: 1
                focus: panelWindow.visible

                Keys.onEscapePressed: {
                    GlobalStates.mouseMenuOpen = false
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // 1. Header (Device Info + Battery)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        
                        MaterialSymbol {
                            text: "mouse"
                            iconSize: 24
                            color: Appearance.colors.colPrimary
                        }
                        
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: "MX Master 3S"
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.bold: true
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                text: root.mouseConnected ? "Connected" : "Searching..."
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: root.mouseConnected ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }
                        }

                        // Battery Level
                        RowLayout {
                            visible: root.mouseConnected
                            spacing: 4
                            MaterialSymbol {
                                text: root.mouseBatteryState === "Recharging" ? "battery_charging_full" : "battery_std"
                                iconSize: 18
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: root.mouseBatteryPercentage + "%"
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                            }
                        }
                    }

                    // Divider
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Appearance.colors.colLayer0Border
                        opacity: 0.5
                    }

                    // Controls Column
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 14
                        enabled: root.mouseConnected
                        opacity: enabled ? 1.0 : 0.4

                        // SmartShift Mode Toggle
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            StyledText {
                                text: "SmartShift Mode"
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.bold: true
                                color: Appearance.colors.colPrimary
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                
                                RippleButton {
                                    id: freespinBtn
                                    Layout.fillWidth: true
                                    colBackground: Appearance.colors.colLayer3
                                    toggled: !root.mouseSmartShiftEnabled
                                    contentItem: StyledText {
                                        text: "Freespin"
                                        color: freespinBtn.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: Quickshell.execDetached([`${Quickshell.env("HOME")}/.scripts/logitune-cli`, "--set-smartshift", "freespin"])
                                }
                                RippleButton {
                                    id: smartshiftBtn
                                    Layout.fillWidth: true
                                    colBackground: Appearance.colors.colLayer3
                                    toggled: root.mouseSmartShiftEnabled
                                    contentItem: StyledText {
                                        text: "SmartShift"
                                        color: smartshiftBtn.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: Quickshell.execDetached([`${Quickshell.env("HOME")}/.scripts/logitune-cli`, "--set-smartshift", "ratchet"])
                                }
                            }
                        }

                        // DPI Switcher
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            StyledText {
                                text: "DPI Resolution"
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.bold: true
                                color: Appearance.colors.colPrimary
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Repeater {
                                    model: [1000, 2000, 3500, 5000, 8000]
                                    delegate: RippleButton {
                                        id: dpiBtn
                                        required property int modelData
                                        Layout.fillWidth: true
                                        colBackground: Appearance.colors.colLayer3
                                        toggled: Math.abs(root.mouseDpi - modelData) < 150
                                        contentItem: StyledText {
                                            text: dpiBtn.modelData.toString()
                                            color: dpiBtn.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        onClicked: Quickshell.execDetached([`${Quickshell.env("HOME")}/.scripts/logitune-cli`, "--set-dpi", modelData.toString()])
                                    }
                                }
                            }

                            // Precise Custom DPI Entry Field
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                
                                PillTextField {
                                    id: customDpiInput
                                    Layout.fillWidth: true
                                    placeholderText: "Custom DPI..."
                                    leadingIcon: "tune"
                                    Component.onCompleted: {
                                        text = root.mouseDpi > 0 ? root.mouseDpi.toString() : ""
                                    }
                                    onAccepted: {
                                        const val = parseInt(text)
                                        if (!isNaN(val) && val >= 200 && val <= 8000) {
                                            Quickshell.execDetached([`${Quickshell.env("HOME")}/.scripts/logitune-cli`, "--set-dpi", val.toString()])
                                            customDpiInput.inputItem.focus = false
                                        }
                                    }
                                }
                                
                                RippleButton {
                                    id: setDpiBtn
                                    colBackground: Appearance.colors.colLayer3
                                    implicitWidth: 60
                                    contentItem: StyledText {
                                        text: "Set"
                                        color: Appearance.colors.colOnLayer3
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: {
                                        const val = parseInt(customDpiInput.text)
                                        if (!isNaN(val) && val >= 200 && val <= 8000) {
                                            root.mouseDpi = val
                                            Quickshell.execDetached([`${Quickshell.env("HOME")}/.scripts/logitune-cli`, "--set-dpi", val.toString()])
                                            customDpiInput.inputItem.focus = false
                                        }
                                    }
                                }
                            }
                        }

                        // High-Res Scroll Switch Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    text: "High-Res Scrolling"
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.bold: true
                                    color: Appearance.colors.colOnLayer2
                                }
                                StyledText {
                                    text: "Smooth sub-pixel scroll events"
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            StyledSwitch {
                                checked: root.mouseHiResScroll
                                onToggled: {
                                    root.mouseHiResScroll = checked
                                    Quickshell.execDetached([`${Quickshell.env("HOME")}/.scripts/logitune-cli`, "--set-hires", checked ? "on" : "off"])
                                }
                            }
                        }
                    }

                    // Divider
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Appearance.colors.colLayer0Border
                        opacity: 0.5
                    }

                    // System Utilities (Footer Buttons)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RippleButton {
                            id: shelfBtn
                            Layout.fillWidth: true
                            colBackground: Appearance.colors.colLayer3
                            contentItem: StyledText {
                                text: "Shelf"
                                color: Appearance.colors.colOnLayer3
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                GlobalStates.shelfOpen = !GlobalStates.shelfOpen
                                GlobalStates.mouseMenuOpen = false
                            }
                        }
                        RippleButton {
                            id: walltuneBtn
                            Layout.fillWidth: true
                            colBackground: Appearance.colors.colLayer3
                            contentItem: StyledText {
                                text: "WallTune"
                                color: Appearance.colors.colOnLayer3
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                GlobalStates.wallTuneOpen = !GlobalStates.wallTuneOpen
                                GlobalStates.mouseMenuOpen = false
                            }
                        }
                        RippleButton {
                            id: mixerBtn
                            Layout.fillWidth: true
                            colBackground: Appearance.colors.colLayer3
                            contentItem: StyledText {
                                text: "Mixer"
                                color: Appearance.colors.colOnLayer3
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                pavucontrolProc.running = true
                                GlobalStates.mouseMenuOpen = false
                            }
                        }
                    }
                }
            }
        }
    }

    FileView {
        id: statusFile
        path: "/dev/shm/logitune-cli-status.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(statusFile.text())
                root.mouseConnected = data.connected || false
                root.mouseDpi = data.dpi || 0
                root.mouseSmartShiftEnabled = data.smartshift_enabled || false
                root.mouseSmartShiftThreshold = data.smartshift_threshold || 10
                root.mouseHiResScroll = data.hires_scroll || false
                root.mouseBatteryPercentage = data.battery_percentage || 0
                root.mouseBatteryState = data.battery_state || "Disconnected"

                // Only update the input text if the user isn't currently typing in it
                if (!customDpiInput.inputItem.activeFocus) {
                    customDpiInput.text = root.mouseDpi > 0 ? root.mouseDpi.toString() : ""
                }
            } catch (e) {
                // Ignore parse errors on transient writes
            }
        }
    }
}
