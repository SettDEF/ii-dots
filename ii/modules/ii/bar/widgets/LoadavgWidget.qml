// The load average, from the same /proc/loadavg read SysStats already does.
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

StyledText {
    id: root
    required property string widgetId

    readonly property bool fiveMinute: BarWidgets.get(root.widgetId, "fiveMinute") === true
    readonly property real value: root.fiveMinute ? SysStats.load5 : SysStats.load1

    text: root.value.toFixed(2)
    font.pixelSize: Appearance.font.pixelSize.smaller
    font.family: Appearance.font.family.monospace
    // Amber past one core's worth of work, error red past four: a number that
    // only ever looks the same is a number nobody reads.
    color: root.value >= 4 ? Appearance.m3colors.m3error
         : root.value >= 1 ? Appearance.colors.colSecondary
                           : Appearance.colors.colOnLayer1
    verticalAlignment: Text.AlignVCenter
}
