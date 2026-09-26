import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Battery detail popup, as a grid of tiles.
 *
 * Rows of label-then-value made every reading look equally important. The
 * charge is the thing you opened this for, so it gets a wide tile and the
 * bar; the rest are small tiles you can scan.
 *
 * Tile widths are fixed: StyledPopup centres on the hover target and clamps
 * only the left edge, so anything that grows with its text gets clipped near
 * the right of the screen.
 */
StyledPopup {
    id: root

    readonly property color levelColor: Battery.isLowAndNotCharging ? Appearance.m3colors.m3error
        : Battery.isCharging ? Appearance.colors.colPrimary
        : Appearance.colors.colOnSurfaceVariant

    readonly property int pct: Math.round(Battery.percentage * 100)
    readonly property bool full: Battery.chargeState == 4

    function hms(s) {
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
        return h > 0 ? `${h}h ${m}m` : `${m}m`;
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 6

        StyledPopupHeaderRow {
            icon: "battery_android_full"
            label: Translation.tr("Battery")
        }

        // Hero: the charge, its bar, and what it is doing.
        StyledPopupTile {
            wide: true
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    MaterialSymbol {
                        text: Battery.isCharging ? "battery_charging_full" : "battery_android_full"
                        iconSize: Appearance.font.pixelSize.larger
                        fill: 1
                        color: root.levelColor
                    }
                    StyledText {
                        text: `${root.pct}%`
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.DemiBold
                        color: root.levelColor
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        text: root.full ? Translation.tr("Full")
                            : Battery.isCharging ? Translation.tr("Charging")
                            : Translation.tr("On battery")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 4
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer2
                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        // Clamped: UPower can report just over 100% on a full cell.
                        width: parent.width * Math.max(0, Math.min(1, Battery.percentage))
                        radius: parent.radius
                        color: root.levelColor
                    }
                }
            }
        }

        GridLayout {
            columns: 2
            columnSpacing: 6
            rowSpacing: 6

            StyledPopupTile {
                visible: !root.full && (Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty) > 0
                         && Battery.energyRate > 0.01
                icon: "schedule"
                label: Battery.isCharging ? Translation.tr("Time to full") : Translation.tr("Time to empty")
                value: root.hms(Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty)
            }
            StyledPopupTile {
                visible: !(!root.full && Battery.energyRate == 0)
                icon: "bolt"
                label: root.full ? Translation.tr("State")
                     : Battery.isCharging ? Translation.tr("Charging at") : Translation.tr("Draw")
                value: root.full ? Translation.tr("Charged") : `${Battery.energyRate.toFixed(1)} W`
            }
            StyledPopupTile {
                icon: "heart_check"
                label: Translation.tr("Health")
                value: `${Battery.health.toFixed(0)}%`
                // 80% is the usual warranty floor for laptop cells.
                valueColor: Battery.health < 80 ? Appearance.m3colors.m3error
                          : Battery.health < 85 ? Appearance.m3colors.m3tertiary
                          : Appearance.colors.colOnSurfaceVariant
            }
            StyledPopupTile {
                icon: "power"
                label: Translation.tr("Power")
                value: Battery.isPluggedIn ? Translation.tr("Plugged in") : Translation.tr("Battery")
            }
        }
    }
}
