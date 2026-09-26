import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Two rising bars — a meter, so it can't be mistaken for the other tiles.
DockTile {
    id: root
    // Mid step: secondaryContainer is nearly identical to primaryContainer
    // in this palette, so it is mixed rather than picked.
    tint: ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colPrimaryContainer, 0.45)
    tooltip: Translation.tr("CPU %1%  ·  RAM %2%")
        .arg(Math.round(ResourceUsage.cpuUsage * 100))
        .arg(Math.round(ResourceUsage.memoryUsedPercentage * 100))

    component Bar: Item {
        required property real fraction
        Layout.fillHeight: true
        implicitWidth: 9
        Rectangle {
            anchors.fill: parent
            radius: 4
            color: Qt.alpha(Appearance.colors.colOnPrimary, 0.25)
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: parent.height * Math.max(0.10, Math.min(1, fraction))
            radius: 4
            color: fraction > 0.9 ? Appearance.m3colors.m3error : Appearance.colors.colOnPrimary
            Behavior on height {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    RowLayout {
        anchors.centerIn: parent
        height: parent.height - 10
        spacing: 4
        Bar { fraction: ResourceUsage.cpuUsage }
        Bar { fraction: ResourceUsage.memoryUsedPercentage }
        Bar {
            visible: DockWidgets.get("resources", "showSwap") === true
            fraction: ResourceUsage.swapUsedPercentage
        }
    }
}
