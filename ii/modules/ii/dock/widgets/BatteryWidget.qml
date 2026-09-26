import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// The tile itself fills with the charge — a battery you read at a glance.
DockTile {
    id: root
    readonly property int pct: Math.round(Battery.percentage * 100)
    tint: Appearance.colors.colPrimaryContainer
    tooltip: Battery.isCharging ? Translation.tr("Charging — %1%").arg(root.pct)
                                : Translation.tr("Battery %1%").arg(root.pct)

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: parent.height * Math.max(0, Math.min(1, Battery.percentage))
        color: Battery.isLow ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
        opacity: 0.8
        Behavior on height {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }
    MaterialSymbol {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 4
        text: Battery.isCharging ? "bolt" : "battery_full"
        iconSize: Appearance.font.pixelSize.smallie
        fill: 1
        color: Appearance.colors.colOnPrimaryContainer
    }
    StyledText {
        visible: DockWidgets.get("battery", "showPercent") === true
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        text: `${root.pct}`
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.DemiBold
        color: Appearance.colors.colOnPrimaryContainer
    }
}
