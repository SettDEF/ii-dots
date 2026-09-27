//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings
import qs.modules.common.functions

ApplicationWindow {
    id: root
    property string firstRunFilePath: FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property real contentPadding: 8
    property bool showNextTime: false
    visible: true
    onClosing: {
        Quickshell.execDetached(["notify-send", Translation.tr("Welcome app"), Translation.tr("Enjoy! You can reopen the welcome app any time with <tt>Super+Shift+Alt+/</tt>. To open the settings app, hit <tt>Super+I</tt>"), "-a", "Shell"]);
        Qt.quit();
    }
    title: Translation.tr("illogical-impulse Welcome")

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        Config.readWriteDelay = 0 // Welcome app always only sets one var at a time so delay isn't needed
    }

    minimumWidth: 600
    minimumHeight: 400
    width: 900
    height: 650
    color: Appearance.m3colors.m3background

    Process {
        id: konachanWallProc
        property string status: ""
        command: ["bash", "-c", Quickshell.shellPath("scripts/colors/random/random_konachan_wall.sh")]
        stdout: SplitParser {
            onRead: data => {
                console.log(`Konachan wall proc output: ${data}`);
                konachanWallProc.status = data.trim();
            }
        }
    }

    Process {
        id: translationProc
        property string locale: ""
        command: [Directories.aiTranslationScriptPath, translationProc.locale]
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: contentPadding
        }

        Item {
            // Titlebar
            visible: Config.options?.windows.showTitlebar
            Layout.fillWidth: true
            implicitHeight: Math.max(welcomeText.implicitHeight, windowControlsRow.implicitHeight)
            StyledText {
                id: welcomeText
                anchors {
                    left: Config.options.windows.centerTitle ? undefined : parent.left
                    horizontalCenter: Config.options.windows.centerTitle ? parent.horizontalCenter : undefined
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("Hi there! First things first...")
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    variableAxes: Appearance.font.variableAxes.title
                }
            }
            RowLayout { // Window controls row
                id: windowControlsRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: Translation.tr("Show next time")
                }
                StyledSwitch {
                    id: showNextTimeSwitch
                    checked: root.showNextTime
                    scale: 0.6
                    Layout.alignment: Qt.AlignVCenter
                    onCheckedChanged: {
                        if (checked) {
                            Quickshell.execDetached(["rm", root.firstRunFilePath]);
                        } else {
                            Quickshell.execDetached(["bash", "-c", `echo '${StringUtils.shellSingleQuoteEscape(root.firstRunFileContent)}' > '${StringUtils.shellSingleQuoteEscape(root.firstRunFilePath)}'`]);
                        }
                    }
                }
                RippleButton {
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 35
                    implicitHeight: 35
                    onClicked: root.close()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 20
                    }

                    StyledToolTip {
                        text: Translation.tr("Tip: Close a window with Super+Q")
                    }
                }
            }
        }

        Rectangle {
            // Content container
            color: Appearance.m3colors.m3surfaceContainerLow
            radius: Appearance.rounding.windowRounding - root.contentPadding
            implicitHeight: contentColumn.implicitHeight
            implicitWidth: contentColumn.implicitWidth
            Layout.fillWidth: true
            Layout.fillHeight: true

            SectionRail {
                id: sectionRail
                anchors {
                    left: parent.left; top: parent.top; bottom: parent.bottom
                    margins: 10
                }
                flickable: contentColumn
                column: contentColumn.contentItem
            }

            ContentPage {
                id: contentColumn
                anchors {
                    left: sectionRail.visible ? sectionRail.right : parent.left
                    right: parent.right
                    top: parent.top
                    bottom: parent.bottom
                }
                forceWidth: true
                baseWidth: 560

                ContentSection {
                    Layout.fillWidth: true
                    icon: "language"
                    title: Translation.tr("Language")

                    ContentSubsection {
                        title: Translation.tr("Select language")
                        ConfigSelectionArray {
                            id: languageSelector
                            currentValue: Config.options.language.ui
                            onSelected: newValue => {
                                Config.options.language.ui = newValue;
                            }
                            options: [
                                {
                                    displayName: Translation.tr("Auto (System)"),
                                    value: "auto"
                                },
                                ...Translation.allAvailableLanguages.map(lang => {
                                    return {
                                        displayName: lang,
                                        value: lang
                                    };
                                })]
                        }
                    }

                    NoticeBox {
                        Layout.fillWidth: true
                        text: Translation.tr("Language not listed or incomplete translations?\nYou can choose to generate translations for it with Gemini.\n1. Open the left sidebar with Super+A, set model to Gemini (if it isn't already)\n2. Type /key, hit Enter and follow the instructions\n3. Type /key YOUR_API_KEY\n4. Type the locale of your language below and press Generate")
                    }

                    ContentSubsection {
                        title: Translation.tr("Generate translation with Gemini")
                        
                        ConfigRow {
                            MaterialTextArea {
                                id: localeInput
                                Layout.fillWidth: true
                                placeholderText: Translation.tr("Locale code, e.g. fr_FR, de_DE, zh_CN...")
                                text: Config.options.language.ui === "auto" ? Qt.locale().name : Config.options.language.ui
                            }
                            RippleButtonWithIcon {
                                id: generateTranslationBtn
                                Layout.fillHeight: true
                                nerdIcon: ""
                                enabled: !translationProc.running || (translationProc.locale !== localeInput.text.trim())
                                mainText: enabled ? Translation.tr("Generate\nTypically takes 2 minutes") : Translation.tr("Generating...\nDon't close this window!")
                                onClicked: {
                                    translationProc.locale = localeInput.text.trim();
                                    translationProc.running = false;
                                    translationProc.running = true;
                                }
                            }
                        }
                    }
                }

                SystemBasicsSection {}

                ContentSection {
                    icon: "wifi"
                    title: Translation.tr("Network")

                    ConfigRow {
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: Appearance.colors.colOnLayer0
                            text: !SystemRequirements.has("nmcli")
                                    ? Translation.tr("NetworkManager is not installed, so there is nothing to configure here.")
                                : Network.ethernet ? Translation.tr("Connected over Ethernet.")
                                : Network.wifiStatus === "connected"
                                    ? Translation.tr("Connected to %1.").arg(Network.networkName)
                                : Network.wifiStatus === "limited"
                                    ? Translation.tr("Connected to %1, but with no route out — a captive portal, probably.").arg(Network.networkName)
                                : Translation.tr("Not connected. You will want this before installing anything below.")
                        }
                        RippleButtonWithIcon {
                            buttonRadius: Appearance.rounding.small
                            visible: SystemRequirements.has("nmcli")
                            materialIcon: "wifi_find"
                            mainText: Translation.tr("Wi-Fi")
                            onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""),
                                                                "ipc", "call", "wifi", "open"])
                        }
                    }
                }

                ContentSection {
                    icon: "screenshot_monitor"
                    title: Translation.tr("Bar")

                    ConfigRow {
                        ContentSubsection {
                            title: Translation.tr("Bar position")
                            ConfigSelectionArray {
                                currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                                onSelected: newValue => {
                                    Config.options.bar.bottom = (newValue & 1) !== 0;
                                    Config.options.bar.vertical = (newValue & 2) !== 0;
                                }
                                options: [
                                    {
                                        displayName: Translation.tr("Top"),
                                        icon: "arrow_upward",
                                        value: 0 // bottom: false, vertical: false
                                    },
                                    {
                                        displayName: Translation.tr("Left"),
                                        icon: "arrow_back",
                                        value: 2 // bottom: false, vertical: true
                                    },
                                    {
                                        displayName: Translation.tr("Bottom"),
                                        icon: "arrow_downward",
                                        value: 1 // bottom: true, vertical: false
                                    },
                                    {
                                        displayName: Translation.tr("Right"),
                                        icon: "arrow_forward",
                                        value: 3 // bottom: true, vertical: true
                                    }
                                ]
                            }
                        }
                        ContentSubsection {
                            title: Translation.tr("Bar style")

                            ConfigSelectionArray {
                                currentValue: Config.options.bar.cornerStyle
                                onSelected: newValue => {
                                    Config.options.bar.cornerStyle = newValue; // Update local copy
                                }
                                options: [
                                    {
                                        displayName: Translation.tr("Hug"),
                                        icon: "line_curve",
                                        value: 0
                                    },
                                    {
                                        displayName: Translation.tr("Float"),
                                        icon: "page_header",
                                        value: 1
                                    },
                                    {
                                        displayName: Translation.tr("Rect"),
                                        icon: "toolbar",
                                        value: 2
                                    }
                                ]
                            }
                        }
                    }
                }

                ContentSection {
                    icon: "format_paint"
                    title: Translation.tr("Style & wallpaper")

                    ButtonGroup {
                        Layout.alignment: Qt.AlignHCenter
                        LightDarkPreferenceButton {
                            dark: false
                        }
                        LightDarkPreferenceButton {
                            dark: true
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        RippleButtonWithIcon {
                            id: rndWallBtn
                            visible: Config.options.policies.weeb === 1
                            Layout.alignment: Qt.AlignHCenter
                            buttonRadius: Appearance.rounding.small
                            materialIcon: "ifl"
                            mainText: konachanWallProc.running ? Translation.tr("Be patient...") : Translation.tr("Random: Konachan")
                            onClicked: {
                                console.log(konachanWallProc.command.join(" "));
                                konachanWallProc.running = true;
                            }
                            StyledToolTip {
                                text: Translation.tr("Random SFW Anime wallpaper from Konachan\nImage is saved to ~/Pictures/Wallpapers")
                            }
                        }
                        RippleButtonWithIcon {
                            materialIcon: "wallpaper"
                            StyledToolTip {
                                text: Translation.tr("Pick wallpaper image on your system")
                            }
                            onClicked: {
                                Quickshell.execDetached([`${Directories.wallpaperSwitchScriptPath}`]);
                            }
                            mainContentComponent: Component {
                                RowLayout {
                                    spacing: 10
                                    StyledText {
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        text: Translation.tr("Choose file")
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                    RowLayout {
                                        spacing: 3
                                        KeyboardKey {
                                            key: "Ctrl"
                                        }
                                        KeyboardKey {
                                            key: "󰖳"
                                        }
                                        StyledText {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: "+"
                                        }
                                        KeyboardKey {
                                            key: "T"
                                        }
                                    }
                                }
                            }
                        }
                    }

                    NoticeBox {
                        Layout.fillWidth: true
                        text: Translation.tr("Change any time later with /dark, /light, /wallpaper in the launcher\nIf the shell's colors aren't changing:\n    1. Open the right sidebar with Super+N\n    2. Click \"Reload Hyprland & Quickshell\" in the top-right corner")
                    }
                }

                ContentSection {
                    icon: "rule"
                    title: Translation.tr("Policies")

                    ConfigRow {
                        Layout.fillWidth: true

                        ContentSubsection {
                            title: "Weeb"

                            ConfigSelectionArray {
                                currentValue: Config.options.policies.weeb
                                onSelected: newValue => {
                                    Config.options.policies.weeb = newValue;
                                }
                                options: [
                                    {
                                        displayName: Translation.tr("No"),
                                        icon: "close",
                                        value: 0
                                    },
                                    {
                                        displayName: Translation.tr("Yes"),
                                        icon: "check",
                                        value: 1
                                    },
                                    {
                                        displayName: Translation.tr("Closet"),
                                        icon: "ev_shadow",
                                        value: 2
                                    }
                                ]
                            }
                        }

                        ContentSubsection {
                            title: "AI"

                            ConfigSelectionArray {
                                currentValue: Config.options.policies.ai
                                onSelected: newValue => {
                                    Config.options.policies.ai = newValue;
                                }
                                options: [
                                    {
                                        displayName: Translation.tr("No"),
                                        icon: "close",
                                        value: 0
                                    },
                                    {
                                        displayName: Translation.tr("Yes"),
                                        icon: "check",
                                        value: 1
                                    },
                                    {
                                        displayName: Translation.tr("Local only"),
                                        icon: "sync_saved_locally",
                                        value: 2
                                    }
                                ]
                            }
                        }
                    }
                }

                ContentSection {
                    icon: "inventory_2"
                    title: Translation.tr("What's missing")

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        text: Translation.tr("A feature whose tool is absent hides itself rather than erroring, which is why half of this can be missing without saying so. Nothing here is required.")
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: SystemRequirements.checked && SystemRequirements.missingRelevant.length === 0
                        color: Appearance.colors.colOnLayer0
                        text: Translation.tr("Everything optional is installed.")
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        visible: SystemRequirements.missingRelevant.length > 0

                        Repeater {
                            model: SystemRequirements.missingRelevant
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8

                                MaterialSymbol {
                                    text: "remove"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    Layout.preferredWidth: 150
                                    text: modelData.pkg
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer0
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 5
                        visible: SystemRequirements.missingRelevant.length > 0

                        RippleButtonWithIcon {
                            id: copyInstallButton
                            property bool copied: false
                            buttonRadius: Appearance.rounding.small
                            materialIcon: copied ? "check" : "content_copy"
                            mainText: copied ? Translation.tr("Copied")
                                             : Translation.tr("Copy install command")
                            onClicked: {
                                Quickshell.clipboardText = SystemRequirements.installCommand();
                                copyInstallButton.copied = true;
                                copiedResetTimer.restart();
                            }
                            Timer {
                                id: copiedResetTimer
                                interval: 1500
                                onTriggered: copyInstallButton.copied = false
                            }
                        }
                        RippleButtonWithIcon {
                            buttonRadius: Appearance.rounding.small
                            materialIcon: "refresh"
                            mainText: Translation.tr("Check again")
                            onClicked: SystemRequirements.refresh()
                        }
                    }
                }

                ContentSection {
                    icon: "system_update"
                    title: Translation.tr("Updates")

                    ConfigRow {
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: Appearance.colors.colOnLayer0
                            text: !ShellUpdates.available
                                    ? Translation.tr("Not a git checkout, so the shell cannot update itself.")
                                : ShellUpdates.behind > 0
                                    ? Translation.tr("%1 update(s) waiting for the shell.").arg(ShellUpdates.behind)
                                : Translation.tr("The shell is up to date.")
                        }
                        RippleButtonWithIcon {
                            buttonRadius: Appearance.rounding.small
                            visible: ShellUpdates.available
                            enabled: !ShellUpdates.checking
                            materialIcon: "refresh"
                            mainText: Translation.tr("Check")
                            onClicked: ShellUpdates.check()
                        }
                        RippleButtonWithIcon {
                            buttonRadius: Appearance.rounding.small
                            visible: ShellUpdates.updateAvailable
                            enabled: ShellUpdates.canApply
                            materialIcon: "download"
                            mainText: Translation.tr("Update")
                            onClicked: ShellUpdates.apply()
                        }
                    }

                    ConfigRow {
                        visible: Updates.available
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: Appearance.colors.colOnLayer0
                            text: Updates.count > 0
                                ? Translation.tr("%1 system package(s) can be updated.").arg(Updates.count)
                                : Translation.tr("System packages are up to date.")
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "notifications"
                        text: Translation.tr("Tell me when a shell update is available")
                        checked: Config.options.updates.shell.notify
                        onCheckedChanged: Config.options.updates.shell.notify = checked
                    }
                }

                ContentSection {
                    icon: "build"
                    title: Translation.tr("Maintenance")

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        text: Translation.tr("The shell reloads itself when its files change, so these are for when something is stuck rather than for everyday use.")
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 5

                        RippleButtonWithIcon {
                            buttonRadius: Appearance.rounding.small
                            materialIcon: "refresh"
                            mainText: Translation.tr("Reload shell")
                            onClicked: Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "shell", "reload"])
                        }
                        RippleButtonWithIcon {
                            buttonRadius: Appearance.rounding.small
                            materialIcon: "restart_alt"
                            mainText: Translation.tr("Reload both")
                            onClicked: Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "shell", "reloadAll"])
                        }
                        RippleButtonWithIcon {
                            buttonRadius: Appearance.rounding.small
                            materialIcon: "description"
                            mainText: Translation.tr("Config file")
                            onClicked: Quickshell.execDetached(["xdg-open",
                                `${Directories.config}/illogical-impulse/config.json`])
                        }
                        RippleButtonWithIcon {
                            id: clearCacheButton
                            property bool done: false
                            buttonRadius: Appearance.rounding.small
                            materialIcon: clearCacheButton.done ? "check" : "mop"
                            mainText: clearCacheButton.done ? Translation.tr("Cleared")
                                                            : Translation.tr("Clear caches")
                            // Thumbnails and the QML cache only. Not walltune,
                            // whose output IS the current wallpaper.
                            onClicked: {
                                Quickshell.execDetached(["bash", "-c",
                                    `rm -rf '${Directories.cache}/quickshell/qmlcache' '${Directories.cache}/quickshell/media'`]);
                                clearCacheButton.done = true;
                                clearCacheResetTimer.restart();
                            }
                            Timer {
                                id: clearCacheResetTimer
                                interval: 1500
                                onTriggered: clearCacheButton.done = false
                            }
                        }
                    }
                }

                ContentSection {
                    icon: "bug_report"
                    title: Translation.tr("Diagnostics")

                    ConfigRow {
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: Appearance.colors.colOnLayer0
                            text: ShellUpdates.version.length > 0
                                ? Translation.tr("Version %1").arg(ShellUpdates.version)
                                : Translation.tr("Not a git checkout, so there is no version to report.")
                        }
                        RippleButtonWithIcon {
                            id: copyDiagButton
                            property bool copied: false
                            buttonRadius: Appearance.rounding.small
                            materialIcon: copyDiagButton.copied ? "check" : "content_copy"
                            mainText: copyDiagButton.copied ? Translation.tr("Copied")
                                                            : Translation.tr("Copy system info")
                            // What a bug report needs and nobody remembers to
                            // include. No hostname, no user, no network names.
                            onClicked: {
                                Quickshell.clipboardText =
                                    `shell: ${ShellUpdates.version}\n`
                                    + `missing: ${SystemRequirements.missingRelevant.map(r => r.pkg).join(" ") || "none"}\n`
                                    + `asus: ${SystemRequirements.isAsus}\n`
                                    + `bar: position=${Config.options.bar.bottom ? "bottom" : Config.options.bar.vertical ? "side" : "top"}`
                                    + ` style=${Config.options.bar.cornerStyle}\n`
                                    + `dark: ${Appearance.m3colors.darkmode}`;
                                copyDiagButton.copied = true;
                                copyDiagResetTimer.restart();
                            }
                            Timer {
                                id: copyDiagResetTimer
                                interval: 1500
                                onTriggered: copyDiagButton.copied = false
                            }
                        }
                    }
                }

                ContentSection {
                    icon: "info"
                    title: Translation.tr("Info")

                    Flow {
                        Layout.fillWidth: true
                        spacing: 5

                        RippleButtonWithIcon {
                            materialIcon: "keyboard_alt"
                            onClicked: {
                                Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "cheatsheet", "toggle"]);
                            }
                            mainContentComponent: Component {
                                RowLayout {
                                    spacing: 10
                                    StyledText {
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        text: Translation.tr("Keybinds")
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                    RowLayout {
                                        spacing: 3
                                        KeyboardKey {
                                            key: "󰖳"
                                        }
                                        StyledText {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: "+"
                                        }
                                        KeyboardKey {
                                            key: "/"
                                        }
                                    }
                                }
                            }
                        }

                        RippleButtonWithIcon {
                            materialIcon: "settings"
                            mainText: Translation.tr("All settings")
                            onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""),
                                                                "ipc", "call", "settings", "open"])
                        }
                        RippleButtonWithIcon {
                            materialIcon: "menu_book"
                            mainText: Translation.tr("Read me")
                            onClicked: Qt.openUrlExternally("https://github.com/SettDEF/ii-dots#readme")
                        }
                        RippleButtonWithIcon {
                            nerdIcon: ""
                            mainText: Translation.tr("Source")
                            onClicked: Qt.openUrlExternally("https://github.com/SettDEF/ii-dots")
                        }
                        RippleButtonWithIcon {
                            materialIcon: "bug_report"
                            mainText: Translation.tr("Report a problem")
                            onClicked: Qt.openUrlExternally("https://github.com/SettDEF/ii-dots/issues/new")
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }

                // The last thing on the page should be the way out of it.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        text: Translation.tr("None of this is final — all of it is in the settings, under Super+I.")
                    }
                    PrimaryActionButton {
                        buttonText: Translation.tr("Start using it")
                        onClicked: root.close()
                    }
                }
            }
        }
    }
}
