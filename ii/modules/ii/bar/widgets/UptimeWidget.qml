// How long the machine has been up. SysStats already reads /proc/uptime for
// the game-playtime figure, so this costs nothing extra.
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    required property string widgetId

    readonly property bool compact: BarWidgets.get(root.widgetId, "compact") !== false
    readonly property real secs: Math.max(0, SysStats.uptimeSec)

    hoverEnabled: true
    implicitWidth: label.implicitWidth
    // A little taller than the text so the hover target is not a hairline.
    implicitHeight: label.implicitHeight + 8

    StyledText {
        id: label
        anchors.centerIn: parent
        text: {
            const s = root.secs;
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
    }

    StyledPopup {
        hoverTarget: root

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 6

            StyledPopupHeaderRow { icon: "timer"; label: Translation.tr("Uptime") }
            WidgetRow {
                Layout.minimumWidth: 180
                label: Translation.tr("Up for")
                value: {
                    const d = Math.floor(root.secs / 86400);
                    const h = Math.floor((root.secs % 86400) / 3600);
                    const m = Math.floor((root.secs % 3600) / 60);
                    return d > 0 ? `${d}d ${h}h ${m}m` : `${h}h ${m}m`;
                }
            }
            WidgetRow {
                label: Translation.tr("Booted")
                value: Qt.formatDateTime(new Date(Date.now() - root.secs * 1000), "ddd d MMM, HH:mm")
            }
        }
    }
}
