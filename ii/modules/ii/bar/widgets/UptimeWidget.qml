// How long the machine has been up. SysStats already reads /proc/uptime for
// the game-playtime figure, so this costs nothing extra.
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

StyledText {
    id: root
    required property string widgetId

    readonly property bool compact: BarWidgets.get(root.widgetId, "compact") !== false

    text: {
        const s = Math.max(0, SysStats.uptimeSec);
        const d = Math.floor(s / 86400);
        const h = Math.floor((s % 86400) / 3600);
        const m = Math.floor((s % 3600) / 60);
        if (root.compact)
            return d > 0 ? `${d}d ${h}h` : (h > 0 ? `${h}h ${m}m` : `${m}m`);
        return d > 0 ? Translation.tr("%1 d %2 h").arg(d).arg(h)
                     : Translation.tr("%1 h %2 m").arg(h).arg(m);
    }

    font.pixelSize: Appearance.font.pixelSize.smaller
    // Monospace: the figure changes every minute and a proportional font makes
    // the whole bar shuffle sideways when it does.
    font.family: Appearance.font.family.monospace
    color: Appearance.colors.colOnLayer1
    verticalAlignment: Text.AlignVCenter
}
