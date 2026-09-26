pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * ROG control for the Flow Z13 (GZ302EA).
 *
 * Only what this machine actually has: no GPU switching (no dGPU), no AniMe
 * matrix or Slash bar, no screenpad. Hardware state and writes live in the Rog
 * service; this file is layout.
 */
Scope {
    id: root

    readonly property var profileModel: [
        { id: "Quiet",       label: Translation.tr("Quiet"),       icon: "eco" },
        { id: "Balanced",    label: Translation.tr("Balanced"),    icon: "balance" },
        { id: "Performance", label: Translation.tr("Performance"), icon: "bolt" }
    ]
    function profileIcon(p) {
        return p === "Quiet" ? "eco" : (p === "Performance" ? "bolt" : "balance")
    }

    StackedPanelLoader {
        isOpen: GlobalStates.rogPowerOpen

        sourceComponent: StackedSettingsPanel {
            id: win
            panelId: "rogPower"
            title: Translation.tr("ROG")
            icon: "developer_board"
            onRequestClose: GlobalStates.rogPowerOpen = false

            Component.onCompleted: Rog.watchers++
            Component.onDestruction: Rog.watchers--

            // ── Live header ─────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: header.implicitHeight + 28
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1

                readonly property bool hot: Rog.cpuTemp >= 90

                ColumnLayout {
                    id: header
                    x: 14
                    y: 14
                    width: parent.width - 28
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Rectangle {
                            implicitWidth: 44
                            implicitHeight: 44
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colPrimaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: root.profileIcon(Rog.profile)
                                iconSize: 24
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            StyledText {
                                Layout.fillWidth: true
                                text: Rog.profile
                                font.pixelSize: Appearance.font.pixelSize.larger
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: (Rog.onAc ? Translation.tr("On charger") : Translation.tr("On battery"))
                                      + "  ·  " + Rog.batteryPercent + "%"
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }

                        StyledText {
                            text: Rog.apuWatts > 0 ? Rog.apuWatts.toFixed(0) + " W" : "—"
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    // Four readings, label over value.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        component Stat: ColumnLayout {
                            property string label: ""
                            property string value: "—"
                            property color tint: Appearance.colors.colOnLayer1
                            Layout.fillWidth: true
                            spacing: 0
                            // fillWidth on the TEXTS too: a nested layout can
                            // grow no wider than its children allow, and a text
                            // without it counts as fixed-width - which capped
                            // each stat at its text and packed the row left.
                            StyledText {
                                Layout.fillWidth: true
                                text: label
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: value
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.family: Appearance.font.family.monospace
                                color: tint
                            }
                        }

                        Stat {
                            label: Translation.tr("CPU")
                            value: Rog.cpuTemp > 0 ? Rog.cpuTemp + "°C" : "—"
                            tint: Rog.cpuTemp >= 90 ? Appearance.m3colors.m3error
                                : Rog.cpuTemp >= 80 ? Appearance.colors.colPrimary
                                : Appearance.colors.colOnLayer1
                        }
                        Stat {
                            label: Translation.tr("GPU")
                            value: Rog.gpuTemp > 0 ? Rog.gpuTemp + "°C" : "—"
                            tint: Rog.gpuTemp >= 90 ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                        }
                        Stat {
                            label: Translation.tr("Fan 1")
                            value: Rog.fan1Rpm > 0 ? Rog.fan1Rpm + "" : Translation.tr("off")
                        }
                        Stat {
                            label: Translation.tr("Fan 2")
                            value: Rog.fan2Rpm > 0 ? Rog.fan2Rpm + "" : Translation.tr("off")
                        }
                    }
                }
            }

            // ── Performance ─────────────────────────────────────────────
            CollapsibleSection {
                title: Translation.tr("Performance")
                value: Rog.profile
                icon: "speed"
                expanded: true

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    SegmentedControl {
                        Layout.fillWidth: true
                        model: root.profileModel
                        currentId: Rog.profile
                        onPicked: id => Rog.setProfile(id)
                    }
                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer1
                        onClicked: win.autoOpen = true
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "tune"
                            iconSize: 18
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledToolTip { text: Translation.tr("Automatic switching") }
                    }
                }
            }

            // ── Battery ─────────────────────────────────────────────────
            CollapsibleSection {
                title: Translation.tr("Battery")
                value: Translation.tr("Limit %1%").arg(Rog.batteryLimit)
                       + (Rog.batteryHealth > 0 ? "  ·  " + Translation.tr("Health %1%").arg(Rog.batteryHealth) : "")
                icon: "battery_charging_full"

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Charge limit")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            text: limitSlider.pressed ? Math.round(limitSlider.value) + "%" : Rog.batteryLimit + "%"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                    StyledSlider {
                        id: limitSlider
                        Layout.fillWidth: true
                        from: 20
                        to: 100
                        stepSize: 5
                        usePercentTooltip: false
                        stopIndicatorValues: [60, 80, 100]
                        value: Rog.batteryLimit
                        // One write per gesture: asusctl is not a thing to call
                        // on every pixel of a drag.
                        onPressedChanged: if (!pressed) Rog.setBatteryLimit(value)
                    }
                }

                // A charge limit's whole point is to stop short most days; the
                // common reasons to change it are these three.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [
                            { v: 60,  label: Translation.tr("Desk (60%)") },
                            { v: 80,  label: Translation.tr("Daily (80%)") },
                            { v: 100, label: Translation.tr("Full") }
                        ]
                        delegate: RippleButton {
                            id: chip
                            required property var modelData
                            readonly property bool sel: Rog.batteryLimit === chip.modelData.v
                            Layout.fillWidth: true
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: sel ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
                            colBackgroundHover: sel ? Appearance.colors.colPrimary : Appearance.colors.colLayer1Hover
                            onClicked: Rog.setBatteryLimit(chip.modelData.v)
                            contentItem: StyledText {
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: chip.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: chip.sel ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }

                // Top up to 100% once - for a travel day - without giving up the
                // limit afterwards.
                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    visible: Rog.batteryLimit < 100
                    materialIcon: "bolt"
                    mainText: Translation.tr("Charge to 100% once")
                    onClicked: Rog.chargeOnce(100)
                }

                // Health and live state.
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: batStats.implicitHeight + 20
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    GridLayout {
                        id: batStats
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                        columns: 2
                        columnSpacing: 12
                        rowSpacing: 6

                        component Kv: RowLayout {
                            property string k: ""
                            property string v: ""
                            Layout.fillWidth: true
                            StyledText {
                                Layout.fillWidth: true
                                text: k
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                text: v
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.family: Appearance.font.family.monospace
                                color: Appearance.colors.colOnLayer1
                            }
                        }

                        Kv { k: Translation.tr("Status"); v: Rog.batteryStatus || "—" }
                        Kv {
                            k: Translation.tr("Now")
                            v: Rog.batteryWatts > 0.05 ? Rog.batteryWatts.toFixed(1) + " W" : "—"
                        }
                        Kv {
                            k: Translation.tr("Health")
                            v: Rog.batteryHealth > 0 ? Rog.batteryHealth + "%" : "—"
                        }
                        Kv {
                            k: Translation.tr("Capacity")
                            v: Rog.batteryDesignWh > 0
                               ? Rog.batteryFullWh.toFixed(1) + " / " + Rog.batteryDesignWh.toFixed(0) + " Wh"
                               : "—"
                        }
                        Kv {
                            visible: Rog.batteryCycles > 0
                            k: Translation.tr("Cycles")
                            v: String(Rog.batteryCycles)
                        }
                    }
                }
            }

            // ── Fans & power ────────────────────────────────────────────
            // A section of this panel, not a popup: the editor used to open in
            // a sheet with its own card and title inside it.
            CollapsibleSection {
                title: Translation.tr("Fans & power")
                value: Rog.fan1Rpm + " / " + Rog.fan2Rpm + " rpm"
                icon: "mode_fan"

                RogPowerContent {
                    Layout.fillWidth: true
                    embedded: true
                }
            }

            property bool autoOpen: false

            // asusd switches profile by itself when the charger connects or
            // disconnects, which is why the active one can change on its own.
            PanelSheet {
                open: win.autoOpen
                title: Translation.tr("Automatic switching")
                subtitle: Translation.tr("On the charger it steps down while the battery is low or draining")
                onClosed: win.autoOpen = false

                component AutoRow: ColumnLayout {
                    id: autoRow
                    property string label: ""
                    property string symbol: ""
                    property string currentId: ""
                    signal picked(string id)
                    Layout.fillWidth: true
                    spacing: 6
                    RowLayout {
                        spacing: 8
                        MaterialSymbol {
                            text: autoRow.symbol
                            iconSize: 17
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: autoRow.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                    SegmentedControl {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        model: root.profileModel
                        currentId: autoRow.currentId
                        onPicked: id => autoRow.picked(id)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 14
                    AutoRow {
                        label: Translation.tr("On charger")
                        symbol: "power"
                        currentId: Rog.chargerMax
                        onPicked: id => Rog.setAcProfile(id)
                    }
                    AutoRow {
                        label: Translation.tr("On battery")
                        symbol: "battery_full"
                        currentId: Rog.batteryProfile
                        onPicked: id => Rog.setBatteryProfile(id)
                    }
                }
            }
        }
    }
}
