import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    spacing: 8

    WidgetCard {
        WidgetBar {
            label: Translation.tr("CPU")
            fraction: ResourceUsage.cpuUsage
            value: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
        }
        WidgetBar {
            label: Translation.tr("Memory")
            fraction: ResourceUsage.memoryUsedPercentage
            value: `${Math.round(ResourceUsage.memoryUsedPercentage * 100)}%`
        }
        WidgetBar {
            label: Translation.tr("Swap")
            fraction: ResourceUsage.swapUsedPercentage
            value: `${Math.round(ResourceUsage.swapUsedPercentage * 100)}%`
        }
    }
}
