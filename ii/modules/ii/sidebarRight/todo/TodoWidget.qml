import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * The sidebar's To Do: Dotos, at a glance. One line to capture a task (Dotos
 * syntax: "Dentist @fri 14:00 !high +health"), what is being tracked now, and
 * the open tasks grouped like Dotos. N focuses the capture line, Esc leaves it.
 */
Item {
    id: root
    property int tick: 0
    Timer { interval: 30000; running: root.visible && !!Todo.active; repeat: true; onTriggered: root.tick++ }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_N && !capture.activeFocus) {
            capture.forceActiveFocus();
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors { fill: parent; rightMargin: 14; topMargin: 12 }
        spacing: 10

        // ── summary + actions ──
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 4
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                // the Dotos page header: a title over a mono summary
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Tasks")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: {
                        if (Todo.error) return Todo.error;
                        if (!Todo.loaded) return Translation.tr("loading…");
                        const parts = [Translation.tr("%1 open").arg(Todo.open.length)];
                        if (Todo.overdue > 0) parts.push(Translation.tr("%1 overdue").arg(Todo.overdue));
                        if (Todo.dueToday > 0) parts.push(Translation.tr("%1 today").arg(Todo.dueToday));
                        if (Todo.doing.length > 0) parts.push(Translation.tr("%1 doing").arg(Todo.doing.length));
                        return parts.join(" · ");
                    }
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Todo.error ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                }
            }
            Repeater {
                model: [
                    { icon: "undo", tip: Translation.tr("Undo the last change"), run: () => Todo.undo() },
                    { icon: "open_in_new", tip: Translation.tr("Open Dotos"), run: () => Todo.openApp("tasks") }
                ]
                delegate: Rectangle {
                    id: headBtn
                    required property var modelData
                    implicitWidth: 28; implicitHeight: 28; radius: 14
                    color: headHov.hovered ? Appearance.colors.colLayer2Hover : "transparent"
                    MaterialSymbol { anchors.centerIn: parent; text: headBtn.modelData.icon; iconSize: 18; color: Appearance.colors.colSubtext }
                    HoverHandler { id: headHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: headBtn.modelData.run() }
                    StyledToolTip { extraVisibleCondition: false; alternativeVisibleCondition: headHov.hovered; text: headBtn.modelData.tip }
                }
            }
        }

        // ── capture ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            border.width: capture.activeFocus ? 1 : 0
            border.color: Appearance.colors.colPrimary
            RowLayout {
                anchors { fill: parent; leftMargin: 12; rightMargin: 6 }
                spacing: 10
                MaterialSymbol { text: "add_task"; iconSize: 18; color: capture.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colSubtext }
                TextField {
                    id: capture
                    Layout.fillWidth: true
                    background: null
                    padding: 0
                    color: Appearance.colors.colOnLayer2
                    font.pixelSize: Appearance.font.pixelSize.small
                    renderType: Text.NativeRendering
                    selectionColor: Appearance.colors.colSecondaryContainer
                    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                    placeholderText: Translation.tr("New task…  @fri 14:00 !high +project")
                    placeholderTextColor: Appearance.colors.colSubtext
                    onAccepted: {
                        if (text.trim().length === 0) return;
                        Todo.capture(text);
                        text = "";
                    }
                    Keys.onEscapePressed: { text = ""; root.forceActiveFocus(); }
                }
                Rectangle {
                    visible: capture.text.trim().length > 0
                    implicitWidth: 28; implicitHeight: 28; radius: 14
                    color: Appearance.colors.colPrimary
                    MaterialSymbol { anchors.centerIn: parent; text: "arrow_upward"; iconSize: 17; color: Appearance.colors.colOnPrimary }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: capture.accepted() }
                }
            }
        }

        // ── being tracked now ──
        Rectangle {
            Layout.fillWidth: true
            visible: !!Todo.active
            implicitHeight: 36
            radius: Appearance.rounding.small
            color: Qt.alpha(Appearance.colors.colPrimary, 0.14)
            RowLayout {
                anchors { fill: parent; leftMargin: 10; rightMargin: 4 }
                spacing: 8
                Rectangle {
                    implicitWidth: 8; implicitHeight: 8; radius: 4
                    color: Appearance.colors.colPrimary
                    SequentialAnimation on opacity {
                        running: !!Todo.active && root.visible
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 900 }
                        NumberAnimation { to: 1; duration: 900 }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Todo.active?.title ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    text: (root.tick, Todo.active ? (() => {
                        const m = Math.floor((Date.now() / 1000 - (Todo.active.since ?? 0)) / 60);
                        return m >= 60 ? `${Math.floor(m / 60)} h ${m % 60} m` : `${m} min`;
                    })() : "")
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colPrimary
                }
                Rectangle {
                    implicitWidth: 28; implicitHeight: 28; radius: 14
                    color: stopHov.hovered ? Qt.alpha(Appearance.colors.colPrimary, 0.2) : "transparent"
                    MaterialSymbol { anchors.centerIn: parent; text: "stop"; iconSize: 18; fill: 1; color: Appearance.colors.colPrimary }
                    HoverHandler { id: stopHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Todo.stop() }
                    StyledToolTip { extraVisibleCondition: false; alternativeVisibleCondition: stopHov.hovered; text: Translation.tr("Stop the timer") }
                }
            }
        }

        TaskList {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            tick: root.tick
            taskList: Todo.list.map((item, i) => Object.assign({}, item, { originalIndex: i }))
        }
    }
}
