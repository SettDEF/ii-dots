import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts

// Sound settings for notifications: the default, a per-app override for every
// app that has actually sent one, and a URL field to add new sounds.
ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: 8

    // Only apps seen in history — a free-text field here would just invite
    // typos that silently never match an incoming notification's appName.
    readonly property var knownApps: {
        const seen = [];
        for (const n of (Notifications.list ?? [])) {
            const a = n?.appName ?? "";
            if (a.length > 0 && seen.indexOf(a) === -1) seen.push(a);
        }
        return seen.sort();
    }
    readonly property var lib: NotificationSounds.library

    function indexOfRef(ref) { return root.lib.findIndex(s => s.ref === ref); }

    ConfigSwitch {
        buttonIcon: "volume_up"
        text: Translation.tr("Play a sound for notifications")
        checked: Config.options.notifications.sound
        onCheckedChanged: Config.options.notifications.sound = checked
    }

    // ── Default sound ────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        enabled: Config.options.notifications.sound

        StyledText {
            text: Translation.tr("Default sound")
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.small
        }
        Item { Layout.fillWidth: true }
        StyledComboBoxSearch {
            Layout.preferredWidth: 230
            model: root.lib
            textRole: "label"
            currentIndex: root.indexOfRef(Config.options.notifications.soundName)
            onActivated: idx => Config.options.notifications.soundName = root.lib[idx].ref
        }
        RippleButton {
            implicitWidth: 36; implicitHeight: 36
            buttonRadius: Appearance.rounding.full
            onClicked: NotificationSounds.play(Config.options.notifications.soundName)
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "play_arrow"; iconSize: 20
                color: Appearance.colors.colOnLayer1
            }
            StyledToolTip { text: Translation.tr("Preview") }
        }
    }

    // ── Add a sound from a link ──────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        MaterialTextField {
            id: urlField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Paste a link to a sound file…")
            onAccepted: addBtn.clicked()
        }
        RippleButtonWithIcon {
            id: addBtn
            materialIcon: "download"
            mainText: Translation.tr("Add")
            enabled: urlField.text.trim().length > 0 && !root.busy
            onClicked: {
                root.busy = true;
                NotificationSounds.addFromUrl(urlField.text.trim(), "");
            }
        }
    }
    property bool busy: false
    property string status: ""

    StyledText {
        visible: root.status.length > 0
        Layout.fillWidth: true
        text: root.status
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: root.status.startsWith("✓") ? Appearance.colors.colSubtext
                                           : Appearance.m3colors.m3error
    }

    Connections {
        target: NotificationSounds
        function onAdded(name) {
            root.busy = false; urlField.text = "";
            root.status = "✓ " + Translation.tr("Added \"%1\"").arg(name);
        }
        function onAddFailed(reason) { root.busy = false; root.status = reason; }
    }

    // ── Per app ──────────────────────────────────────────────────────────
    StyledText {
        visible: root.knownApps.length > 0
        Layout.topMargin: 6
        text: Translation.tr("Per application")
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.DemiBold
    }
    StyledText {
        visible: root.knownApps.length === 0
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: Translation.tr("No apps have sent a notification yet. They appear here once they do.")
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
    }

    Repeater {
        model: root.knownApps
        delegate: RowLayout {
            id: appRow
            required property string modelData
            Layout.fillWidth: true
            spacing: 8
            enabled: Config.options.notifications.sound

            readonly property string ownRef: NotificationSounds.appSounds[appRow.modelData] ?? ""

            StyledText {
                Layout.fillWidth: true
                text: appRow.modelData
                elide: Text.ElideRight
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
            }
            StyledComboBoxSearch {
                Layout.preferredWidth: 200
                // -1 shows nothing, which is what "follows the default" means.
                model: root.lib
                textRole: "label"
                currentIndex: appRow.ownRef.length > 0 ? root.indexOfRef(appRow.ownRef) : -1
                onActivated: idx => NotificationSounds.setAppSound(appRow.modelData, root.lib[idx].ref)
            }
            RippleButton {
                implicitWidth: 32; implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                onClicked: NotificationSounds.play(NotificationSounds.soundFor(appRow.modelData))
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "play_arrow"; iconSize: 17
                    color: Appearance.colors.colOnLayer1
                }
            }
            RippleButton {
                implicitWidth: 32; implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                enabled: appRow.ownRef.length > 0
                onClicked: NotificationSounds.setAppSound(appRow.modelData, "")
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "restart_alt"; iconSize: 17
                    color: Appearance.colors.colSubtext
                }
                StyledToolTip { text: Translation.tr("Use the default") }
            }
        }
    }
}
