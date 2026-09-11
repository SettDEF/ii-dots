// Standalone VPN widget — the expanded form of the VPN tile, in the same
// visual language as RogProfileSwitcher: transparent track, a circular thumb
// carrying the accent, label text alongside.
//
// Tap the thumb to connect/disconnect. Tap the text side to open the VPN half
// of the connectivity popup, alongside Wi-Fi and Bluetooth, where servers and
// the leak check live — a tile is the wrong place to pick one of many servers.
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: track
    property real pad: 2
    property real btnH: 56

    Layout.fillWidth: true
    width: parent ? parent.width : 0
    height: btnH
    implicitHeight: btnH
    radius: btnH / 2
    color: "transparent"

    readonly property bool on: Vpn.connected
    readonly property bool configured: Vpn.nordAvailable || Vpn.profiles.length > 0
    readonly property real thumbDiameter: height - pad * 2

    // ── Thumb: the connect/disconnect control ─────────────────────────────
    Rectangle {
        id: thumb
        x: track.pad
        anchors.verticalCenter: parent.verticalCenter
        width: track.thumbDiameter
        height: track.thumbDiameter
        radius: width / 2
        color: track.on ? Appearance.colors.colPrimary
             : thumbMa.containsMouse ? Appearance.colors.colLayer2Hover
             : Appearance.colors.colLayer2
        Behavior on color { ColorAnimation { duration: 180 } }

        MaterialSymbol {
            anchors.centerIn: parent
            text: Vpn.busy ? "hourglass_top"
                : track.on ? "lock" : "lock_open"
            iconSize: 24
            color: track.on ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnLayer2
        }

        MouseArea {
            id: thumbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (!track.configured) { GlobalStates.connectivityVpnOpen = true; return; }
                if (Vpn.connected) Vpn.disconnect();
                else Vpn.connectTo(Vpn.profiles[0] ?? { country: "" });
            }
        }
        StyledToolTip {
            text: track.configured
                ? (track.on ? Translation.tr("Disconnect") : Translation.tr("Connect"))
                : Translation.tr("No VPN configured")
        }
    }

    // ── Label: opens the panel ────────────────────────────────────────────
    ColumnLayout {
        anchors {
            left: thumb.right
            leftMargin: 12
            right: parent.right
            rightMargin: 14
            verticalCenter: parent.verticalCenter
        }
        spacing: 0

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("VPN")
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer2
            elide: Text.ElideRight
        }
        StyledText {
            Layout.fillWidth: true
            text: Vpn.busy ? Translation.tr("Working…")
                : track.on ? (Vpn.activeCountry || Vpn.activeName || Translation.tr("Connected"))
                : track.configured ? Translation.tr("Not connected")
                : Translation.tr("Not set up")
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
        }
    }

    MouseArea {
        anchors { left: thumb.right; top: parent.top; bottom: parent.bottom; right: parent.right }
        cursorShape: Qt.PointingHandCursor
        onClicked: GlobalStates.connectivityVpnOpen = true
    }
}
