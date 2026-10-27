// Dotos in the bar: the timer while one runs, else the next thing to do.
// Click: quick capture. Right click: open Dotos. Hover: the list, tickable.
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.modules.ii.dotos
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    required property string widgetId

    readonly property bool showNext: BarWidgets.get(root.widgetId, "showNext") !== false
    readonly property int maxWidth: BarWidgets.get(root.widgetId, "maxWidth") ?? 220
    readonly property string launchPage: BarWidgets.get(root.widgetId, "launchPage") ?? "home"
    readonly property var active: Todo.active
    readonly property bool alert: Todo.overdue > 0

    // collapsed by default; right click toggles
    property bool expanded: false
    property real expandProgress: 0

    Behavior on expandProgress {
        NumberAnimation {
            duration: 250
            easing.type: Easing.OutBack
            easing.overshoot: 1.3
        }
    }

    onExpandedChanged: expandProgress = expanded ? 1 : 0

    // a tick so the timer counts while it is shown
    property int tick: 0
    Timer { interval: 1000; running: !!root.active; repeat: true; onTriggered: root.tick++ }
    function dur(s) {
        s = Math.max(0, Math.floor(s))
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60)
        return h > 0 ? `${h}:${String(m).padStart(2, "0")}` : `${m}m`
    }

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    implicitWidth: row.implicitWidth + 4
    // Shrinks with the bar (BarWidget): the title elides first, down to the
    // icon and the counts, so a long task never pushes the bar over the clock.
    readonly property real minimumWidth: row.implicitWidth - (title.visible ? Math.min(title.implicitWidth, root.maxWidth) + row.spacing : 0) + 4
    implicitHeight: row.implicitHeight + 8
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) root.expanded = !root.expanded
        else if (mouse.button === Qt.MiddleButton && root.active) Todo.stop()
        else if (mouse.button === Qt.LeftButton) Todo.openApp(root.launchPage)
        else GlobalStates.dotosCaptureOpen = !GlobalStates.dotosCaptureOpen
    }

    RowLayout {
        id: row
        anchors { left: parent.left; right: parent.right; leftMargin: 4; rightMargin: 4; verticalCenter: parent.verticalCenter }
        spacing: 8

        MaterialSymbol {
            text: root.active ? "timer" : "checklist"
            iconSize: Appearance.font.pixelSize.normal
            fill: root.active || root.alert ? 1 : 0
            color: root.alert ? Appearance.m3colors.m3error
                : root.active ? Appearance.colors.colPrimary : Appearance.colors.colPrimary
        }
        StyledText {
            id: title
            visible: expandProgress > 0.01 && text.length > 0
            opacity: expandProgress
            scale: 0.8 + 0.2 * expandProgress
            transformOrigin: Item.Left
            Layout.fillWidth: true
            Layout.maximumWidth: root.maxWidth
            elide: Text.ElideRight
            text: root.active ? root.active.title
                : root.showNext && Todo.next ? Todo.next.title : ""
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            visible: expandProgress > 0.01 && !!root.active
            opacity: expandProgress
            scale: 0.8 + 0.2 * expandProgress
            transformOrigin: Item.Left
            text: (root.tick, root.dur(Date.now() / 1000 - (root.active?.since ?? 0)))
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colPrimary
        }
        StyledText {
            visible: expandProgress > 0.01 && !root.active && (Todo.overdue + Todo.dueToday) > 0
            opacity: expandProgress
            scale: 0.8 + 0.2 * expandProgress
            transformOrigin: Item.Left
            text: Todo.overdue > 0 ? "!" + Todo.overdue : String(Todo.dueToday)
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.alert ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
        }
    }

    StyledPopup {
        hoverTarget: root

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 6

            StyledPopupHeaderRow { icon: "checklist"; label: "Dotos" }
            StyledText {
                visible: Todo.open.length === 0
                text: Translation.tr("Nothing open")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            Repeater {
                model: Todo.open.slice(0, 8)
                delegate: DotosTaskRow {
                    required property var modelData
                    Layout.preferredWidth: 360
                    task: modelData
                }
            }
            // quick actions
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                StyledText {
                    text: Translation.tr("Left: open Dotos · Right: toggle · Middle: stop")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
