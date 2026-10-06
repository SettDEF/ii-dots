import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: panel
    spacing: 8
    readonly property int pct: Math.round(Battery.percentage * 100)

    WidgetCard {
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol {
                text: Battery.isCharging ? "bolt" : "battery_full"
                iconSize: Appearance.font.pixelSize.huge
                fill: 1
                color: Battery.isLow ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: -2
                StyledText {
                    text: `${panel.pct}%`
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    text: !Battery.available ? Translation.tr("No battery")
                        : Battery.isCharging ? Translation.tr("Charging")
                        : Battery.isPluggedIn ? Translation.tr("Plugged in")
                        : Translation.tr("On battery")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }
        }
        WidgetBar {
            fraction: Battery.percentage
            critical: Battery.isLow
            visible: Battery.available
        }
    }
}
