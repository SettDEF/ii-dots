// The load average, from the same /proc/loadavg read SysStats already does.
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    required property string widgetId

    readonly property bool fiveMinute: BarWidgets.get(root.widgetId, "fiveMinute") === true
    readonly property real value: root.fiveMinute ? SysStats.load5 : SysStats.load1
    readonly property int cores: Math.max(1, SysStats.coreCount)

    hoverEnabled: true
    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight + 8

    StyledText {
        id: label
        anchors.centerIn: parent
        text: root.value.toFixed(2)
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.family: Appearance.font.family.monospace
        // Amber past one core's worth of work, error red past four: a number that
        // only ever looks the same is a number nobody reads.
        color: root.value >= 4 ? Appearance.m3colors.m3error
             : root.value >= 1 ? Appearance.colors.colSecondary
                               : Appearance.colors.colOnLayer1
    }

    StyledPopup {
        hoverTarget: root

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 6

            StyledPopupHeaderRow { icon: "monitoring"; label: Translation.tr("Load average") }
            // A bar full means every core busy: load is only meaningful
            // against how many cores there are to run it.
            WidgetBar {
                Layout.minimumWidth: 200
                label: Translation.tr("1 minute")
                value: SysStats.load1.toFixed(2)
                fraction: SysStats.load1 / root.cores
            }
            WidgetBar {
                label: Translation.tr("5 minutes")
                value: SysStats.load5.toFixed(2)
                fraction: SysStats.load5 / root.cores
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("%1 cores").arg(root.cores)
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }
}
