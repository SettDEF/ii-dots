// Pointer settings, in the Settings app.
//
// The Pointer panel is the place you TUNE from — it has the curve editor, live
// telemetry, and everything under your hand while you drag. This page is the
// place you FIND things: the durable switches, the profile rules you made
// weeks ago, and the config files various daemons keep about your mouse.
//
// It deliberately does not duplicate the curve editor. Two editors for one
// curve is how they drift.
import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    ContentSection {
        icon: "mouse"
        title: Translation.tr("Device")

        // Everything here comes from logitune-cli's status file, so it is
        // blank rather than wrong when no supported mouse is attached.
        ConfigRow {
            visible: !LogiTune.available
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("No supported mouse detected. These controls need logitune-cli and a Logitech device.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }

        ConfigRow {
            visible: LogiTune.available
            StyledText {
                Layout.fillWidth: true
                text: LogiTune.deviceLabel
                    + (LogiTune.connected
                        ? ("  ·  " + Translation.tr("battery %1%").arg(LogiTune.battery))
                        : ("  ·  " + Translation.tr("disconnected")))
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: LogiTune.connected ? Appearance.colors.colOnLayer0
                                          : Appearance.colors.colSubtext
            }
        }

        ConfigSpinBox {
            visible: LogiTune.available
            icon: "adjust"
            text: Translation.tr("Sensor DPI")
            value: LogiTune.dpi
            from: LogiTune.minDpi
            to: LogiTune.maxDpi
            stepSize: LogiTune.step
            onValueChanged: LogiTune.setDpi(value)
        }

        ConfigSwitch {
            visible: LogiTune.available
            buttonIcon: "swap_vert"
            text: Translation.tr("High-resolution scrolling")
            checked: LogiTune.hiResScroll
            onCheckedChanged: LogiTune.setHiResScroll(checked)
        }

        ConfigSwitch {
            visible: LogiTune.available
            buttonIcon: "sync"
            text: Translation.tr("Ratcheted scroll wheel")
            checked: LogiTune.smartShift
            onCheckedChanged: LogiTune.setSmartShift(checked ? "ratchet" : "freespin")
        }
    }

    ContentSection {
        icon: "tune"
        title: Translation.tr("Profiles")

        ConfigSwitch {
            buttonIcon: "auto_mode"
            text: Translation.tr("Switch pointer settings by context")
            checked: Config.options.kinetix.profilesEnabled
            onCheckedChanged: Config.options.kinetix.profilesEnabled = checked
        }

        ConfigRow {
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Most specific wins: an app rule beats a workspace rule, which beats a monitor rule. With none matching, your own saved settings apply.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }

        ConfigRow {
            StyledText {
                Layout.fillWidth: true
                text: KinetixProfiles.activeProfile
                    ? Translation.tr("Active now: %1").arg(KinetixProfiles.activeLabel)
                    : Translation.tr("No profile active")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: KinetixProfiles.activeProfile ? Appearance.colors.colPrimary
                                                     : Appearance.colors.colSubtext
            }
        }

        // Rules are CREATED in the Pointer panel, where the settings they
        // capture are in front of you. Here they are listed and removable —
        // which is what you want weeks later, when you have forgotten a rule
        // exists and the pointer feels wrong in one app.
        Repeater {
            model: KinetixProfiles.profiles
            delegate: ConfigRow {
                required property var modelData
                MaterialSymbol {
                    text: modelData.scope === "app" ? "apps"
                        : modelData.scope === "workspace" ? "workspaces" : "monitor"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    text: modelData.name || modelData.match
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                }
                StyledText {
                    visible: Number(modelData.dpi ?? 0) > 0
                    text: (modelData.dpi ?? 0) + " dpi"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
                RippleButton {
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    onClicked: KinetixProfiles.remove(modelData.scope, modelData.match)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "delete"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.m3colors.m3error
                    }
                    StyledToolTip { text: Translation.tr("Delete this rule") }
                }
            }
        }

        ConfigRow {
            visible: KinetixProfiles.profiles.length === 0
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("No rules yet. Open the Pointer panel and use \"This app\" / \"This workspace\" / \"This monitor\" to capture the current settings.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            visible: KinetixProfiles.profiles.length > 0
            materialIcon: "delete_sweep"
            mainText: Translation.tr("Delete all rules")
            onClicked: KinetixProfiles.clearAll()
        }
    }

    ContentSection {
        icon: "speed"
        title: Translation.tr("Feel")

        // The same values the Pointer panel edits, read from and written to the
        // engine's config through KinetixProfiles — one write path, so the two
        // surfaces cannot disagree about what the current settings are.
        //
        // The curve editor is deliberately NOT duplicated here. Two editors for
        // one curve is how they drift; the panel owns that.
        ConfigSpinBox {
            icon: "speed"
            text: Translation.tr("Master sensitivity (×100)")
            value: Math.round(KinetixProfiles.baseField("sensitivity", 1.0) * 100)
            from: 20
            to: 300
            stepSize: 5
            onValueChanged: KinetixProfiles.setBaseField("sensitivity", value / 100)
        }

        ConfigSpinBox {
            icon: "blur_on"
            text: Translation.tr("Motion smoothness (%)")
            value: Math.round(KinetixProfiles.baseField("smoothness", 0.35) * 100)
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: KinetixProfiles.setBaseField("smoothness", value / 100)
        }

        ConfigSpinBox {
            icon: "vibration"
            text: Translation.tr("Micro-tremor damping (×100 px/f)")
            value: Math.round(KinetixProfiles.baseField("tremor_friction", 0.4) * 100)
            from: 0
            to: 200
            stepSize: 5
            onValueChanged: KinetixProfiles.setBaseField("tremor_friction", value / 100)
        }

        ConfigSwitch {
            buttonIcon: "straighten"
            text: Translation.tr("Angle snapping")
            checked: KinetixProfiles.baseField("angle_snapping", false) === true
            onCheckedChanged: KinetixProfiles.setBaseField("angle_snapping", checked)
        }

        ConfigSpinBox {
            visible: KinetixProfiles.baseField("angle_snapping", false) === true
            icon: "architecture"
            text: Translation.tr("Snap threshold (degrees)")
            value: Math.round(KinetixProfiles.baseField("snap_angle_deg", 6))
            from: 1
            to: 45
            stepSize: 1
            onValueChanged: KinetixProfiles.setBaseField("snap_angle_deg", value)
        }

        ConfigSwitch {
            buttonIcon: "sledding"
            text: Translation.tr("Kinetic glide")
            checked: KinetixProfiles.baseField("kinetic_inertia", false) === true
            onCheckedChanged: KinetixProfiles.setBaseField("kinetic_inertia", checked)
        }

        ConfigSpinBox {
            visible: KinetixProfiles.baseField("kinetic_inertia", false) === true
            icon: "trending_down"
            text: Translation.tr("Coasting decay (×100)")
            value: Math.round(KinetixProfiles.baseField("glide_friction", 0.82) * 100)
            from: 50
            to: 99
            stepSize: 1
            onValueChanged: KinetixProfiles.setBaseField("glide_friction", value / 100)
        }
    }

    ContentSection {
        icon: "description"
        title: Translation.tr("Config files")

        ConfigRow {
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Several daemons keep their own file about this mouse. Listed read-only — they belong to their tools, and editing one from here is how they drift apart.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }

        // The reason this section exists: two files independently recording a
        // DPI, with nothing reconciling them. Whichever daemon applies last
        // wins, so a disagreement here explains a mouse that feels different
        // depending on what started first.
        ConfigRow {
            visible: MouseConfigs.dpiSummary.length > 0
            MaterialSymbol {
                text: MouseConfigs.dpiConflict ? "warning" : "check_circle"
                iconSize: Appearance.font.pixelSize.large
                color: MouseConfigs.dpiConflict ? Appearance.m3colors.m3error
                                                : Appearance.colors.colPrimary
            }
            StyledText {
                Layout.fillWidth: true
                text: MouseConfigs.dpiConflict
                    ? Translation.tr("DPI disagreement — %1").arg(MouseConfigs.dpiSummary)
                    : MouseConfigs.dpiSummary
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: MouseConfigs.dpiConflict ? Appearance.m3colors.m3error
                                                : Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }

        Repeater {
            model: MouseConfigs.entries
            delegate: ConfigRow {
                required property var modelData
                MaterialSymbol {
                    text: modelData.exists ? "description" : "not_interested"
                    iconSize: Appearance.font.pixelSize.large
                    color: modelData.exists ? Appearance.colors.colOnLayer0
                                            : Appearance.colors.colSubtext
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: modelData.label + "  ·  " + modelData.owner
                            + (modelData.dpi > 0 ? ("  ·  " + modelData.dpi + " dpi") : "")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: modelData.exists ? Appearance.colors.colOnLayer0
                                                : Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: modelData.exists ? modelData.path
                                               : (modelData.path + "  —  not present")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideMiddle
                    }
                }
                RippleButton {
                    visible: modelData.exists
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    onClicked: MouseConfigs.openInEditor(modelData.path)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "open_in_new"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colSubtext
                    }
                    StyledToolTip { text: Translation.tr("Open this file") }
                }
            }
        }
    }

    ContentSection {
        icon: "tune"
        title: Translation.tr("Curve")

        ConfigRow {
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("The acceleration curve is edited in the Pointer panel, where you can see it react as you drag.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "open_in_new"
            mainText: Translation.tr("Open the Pointer panel")
            onClicked: GlobalStates.kinetixOpen = true
        }
    }
}
