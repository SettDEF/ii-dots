import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One Dotos task in the shell: tick circle, title, when it is due, and on
 * hover the timer and "open in Dotos". Shared by quick capture and the bar.
 */
Rectangle {
    id: row
    required property var task
    readonly property bool tracking: Todo.active?.uid === row.task.uid
    readonly property color dueColor: row.task.overdue ? Appearance.m3colors.m3error
        : row.task.bucket === "today" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext

    implicitHeight: 38
    radius: Appearance.rounding.small
    color: hov.hovered ? Appearance.colors.colLayer1Hover : "transparent"
    HoverHandler { id: hov }

    function when(t) {
        if (!t.due) return ""
        const d = new Date(t.due)
        const time = t.due_time ? Qt.formatTime(d, "HH:mm") : ""
        if (t.bucket === "today" || t.overdue && d.toDateString() === new Date().toDateString()) return time || Translation.tr("today")
        if (t.bucket === "tomorrow") return Translation.tr("tomorrow") + (time ? " " + time : "")
        const days = Math.round((d - new Date()) / 86400000)
        if (days < 0) return Translation.tr("%1d late").arg(-days)
        if (days < 7) return Qt.formatDate(d, "ddd") + (time ? " " + time : "")
        return Qt.formatDate(d, "d MMM")
    }

    RowLayout {
        anchors { fill: parent; leftMargin: 6; rightMargin: 8 }
        spacing: 8

        // tick
        Rectangle {
            implicitWidth: 26; implicitHeight: 26; radius: 13
            color: tickHov.hovered ? Appearance.colors.colLayer2Hover : "transparent"
            MaterialSymbol {
                anchors.centerIn: parent
                text: tickHov.hovered ? "check_circle" : (row.task.state === "doing" ? "radio_button_partial" : "radio_button_unchecked")
                iconSize: 20
                color: row.task.priority === "high" ? Appearance.m3colors.m3error
                    : tickHov.hovered || row.task.state === "doing" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            HoverHandler { id: tickHov; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Todo.markDone(Todo.list.findIndex(t => t.uid === row.task.uid)) }
        }
        StyledText {
            Layout.fillWidth: true
            text: row.task.title
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            visible: !hov.hovered && text.length > 0
            text: row.task.project ? "+" + row.task.project : ""
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
        StyledText {
            visible: !hov.hovered && text.length > 0
            text: row.when(row.task)
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: row.dueColor
        }
        // timer: start, or stop the running one
        RippleButton {
            visible: hov.hovered || row.tracking
            implicitWidth: 28; implicitHeight: 28
            buttonRadius: 14
            onClicked: row.tracking ? Todo.stop() : Todo.track(row.task.uid)
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: row.tracking ? "stop_circle" : "play_circle"
                iconSize: 20
                color: row.tracking ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            StyledToolTip { text: row.tracking ? Translation.tr("Stop the timer") : Translation.tr("Start the timer (timewarrior)") }
        }
    }
}
