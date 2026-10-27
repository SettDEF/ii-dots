import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * The sidebar's task list, drawn like Dotos' Tasks page: flat rows under
 * coloured group headings (Overdue, Today, Tomorrow, This week…), an accent
 * ring to tick, the title, a flag for high priority, a +project tag in its
 * project colour and the due date in mono at the right. "Done this week"
 * folds at the end. Hover a row for the timer and delete.
 */
Item {
    id: root
    required property var taskList          // Todo.list, each with originalIndex
    property int listBottomPadding: 16
    // with nothing open, what you finished is the interesting part: shown, not folded
    property bool showDone: root.open.length === 0
    property int tick: 0                    // re-evaluates the tracked time

    readonly property var open: root.taskList.filter(t => !t.done)
    readonly property var done: root.taskList.filter(t => t.done)
    readonly property var groups: {
        const order = ["doing", "overdue", "today", "tomorrow", "week", "later", "someday", "inbox"];
        const by = {};
        for (const t of root.open) {
            const g = Todo.group(t);
            if (!by[g]) by[g] = [];
            by[g].push(t);
        }
        const out = order.filter(g => by[g]).map(g => ({ key: g, tasks: by[g] }));
        for (const g in by) if (!order.includes(g)) out.push({ key: g, tasks: by[g] });
        return out;
    }

    component Tag: Rectangle {
        id: tag
        property string text
        property color tone: Appearance.colors.colSubtext
        implicitWidth: tagText.implicitWidth + 10
        implicitHeight: 17
        radius: 6
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(tag.tone, 0.6)
        StyledText {
            id: tagText
            anchors.centerIn: parent
            text: tag.text
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: tag.tone
        }
    }

    component TaskRow: Rectangle {
        id: row
        required property var task
        readonly property bool tracked: (Todo.active?.uid ?? "") === row.task.uid
        readonly property string project: row.task.project ?? ""
        readonly property bool showMeta: !row.task.done && (row.project.length > 0 || !!row.task.estimate_min || row.tracked)
        implicitHeight: Math.max(38, body.implicitHeight + 14)
        radius: Appearance.rounding.small
        color: row.tracked ? Qt.alpha(Appearance.colors.colPrimary, 0.10)
            : hov.hovered ? Appearance.colors.colLayer1Hover : "transparent"
        Behavior on color { ColorAnimation { duration: 110 } }
        HoverHandler { id: hov }

        RowLayout {
            id: body
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 8; rightMargin: 8 }
            spacing: 10

            // the ring: accent, filled when done, ticks on hover
            Rectangle {
                id: check
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 1
                implicitWidth: 18; implicitHeight: 18; radius: 9
                readonly property color ring: row.task.done ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                color: row.task.done ? Qt.alpha(Appearance.colors.colSubtext, 0.35) : checkHov.hovered ? Qt.alpha(check.ring, 0.22) : "transparent"
                border.width: row.task.done ? 0 : 1.5
                border.color: check.ring
                Behavior on color { ColorAnimation { duration: 110 } }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: row.task.done || checkHov.hovered
                    text: "check"
                    iconSize: 13
                    color: row.task.done ? Appearance.colors.colOnLayer1 : check.ring
                }
                HoverHandler { id: checkHov; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: row.task.done ? Todo.markUnfinished(row.task.originalIndex) : Todo.markDone(row.task.originalIndex)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    Layout.fillWidth: true
                    text: row.task.title ?? row.task.content ?? ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.strikeout: row.task.done
                    color: row.task.done ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
                }
                RowLayout {
                    visible: row.showMeta
                    spacing: 6
                    StyledText {
                        visible: row.tracked
                        text: "● " + (root.tick, Todo.active ? Math.max(0, Math.floor((Date.now() / 1000 - (Todo.active.since ?? 0)) / 60)) + " min" : "")
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colPrimary
                    }
                    Tag {
                        visible: row.project.length > 0
                        text: "+" + row.project
                        tone: Todo.colorOf(row.project)
                    }
                    StyledText {
                        visible: !!row.task.estimate_min
                        text: (row.task.estimate_min ?? 0) >= 60 ? `${Math.round(row.task.estimate_min / 6) / 10}h` : `${row.task.estimate_min}m`
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            // right: flag + due; on hover the row's actions take their place
            Item {
                Layout.alignment: Qt.AlignTop
                implicitWidth: Math.max(right.implicitWidth, actions.visible ? actions.implicitWidth : 0)
                implicitHeight: 20
                RowLayout {
                    id: right
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    opacity: actions.visible ? 0 : 1
                    MaterialSymbol {
                        visible: row.task.priority === "high" && !row.task.done
                        text: "flag"
                        fill: 1
                        iconSize: 14
                        color: Appearance.m3colors.m3error
                    }
                    StyledText {
                        readonly property string due: row.task.done ? "" : Todo.dueLabel(row.task)
                        visible: due.length > 0
                        text: due
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: row.task.overdue ? Appearance.m3colors.m3error
                            : row.task.bucket === "today" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }
                }
                Row {
                    id: actions
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    visible: hov.hovered || row.tracked
                    spacing: 0
                    Repeater {
                        model: row.task.done ? ["delete"] : row.tracked && !hov.hovered ? ["stop"] : [row.tracked ? "stop" : "play_arrow", "delete"]
                        delegate: Rectangle {
                            id: act
                            required property string modelData
                            width: 26; height: 26; radius: 13
                            color: actHov.hovered ? Appearance.colors.colLayer2Hover : "transparent"
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: act.modelData
                                iconSize: 17
                                fill: act.modelData === "stop" ? 1 : 0
                                color: act.modelData === "delete" && actHov.hovered ? Appearance.m3colors.m3error
                                    : act.modelData === "stop" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }
                            HoverHandler { id: actHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: act.modelData === "delete" ? Todo.deleteItem(row.task.originalIndex)
                                    : act.modelData === "stop" ? Todo.stop() : Todo.track(row.task.uid)
                            }
                            StyledToolTip {
                                extraVisibleCondition: false
                                alternativeVisibleCondition: actHov.hovered
                                text: act.modelData === "delete" ? Translation.tr("Delete")
                                    : act.modelData === "stop" ? Translation.tr("Stop the timer") : Translation.tr("Start the timer")
                            }
                        }
                    }
                }
            }
        }
    }

    component GroupHeading: Item {
        id: heading
        required property string key
        property int count: 0
        property bool foldable: false
        property bool folded: false
        signal toggled()
        implicitHeight: 28
        HoverHandler { id: headHov; enabled: heading.foldable; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: heading.foldable; onTapped: heading.toggled() }
        RowLayout {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 8; rightMargin: 6 }
            spacing: 7
            StyledText {
                text: Todo.groupLabel(heading.key)
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: heading.key === "overdue" ? Appearance.m3colors.m3error
                    : heading.key === "today" || heading.key === "doing" ? Appearance.colors.colPrimary
                    : heading.key === "done" ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
            }
            StyledText {
                text: heading.count
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
            Item { Layout.fillWidth: true }
            MaterialSymbol {
                visible: heading.foldable
                text: "expand_more"
                iconSize: 18
                color: headHov.hovered ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                rotation: heading.folded ? 0 : 180
                Behavior on rotation { NumberAnimation { duration: 160 } }
            }
        }
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.implicitHeight + root.listBottomPadding
        clip: true
        showScrollBar: contentHeight > height + 1

        ColumnLayout {
            id: col
            // room for the scrollbar only when there is one
            width: flick.width - (flick.showScrollBar ? 12 : 0)
            spacing: 10

            // nothing open: one quiet line, the Dotos empty state
            RowLayout {
                visible: Todo.loaded && root.open.length === 0
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.topMargin: 4
                spacing: 10
                MaterialSymbol { text: "task_alt"; iconSize: 20; color: Appearance.colors.colPrimary }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("All clear — nothing open")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }

            Repeater {
                model: root.groups
                delegate: ColumnLayout {
                    id: group
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 0
                    GroupHeading { Layout.fillWidth: true; key: group.modelData.key; count: group.modelData.tasks.length }
                    Repeater {
                        model: group.modelData.tasks
                        delegate: TaskRow {
                            required property var modelData
                            Layout.fillWidth: true
                            task: modelData
                        }
                    }
                }
            }

            ColumnLayout {
                visible: root.done.length > 0
                Layout.fillWidth: true
                spacing: 0
                GroupHeading {
                    Layout.fillWidth: true
                    key: "done"
                    count: root.done.length
                    foldable: true
                    folded: !root.showDone
                    onToggled: root.showDone = !root.showDone
                }
                Repeater {
                    model: root.showDone ? root.done : []
                    delegate: TaskRow {
                        required property var modelData
                        Layout.fillWidth: true
                        task: modelData
                    }
                }
            }
        }
    }
}
