import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

ColumnLayout {
    id: panel
    spacing: 8

    // Own clock: the shared DateTime ticks per minute, not per second.
    SystemClock {
        id: tick
        precision: SystemClock.Seconds
    }

    readonly property bool twelve: DockWidgets.get("clock", "twelveHour") === true
    readonly property date now: tick.date

    // ISO-8601 week: the Thursday of this week decides which year's week it is.
    readonly property int weekNumber: {
        const d = new Date(panel.now.getFullYear(), panel.now.getMonth(), panel.now.getDate());
        d.setDate(d.getDate() + 3 - ((d.getDay() + 6) % 7));
        const jan4 = new Date(d.getFullYear(), 0, 4);
        return 1 + Math.round(((d - jan4) / 86400000 - 3 + ((jan4.getDay() + 6) % 7)) / 7);
    }
    readonly property int dayOfYear: {
        const start = new Date(panel.now.getFullYear(), 0, 0);
        return Math.floor((panel.now - start) / 86400000);
    }
    readonly property string utcOffset: {
        const m = -panel.now.getTimezoneOffset();
        const sign = m < 0 ? "-" : "+";
        const a = Math.abs(m);
        return `UTC${sign}${String(Math.floor(a / 60)).padStart(2, "0")}:${String(a % 60).padStart(2, "0")}`;
    }

    // ── Hero ────────────────────────────────────────────────────────────
    WidgetCard {
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatDateTime(panel.now, panel.twelve ? "hh:mm:ss" : "HH:mm:ss")
                font.pixelSize: Appearance.font.pixelSize.display
                font.weight: Font.DemiBold
                font.family: Appearance.font.family.numbers
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                visible: panel.twelve
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatDateTime(panel.now, "AP")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: Appearance.colors.colPrimary
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 2
                text: Qt.formatDateTime(panel.now, "dddd, d MMMM yyyy")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    // ── This week ───────────────────────────────────────────────────────
    WidgetCard {
        title: Translation.tr("Week %1").arg(panel.weekNumber)

        WeekRow {
            Layout.fillWidth: true
            date: panel.now
            locale: Qt.locale()
            spacing: 2

            delegate: ColumnLayout {
                required property var model
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.locale().toString(model.date, "ddd").slice(0, 2)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: Appearance.sizes.dockWidgetWindow.weekCell
                    implicitHeight: Appearance.sizes.dockWidgetWindow.weekCell
                    radius: Appearance.rounding.full
                    color: model.today ? Appearance.colors.colPrimary : "transparent"

                    StyledText {
                        anchors.centerIn: parent
                        text: model.day
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: model.today ? Font.DemiBold : Font.Normal
                        color: model.today ? Appearance.colors.colOnPrimary
                                           : Appearance.colors.colOnLayer0
                    }
                }
            }
        }
    }

    // ── Facts ───────────────────────────────────────────────────────────
    WidgetCard {
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetRow { label: Translation.tr("Uptime"); value: DateTime.uptime }
            WidgetRow { label: Translation.tr("Day of year"); value: `${panel.dayOfYear}` }
            WidgetRow { label: Translation.tr("Time zone"); value: panel.utcOffset }
        }
    }

    Item { Layout.fillHeight: true }

    WidgetLaunchRow {
        appName: "Timos"
        appPath: "/mnt/storage/dev/projects/desktop/timos/timos.qml"
    }
}
