import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

WindowDialog {
    id: root
    backgroundHeight: 600

    property string filterText: ""
    readonly property bool isDiscovering: Bluetooth.defaultAdapter?.discovering ?? false

    readonly property var shownDevices: {
        const q = root.filterText.trim().toLowerCase();
        let list = BluetoothStatus.friendlyDeviceList ?? [];
        if (q.length > 0) {
            list = list.filter(d => {
                if (!d) return false;
                const name = (d.name ?? d.alias ?? "").toLowerCase();
                return name.indexOf(q) >= 0;
            });
        }
        return list;
    }

    // Discovery ran only when the scan button was pressed. With the button gone,
    // opening the dialog starts it and closing stops it again — discovery is not
    // free: it transmits continuously in the same 2.4GHz band the Wi-Fi radio
    // shares on this machine, so leaving it running after the dialog closes
    // would cost battery and airtime for a list nobody is looking at.
    Component.onCompleted: if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = true
    Component.onDestruction: if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = false

    WindowDialogTitle {
        text: Translation.tr("Bluetooth devices")
    }

    // Own row, full width — it shared the title's line with the scan button
    // before and had almost nothing left. Shown only once the list is long
    // enough to be worth filtering, keyed on the UNFILTERED count so typing a
    // query cannot make the field disappear from under the cursor.
    PillTextField {
        Layout.fillWidth: true
        visible: (BluetoothStatus.friendlyDeviceList?.length ?? 0) > 5 || root.filterText.length > 0
        placeholderText: Translation.tr("Filter by name…")
        text: root.filterText
        onTextChanged: root.filterText = text
    }
    WindowDialogSeparator {
        visible: !(Bluetooth.defaultAdapter?.discovering ?? false)
    }
    StyledIndeterminateProgressBar {
        visible: Bluetooth.defaultAdapter?.discovering ?? false
        Layout.fillWidth: true
        Layout.topMargin: -8
        Layout.bottomMargin: -8
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large
    }
    ColumnLayout {
        id: emptyStateCol
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        visible: root.shownDevices.length === 0
        spacing: 6
        Layout.topMargin: 20
        Layout.bottomMargin: 20

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            // Same as WifiDialog: StyledIndeterminateProgressBar above already
            // animates for the whole discovery, so this second spinner was
            // redundant. Colour and the "Searching for Bluetooth devices…" text
            // below carry the state.
            text: "bluetooth_searching"
            iconSize: 28
            color: root.isDiscovering ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: root.isDiscovering
                  ? Translation.tr("Searching for Bluetooth devices…")
                  : Translation.tr("No Bluetooth devices found")
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: Appearance.colors.colOnLayer1
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: root.isDiscovering
                  ? Translation.tr("Make sure your device is in pairing mode")
                  : Translation.tr("Try clearing your filter, or reopen this dialog to scan again")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
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
            values: root.shownDevices
        }
        delegate: BluetoothDeviceItem {
            required property BluetoothDevice modelData
            device: modelData
            anchors {
                left: parent?.left
                right: parent?.right
            }
        }
    }
    WindowDialogSeparator {}
    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Config.options.apps.bluetooth}`]);
                GlobalStates.sidebarRightOpen = false;
            }
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
