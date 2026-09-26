import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// The selected day's events, under the month grid.
ColumnLayout {
    id: agenda
    required property string date
    readonly property var events: Kalends.eventsOn(agenda.date)
    readonly property int shown: Math.min(agenda.events.length, 3)

    spacing: 3

    function clock(iso) {
        const d = new Date(iso);
        if (isNaN(d.getTime())) return "";
        const p = n => String(n).padStart(2, "0");
        return `${p(d.getHours())}:${p(d.getMinutes())}`;
    }
    function dayLabel(iso) {
        const d = new Date(iso + "T12:00:00");   // midday: no DST edge case
        return isNaN(d.getTime()) ? iso : Qt.formatDateTime(d, "ddd d MMM");
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 1
        spacing: 6
        StyledText {
            Layout.fillWidth: true
            text: agenda.dayLabel(agenda.date)
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Medium
            color: Appearance.colors.colSubtext
        }
        StyledText {
            visible: agenda.events.length > agenda.shown
            text: Translation.tr("+%1 more").arg(agenda.events.length - agenda.shown)
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
    }

    StyledText {
        visible: agenda.events.length === 0
        Layout.fillWidth: true
        text: Translation.tr("Nothing scheduled")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colOutlineVariant
    }

    Repeater {
        model: agenda.shown
        delegate: RowLayout {
            required property int index
            readonly property var ev: agenda.events[index] ?? ({})
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 3
                implicitHeight: 14
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimary
            }
            StyledText {
                Layout.preferredWidth: 42
                text: ev.all_day ? Translation.tr("all day") : agenda.clock(ev.start)
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                text: ev.summary ?? ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }
        }
    }
}
