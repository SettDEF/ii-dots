// Phone (KDE-Connect) card for the container drawer.  Cleaner than the
// original — no gray panel, header reads as a tappable item with status
// emphasis on the accent color when connected.
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.kdeConnect
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: card
    signal openDialog()
    implicitHeight: col.implicitHeight + 12

    readonly property var d: KdeConnectService.firstDevice
    readonly property bool connected: !!d && d.reachable

    ColumnLayout {
        id: col
        anchors {
            left: parent.left; right: parent.right; top: parent.top
            leftMargin: 4; rightMargin: 4; topMargin: 6
        }
        spacing: 8

        // ── Header ────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 44; Layout.preferredHeight: 44
                radius: 22
                color: card.connected
                    ? Appearance.colors.colPrimary
                    : Qt.alpha(Appearance.colors.colPrimary, 0.10)
                Behavior on color { ColorAnimation { duration: 160 } }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: card.connected ? "smartphone" : "phonelink_off"
                    iconSize: 22
                    fill: card.connected ? 1 : 0
                    color: card.connected
                        ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colPrimary
                    Behavior on color { ColorAnimation { duration: 160 } }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: -2
                StyledText {
                    Layout.fillWidth: true
                    text: card.d?.name ?? Translation.tr("No phone paired")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnLayer1
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        visible: card.connected
                        implicitWidth: 6; implicitHeight: 6; radius: 3
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: card.d
                            ? (card.connected
                                ? (card.d.battery >= 0
                                    ? Translation.tr("Connected · %1%").arg(card.d.battery)
                                    : Translation.tr("Connected"))
                                : Translation.tr("Offline"))
                            : Translation.tr("Open KDE Connect on your phone")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        elide: Text.ElideRight
                        color: card.connected
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colSubtext
                    }
                }
            }

            // Open-dialog chip
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 36; implicitHeight: 36
                radius: 18
                color: openHov.hovered
                    ? Qt.alpha(Appearance.colors.colPrimary, 0.18)
                    : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
                HoverHandler { id: openHov }
                TapHandler   { onTapped: card.openDialog() }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "open_in_new"; iconSize: 18
                    color: Appearance.colors.colPrimary
                }
            }
        }

        // ── Quick actions ─────────────────────────────────────────────
        KdeConnectActions {
            Layout.fillWidth: true
            device: card.d
        }
    }
}
