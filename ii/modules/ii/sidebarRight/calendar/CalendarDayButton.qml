import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: button
    property string day
    property int isToday
    property bool bold
    /// "YYYY-MM-DD"; empty on the weekday header row.
    property string date: ""
    /// Set by the grid; a selected day outranks "today" visually.
    property bool selected: false

    readonly property int eventCount: button.date.length > 0 ? Kalends.countOn(button.date) : 0
    readonly property bool outside: button.isToday === -1

    Layout.fillWidth: false
    Layout.fillHeight: false
    implicitWidth: 38;
    implicitHeight: 38;

    toggled: (isToday == 1)
    buttonRadius: Appearance.rounding.small

    // Today stays filled; a different selected day reads as an outline so the
    // two states never look like two "todays".
    Rectangle {
        anchors.fill: parent
        visible: button.selected && button.isToday != 1
        radius: Appearance.rounding.small
        color: "transparent"
        border.width: 2
        border.color: Appearance.colors.colPrimary
    }
    

    // Clicking a day shows its events here rather than in a strip under the
    // grid: the grid keeps its size, and a day with nothing on it can say so
    // without permanently reserving space to do it.
    readonly property var dayEvents: button.date.length > 0 ? Kalends.eventsOn(button.date) : []
    readonly property bool popupOpen: button.selected && button.date.length > 0

    function clockOf(iso) {
        const d = new Date(iso);
        if (isNaN(d.getTime())) return "";
        const p = n => String(n).padStart(2, "0");
        return `${p(d.getHours())}:${p(d.getMinutes())}`;
    }

    /// The tooltip sizes itself to its longest line, so a 90-character summary
    /// would drag a popup across the screen.
    function shortSummary(s) {
        const t = String(s ?? "").trim();
        return t.length > 30 ? t.slice(0, 29) + "\u2026" : (t.length > 0 ? t : Translation.tr("(untitled)"));
    }

    contentItem: Item {
        anchors.fill: parent

        PopupToolTip {
            extraVisibleCondition: false
            alternativeVisibleCondition: button.popupOpen
            text: {
                const evs = button.dayEvents;
                if (evs.length === 0) return Translation.tr("Nothing scheduled");
                const lines = evs.slice(0, 6).map(e => (e.all_day
                    ? Translation.tr("all day")
                    : button.clockOf(e.start)) + "   " + button.shortSummary(e.summary));
                if (evs.length > 6) lines.push(Translation.tr("+%1 more").arg(evs.length - 6));
                return lines.join("\n");
            }
        }

        StyledText {
            anchors.centerIn: parent
            // Nudged up so the dots below never collide with the numeral.
            anchors.verticalCenterOffset: button.eventCount > 0 ? -3 : 0
            text: button.day
            horizontalAlignment: Text.AlignHCenter
            font.weight: button.bold ? Font.DemiBold : Font.Normal
            color: (button.isToday == 1) ? Appearance.m3colors.m3onPrimary : 
                (button.isToday == 0) ? Appearance.colors.colOnLayer1 : 
                Appearance.colors.colOutlineVariant

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        // Up to three dots, then a bar — counting past three is not something
        // anyone reads off a 38px cell.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 5
            spacing: 2
            visible: button.eventCount > 0
            Repeater {
                model: Math.min(button.eventCount, 3)
                delegate: Rectangle {
                    implicitWidth: button.eventCount > 3 ? 8 : 4
                    implicitHeight: 3
                    radius: Appearance.rounding.full
                    color: (button.isToday == 1) ? Appearance.m3colors.m3onPrimary
                         : button.outside ? Appearance.colors.colOutlineVariant
                         : Appearance.colors.colPrimary
                }
            }
        }
    }
}
