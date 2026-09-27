import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/// Time zone and keyboard layout: the two things worth setting before anything
/// else. Shared by the welcome app and Settings > System, so the first run and
/// the place you go to change it later cannot disagree.
ContentSection {
    id: sec
    icon: "tune"
    title: Translation.tr("Where you are")

    Process {
        id: kbPick
        command: ["qs", "-c", "ii", "ipc", "call", "keyboardLayout", "pick"]
    }
    Process {
        id: kbRead
        running: true
        command: ["qs", "-c", "ii", "ipc", "call", "keyboardLayout", "configured"]
        stdout: StdioCollector { onStreamFinished: sec.layouts = String(text).trim() }
    }
    /// "" when the shell is not running — both hosts can open standalone.
    property string layouts: ""

    ConfigRow {
        StyledText {
            Layout.leftMargin: 8
            Layout.preferredWidth: 110
            text: Translation.tr("Time zone")
            color: Appearance.colors.colOnSecondaryContainer
        }
        StyledComboBox {
            Layout.fillWidth: true
            enabled: !SystemSettings.busy && SystemSettings.timezones.length > 0
            model: SystemSettings.timezones
            currentIndex: Math.max(0, SystemSettings.timezones.indexOf(SystemSettings.timezone))
            onActivated: index => SystemSettings.setTimezone(SystemSettings.timezones[index])
            StyledToolTip {
                text: Translation.tr("Changes the clock for every user. Asks for your password.")
            }
        }
    }

    ConfigRow {
        StyledText {
            Layout.leftMargin: 8
            Layout.preferredWidth: 110
            text: Translation.tr("Keyboard")
            color: Appearance.colors.colOnSecondaryContainer
        }
        StyledText {
            Layout.fillWidth: true
            text: sec.layouts.length > 0 ? sec.layouts.split(",").join(", ")
                                         : Translation.tr("shell not running")
            color: Appearance.colors.colSubtext
        }
        RippleButtonWithIcon {
            materialIcon: "keyboard_alt"
            mainText: Translation.tr("Change")
            enabled: sec.layouts.length > 0
            onClicked: { kbPick.running = false; kbPick.running = true }
            StyledToolTip {
                text: Translation.tr("Applies immediately, no password needed.")
            }
        }
    }

    StyledText {
        visible: SystemSettings.lastError.length > 0
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.m3colors.m3error
        text: SystemSettings.lastError
    }
}
