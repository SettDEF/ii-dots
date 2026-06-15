// modules/ii/deviceControl/Panel.qml
import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../common/widgets" as Widgets

Widgets.StyledPopup {
    id: panel
    implicitWidth: 380
    implicitHeight: 580

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 15

        // Header
        RowLayout {
            Layout.fillWidth: true
            Widgets.StyledText { text: "ASUS System Control"; font.bold: true; font.pixelSize: 18 }
            Item { Layout.fillWidth: true }
            Widgets.IconToolbarButton { source: Quickshell.iconPath("window-close"); onClicked: panel.close() }
        }

        // Performance Profiles
        Widgets.ContentSection {
            title: "Performance Profile"
            Layout.fillWidth: true
            ColumnLayout {
                spacing: 8
                Repeater {
                    model: DeviceControl.profiles // Direct access
                    Widgets.RippleButton {
                        required property string modelData
                        Layout.fillWidth: true
                        implicitHeight: 45
                        background: Rectangle {
                            radius: 8
                            color: DeviceControl.currentProfile === modelData ? theme.colors.primary : theme.colors.surface
                        }
                        contentItem: Widgets.StyledText {
                            text: modelData
                            color: DeviceControl.currentProfile === modelData ? theme.colors.bg : theme.colors.text
                            horizontalAlignment: Text.AlignHCenter
                        }
                        onClicked: DeviceControl.setProfile(modelData)
                    }
                }
            }
        }
        
        // Fan Control
        Rectangle {
             Layout.fillWidth: true; height: 60; radius: 12; color: theme.colors.surface
             RowLayout {
                 anchors.fill: parent; anchors.margins: 15
                 Widgets.StyledText { text: "Custom Fan Curve"; color: theme.colors.text; Layout.fillWidth: true }
                 Widgets.StyledSwitch { 
                     checked: DeviceControl.fanCurveActive
                     onToggled: DeviceControl.setFanCurve(checked)
                 }
             }
        }

        // GPU Mode
        Widgets.ContentSection {
            title: "GPU Mode"
            Layout.fillWidth: true
            RowLayout {
                spacing: 10
                Repeater {
                    model: ["Integrated", "Hybrid", "Vfio"]
                    Widgets.RippleButton {
                        required property string modelData
                        Layout.fillWidth: true; implicitHeight: 40
                        background: Rectangle {
                            radius: 8
                            color: DeviceControl.gpuMode === modelData ? theme.colors.accent : theme.colors.surfaceVariant
                        }
                        contentItem: Widgets.StyledText {
                            text: modelData
                            color: DeviceControl.gpuMode === modelData ? theme.colors.bg : theme.colors.text
                        }
                        onClicked: DeviceControl.setGpuMode(modelData)
                    }
                }
            }
        }

        // ── Mouse scroll-speed (Hyprland scroll_factor per device) ────
        Widgets.ContentSection {
            title: "Mouse scroll speed"
            Layout.fillWidth: true

            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true

                Repeater {
                    model: DeviceControl.mice
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            Widgets.StyledText {
                                Layout.fillWidth: true
                                text: modelData.name
                                color: theme.colors.text
                                elide: Text.ElideRight
                            }
                            Widgets.StyledText {
                                text: modelData.scrollFactor.toFixed(2) + "×"
                                color: theme.colors.text
                                opacity: 0.7
                            }
                        }
                        Slider {
                            Layout.fillWidth: true
                            from: 0.1
                            to: 5.0
                            stepSize: 0.05
                            value: modelData.scrollFactor
                            onMoved: DeviceControl.setScrollFactor(modelData.name, value)
                        }
                    }
                }

                Widgets.StyledText {
                    visible: DeviceControl.mice.length === 0
                    text: "No mice detected"
                    color: theme.colors.text
                    opacity: 0.6
                }

                Widgets.RippleButton {
                    Layout.alignment: Qt.AlignRight
                    implicitHeight: 30
                    background: Rectangle {
                        radius: 8; color: theme.colors.surfaceVariant
                    }
                    contentItem: Widgets.StyledText {
                        text: "Refresh"
                        color: theme.colors.text
                        horizontalAlignment: Text.AlignHCenter
                    }
                    onClicked: DeviceControl.refreshMice()
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
