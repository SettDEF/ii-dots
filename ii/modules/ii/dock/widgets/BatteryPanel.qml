import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: panel
    spacing: 6
    readonly property int pct: Math.round(Battery.percentage * 100)

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
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 5
        radius: Appearance.rounding.full
        color: Qt.alpha(Appearance.colors.colOnLayer0, 0.18)
        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.width * Math.max(0, Math.min(1, Battery.percentage))
            radius: parent.radius
            color: Battery.isLow ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
        }
    }
}
