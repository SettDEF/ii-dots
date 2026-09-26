import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root
    property string formattedDate: Qt.locale().toString(DateTime.clock.date, "dddd, MMMM dd, yyyy")
    property string formattedTime: DateTime.time
    property string formattedUptime: DateTime.uptime
    property string todosSection: getUpcomingTodos()

    // Built fresh on every hover, so this is the right place to ask.
    Component.onCompleted: Kalends.refreshNext()

    function getUpcomingTodos() {
        const unfinishedTodos = Todo.list.filter(function (item) {
            return !item.done;
        });
        if (unfinishedTodos.length === 0) {
            return Translation.tr("No pending tasks");
        }

        // Limit to first 5 todos to keep popup manageable
        const limitedTodos = unfinishedTodos.slice(0, 5);
        let todoText = limitedTodos.map(function (item, index) {
            return `  ${index + 1}. ${item.content}`;
        }).join('\n');

        if (unfinishedTodos.length > 5) {
            todoText += `\n  ${Translation.tr("... and %1 more").arg(unfinishedTodos.length - 5)}`;
        }

        return todoText;
    }

    ColumnLayout {
        id: columnLayout
        anchors.centerIn: parent
        spacing: 4

        StyledPopupHeaderRow {
            icon: "calendar_month"
            label: root.formattedDate
        }

        StyledPopupValueRow {
            icon: "timelapse"
            label: Translation.tr("System uptime:")
            value: root.formattedUptime
        }

        // Next event. Asked for when this popup is built, not polled: the
        // popup only exists while hovered, so a closed bar costs nothing.
        StyledPopupValueRow {
            visible: Kalends.nextEvent !== null
            icon: "event_upcoming"
            label: Translation.tr("Next:")
            value: Kalends.nextLabel()
            emphasized: true
        }
        StyledText {
            visible: Kalends.nextEvent !== null
            Layout.fillWidth: true
            Layout.leftMargin: 4
            horizontalAlignment: Text.AlignLeft
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnSurfaceVariant
            text: Kalends.nextEvent?.summary ?? ""
        }

        // Tasks
        Column {
            spacing: 0
            Layout.fillWidth: true

            StyledPopupValueRow {
                icon: "checklist"
                label: Translation.tr("To Do:")
                value: ""
            }

            StyledText {
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.Wrap
                color: Appearance.colors.colOnSurfaceVariant
                text: root.todosSection
            }
        }
    }
}
