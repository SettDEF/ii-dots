import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The basics: where you are, what you type with, when the screen goes warm,
// what opens when the shell needs a terminal.
//
// Time zone, system locale and console keymap live in /etc, so those three ask
// for a password. Reads are free, so they are shown either way.
ContentPage {
    id: page
    forceWidth: true

    Process {
        id: kbPickProc
        command: ["qs", "-c", "ii", "ipc", "call", "keyboardLayout", "pick"]
    }
    Process {
        id: kbReadProc
        running: true
        command: ["qs", "-c", "ii", "ipc", "call", "keyboardLayout", "configured"]
        stdout: StdioCollector {
            onStreamFinished: page.sessionLayouts = String(text).trim()
        }
    }
    // "" when the shell is not running — the settings app opens standalone.
    property string sessionLayouts: ""

    ContentSection {
        icon: "system_update"
        title: Translation.tr("Shell updates")

        ConfigRow {
            StyledText {
                Layout.leftMargin: 8
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: !ShellUpdates.available
                        ? Translation.tr("Not a git checkout with a remote, so there is nothing to update from.")
                    : ShellUpdates.error.length > 0 ? ShellUpdates.error
                    : ShellUpdates.checking ? Translation.tr("Checking…")
                    : ShellUpdates.behind > 0
                        ? (ShellUpdates.dirty
                            ? Translation.tr("%1 behind — commit or stash your changes first.").arg(ShellUpdates.behind)
                            : Translation.tr("%1 behind. Latest: %2").arg(ShellUpdates.behind).arg(ShellUpdates.latest))
                    : Translation.tr("Up to date.")
            }
            RippleButtonWithIcon {
                buttonRadius: Appearance.rounding.small
                enabled: ShellUpdates.available && !ShellUpdates.checking
                materialIcon: "refresh"
                mainText: Translation.tr("Check now")
                onClicked: ShellUpdates.check()
            }
            RippleButtonWithIcon {
                buttonRadius: Appearance.rounding.small
                visible: ShellUpdates.updateAvailable
                enabled: ShellUpdates.canApply
                materialIcon: "download"
                mainText: ShellUpdates.applying ? Translation.tr("Updating…")
                                                : Translation.tr("Update now")
                onClicked: ShellUpdates.apply()
            }
        }

        ConfigRow {
            StyledText {
                Layout.leftMargin: 8
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("The welcome screen has the first-run setup and a list of what is installed.")
            }
            RippleButtonWithIcon {
                buttonRadius: Appearance.rounding.small
                materialIcon: "waving_hand"
                mainText: Translation.tr("Open it")
                onClicked: Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "welcome", "open"])
            }
        }

        ConfigSwitch {
            buttonIcon: "update"
            text: Translation.tr("Check for updates")
            checked: Config.options.updates.shell.enable
            onCheckedChanged: Config.options.updates.shell.enable = checked
        }
        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Notify when an update is found")
            checked: Config.options.updates.shell.notify
            onCheckedChanged: Config.options.updates.shell.notify = checked
        }
        ConfigSwitch {
            buttonIcon: "bolt"
            text: Translation.tr("Install updates automatically")
            checked: Config.options.updates.shell.autoApply
            onCheckedChanged: Config.options.updates.shell.autoApply = checked
            StyledToolTip {
                text: Translation.tr("Fast-forward only, and skipped while you have uncommitted changes. The shell reloads as soon as the files land, so it will change under you.")
            }
        }
        ConfigSpinBox {
            icon: "timer"
            text: Translation.tr("Check every (hours)")
            value: Config.options.updates.shell.checkIntervalHours
            from: 1
            to: 168
            stepSize: 1
            onValueChanged: Config.options.updates.shell.checkIntervalHours = value
        }
    }

    ContentSection {
        icon: "schedule"
        title: Translation.tr("Time & place")

        ConfigRow {
            StyledText {
                Layout.leftMargin: 8
                Layout.preferredWidth: 120
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
                    text: Translation.tr("Changes the system clock for every user. Asks for your password.")
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

        ContentSubsection {
            title: Translation.tr("Clock format")
            ConfigSelectionArray {
                currentValue: Config.options.time.format
                onSelected: newValue => {
                    Config.options.time.format = newValue;
                    // 12-hour without am/pm is a wrong clock.
                    Config.options.time.dateFormat = newValue === "h:mm AP"
                        ? "ddd, MM/dd" : "ddd, dd/MM";
                    Config.options.time.shortDateFormat = newValue === "h:mm AP"
                        ? "MM/dd" : "dd/MM";
                    Config.options.time.dateWithYearFormat = newValue === "h:mm AP"
                        ? "MM/dd/yyyy" : "dd/MM/yyyy";
                }
                options: [
                    { displayName: Translation.tr("24-hour"), value: "hh:mm" },
                    { displayName: Translation.tr("12-hour"), value: "h:mm AP" }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "avg_pace"
            text: Translation.tr("Show seconds")
            checked: Config.options.time.secondPrecision
            onCheckedChanged: Config.options.time.secondPrecision = checked
        }
    }

    ContentSection {
        icon: "keyboard"
        title: Translation.tr("Keyboard")

        ConfigRow {
            StyledText {
                Layout.leftMargin: 8
                Layout.preferredWidth: 120
                text: Translation.tr("Session layout")
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledText {
                Layout.fillWidth: true
                text: page.sessionLayouts.length > 0
                    ? page.sessionLayouts.split(",").join(", ")
                    : Translation.tr("shell not running")
                color: Appearance.colors.colSubtext
            }
            RippleButtonWithIcon {
                materialIcon: "keyboard_alt"
                mainText: Translation.tr("Change")
                enabled: page.sessionLayouts.length > 0
                onClicked: {
                    kbPickProc.running = false;
                    kbPickProc.running = true;
                }
                StyledToolTip {
                    text: Translation.tr("Opens the layout picker on your desktop. Applies immediately, no password needed.")
                }
            }
        }

        ConfigRow {
            StyledText {
                Layout.leftMargin: 8
                Layout.preferredWidth: 120
                text: Translation.tr("Console keymap")
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledText {
                Layout.fillWidth: true
                text: SystemSettings.consoleKeymap.length > 0
                    ? SystemSettings.consoleKeymap : Translation.tr("unset")
                color: Appearance.colors.colSubtext
            }
            StyledToolTip {
                text: Translation.tr("What the text consoles and the boot prompt use. Separate from your session layout, and only root can change it.")
            }
        }
    }

    ContentSection {
        icon: "translate"
        title: Translation.tr("Language & locale")

        ContentSubsection {
            title: Translation.tr("Shell language")
            ConfigSelectionArray {
                currentValue: Config.options.language.ui
                onSelected: newValue => Config.options.language.ui = newValue
                options: [
                    { displayName: Translation.tr("Auto (system)"), value: "auto" },
                    ...Translation.allAvailableLanguages.map(lang => ({ displayName: lang, value: lang }))
                ]
            }
        }

        ConfigRow {
            StyledText {
                Layout.leftMargin: 8
                Layout.preferredWidth: 120
                text: Translation.tr("System locale")
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledText {
                Layout.fillWidth: true
                text: SystemSettings.locale.length > 0
                    ? SystemSettings.locale : Translation.tr("unset")
                color: Appearance.colors.colSubtext
            }
            StyledToolTip {
                text: Translation.tr("What every application formats dates and numbers with. Only locales you have generated in /etc/locale.gen can be chosen, so this is shown rather than edited.")
            }
        }
    }

    ContentSection {
        icon: "nightlight"
        title: Translation.tr("Night light")

        ConfigSwitch {
            buttonIcon: "schedule"
            text: Translation.tr("Warm the screen on a schedule")
            checked: Config.options.light.night.automatic
            onCheckedChanged: Config.options.light.night.automatic = checked
        }
        ConfigRow {
            uniform: true
            MaterialTextArea {
                Layout.fillWidth: true
                enabled: Config.options.light.night.automatic
                placeholderText: Translation.tr("From, e.g. 19:00")
                text: Config.options.light.night.from
                onTextChanged: Qt.callLater(() => Config.options.light.night.from = text.trim())
            }
            MaterialTextArea {
                Layout.fillWidth: true
                enabled: Config.options.light.night.automatic
                placeholderText: Translation.tr("Until, e.g. 06:30")
                text: Config.options.light.night.to
                onTextChanged: Qt.callLater(() => Config.options.light.night.to = text.trim())
            }
        }
        ConfigSpinBox {
            icon: "thermostat"
            text: Translation.tr("Colour temperature (K)")
            value: Config.options.light.night.colorTemperature
            from: 2500
            to: 6500
            stepSize: 100
            onValueChanged: Config.options.light.night.colorTemperature = value
            StyledToolTip {
                text: Translation.tr("Lower is warmer. 6500 is daylight, so it is effectively off.")
            }
        }
    }

    ContentSection {
        icon: "battery_android_bolt"
        title: Translation.tr("Battery")

        ConfigSwitch {
            buttonIcon: "bedtime"
            text: Translation.tr("Suspend when the battery is critical")
            checked: Config.options.battery.automaticSuspend
            onCheckedChanged: Config.options.battery.automaticSuspend = checked
        }
        ConfigSpinBox {
            icon: "battery_low"
            text: Translation.tr("Warn below (%)")
            value: Config.options.battery.low
            from: 5
            to: 50
            stepSize: 5
            onValueChanged: Config.options.battery.low = value
        }
        ConfigSpinBox {
            icon: "battery_alert"
            text: Translation.tr("Suspend below (%)")
            value: Config.options.battery.suspend
            from: 1
            to: 20
            stepSize: 1
            enabled: Config.options.battery.automaticSuspend
            onValueChanged: Config.options.battery.suspend = value
        }
    }

    ContentSection {
        icon: "apps"
        title: Translation.tr("Default applications")

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.bottomMargin: 4
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("What the shell launches for these jobs. The defaults assume a KDE-ish system; change them to whatever you actually have installed.")
        }

        ConfigRow {
            StyledText {
                Layout.leftMargin: 8
                Layout.preferredWidth: 110
                text: Translation.tr("Terminal")
                color: Appearance.colors.colOnSecondaryContainer
            }
            MaterialTextArea {
                Layout.fillWidth: true
                text: Config.options.apps.terminal
                onTextChanged: Qt.callLater(() => Config.options.apps.terminal = text)
            }
        }
        ConfigRow {
            StyledText {
                Layout.leftMargin: 8
                Layout.preferredWidth: 110
                text: Translation.tr("Task manager")
                color: Appearance.colors.colOnSecondaryContainer
            }
            MaterialTextArea {
                Layout.fillWidth: true
                text: Config.options.apps.taskManager
                onTextChanged: Qt.callLater(() => Config.options.apps.taskManager = text)
            }
        }
        ConfigRow {
            StyledText {
                Layout.leftMargin: 8
                Layout.preferredWidth: 110
                text: Translation.tr("Volume mixer")
                color: Appearance.colors.colOnSecondaryContainer
            }
            MaterialTextArea {
                Layout.fillWidth: true
                text: Config.options.apps.volumeMixer
                onTextChanged: Qt.callLater(() => Config.options.apps.volumeMixer = text)
            }
        }
        ConfigRow {
            StyledText {
                Layout.leftMargin: 8
                Layout.preferredWidth: 110
                text: Translation.tr("Network")
                color: Appearance.colors.colOnSecondaryContainer
            }
            MaterialTextArea {
                Layout.fillWidth: true
                text: Config.options.apps.network
                onTextChanged: Qt.callLater(() => Config.options.apps.network = text)
            }
        }
    }
}
