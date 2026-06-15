import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    backgroundHeight: 620

    Component.onCompleted: MonitorManager.refresh()

    WindowDialogTitle {
        text: Translation.tr("Monitors")
    }
    WindowDialogSeparator {}

    // ── Quick-arrangement presets (Internal / Extend / Mirror / External)
    // Mirrors the Windows "Project" panel. The active preset is detected
    // from current monitor state so the chip stays in sync if the user
    // toggles things manually below.
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: presetRow.implicitHeight + 8

        Flow {
            id: presetRow
            anchors {
                left: parent.left; right: parent.right
                verticalCenter: parent.verticalCenter
            }
            spacing: 6

            component PresetChip: PillTab {
                property string presetId
                inactiveColor: Appearance.colors.colLayer2
                labelSize: Appearance.font.pixelSize.smaller
                horizontalPadding: 9
                verticalPadding: 6
                active: MonitorManager.activePreset === presetId
            }

            PresetChip {
                label: Translation.tr("Internal only"); icon: "laptop"
                presetId: "internal"
                onTriggered: MonitorManager.presetInternalOnly()
            }
            PresetChip {
                label: Translation.tr("Extend"); icon: "splitscreen_right"
                presetId: "extend"
                onTriggered: MonitorManager.presetExtend()
            }
            PresetChip {
                label: Translation.tr("Mirror"); icon: "screen_share"
                presetId: "mirror"
                onTriggered: MonitorManager.presetMirror()
            }
            PresetChip {
                label: Translation.tr("External only"); icon: "monitor"
                presetId: "external"
                onTriggered: MonitorManager.presetExternalOnly()
            }
        }
    }

    WindowDialogSeparator {}

    StyledListView {
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: -15
        Layout.bottomMargin: -16
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large

        clip: true
        spacing: 0
        animateAppearance: false

        model: ScriptModel {
            values: MonitorManager.friendly
        }
        delegate: MonitorItem {
            required property var modelData
            monitor: modelData
            anchors {
                left: parent?.left
                right: parent?.right
            }
        }
    }

    WindowDialogSeparator {}
    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Refresh")
            onClicked: MonitorManager.refresh()
        }
        Item { Layout.fillWidth: true }
        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
