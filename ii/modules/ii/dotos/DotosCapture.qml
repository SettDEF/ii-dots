pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

/**
 * Quick capture from anywhere (Super+R): one line into Dotos without leaving
 * what you are doing, and the next few things on your list under it — tick
 * one off, start its timer, or open Dotos.
 *
 * The line takes Dotos' capture syntax; the tokens light up as you type so
 * you can see what it understood: @fri 14:00  !high  #tag  ~30m  +project  /list
 */
Scope {
    id: root

    PanelWindow {
        id: win
        visible: GlobalStates.dotosCaptureOpen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.namespace: "quickshell:dotosCapture"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        mask: Region { item: card }

        Component.onCompleted: GlobalFocusGrab.addDismissable(win)
        Component.onDestruction: GlobalFocusGrab.removeDismissable(win)
        Connections {
            target: GlobalFocusGrab
            function onDismissed() { GlobalStates.dotosCaptureOpen = false }
        }
        function close() { GlobalStates.dotosCaptureOpen = false }

        // the layer surface gets focus asynchronously; ask until it lands
        Timer {
            id: focusRetry
            running: win.visible
            interval: 50
            repeat: true
            triggeredOnStart: true
            property int ticks: 0
            onRunningChanged: ticks = 0
            onTriggered: {
                input.forceActiveFocus()
                ticks++
                if ((input.activeFocus && ticks >= 3) || ticks >= 14) stop()
            }
        }
        onVisibleChanged: if (visible) { input.text = ""; root.flash = ""; Todo.reload() }

        property string flash: ""

        /// the capture tokens in the line, for the chips under it
        function tokens(line) {
            const out = []
            const re = /(^|\s)(@\S+(?:\s+\d{1,2}[:.]\d{2})?|![a-z]+|#\S+|~\d+[mhd]?|\+\S+|\/\S+|>\S+)/gi
            let m
            while ((m = re.exec(line)) !== null) {
                const t = m[2]
                const kind = t[0] === "@" ? ["event", Translation.tr("when")]
                    : t[0] === "!" ? ["priority_high", Translation.tr("priority")]
                    : t[0] === "#" ? ["sell", Translation.tr("tag")]
                    : t[0] === "~" ? ["timer", Translation.tr("estimate")]
                    : t[0] === "+" ? ["deployed_code", Translation.tr("project")]
                    : t[0] === "/" ? ["list", Translation.tr("list")] : ["swap_horiz", Translation.tr("state")]
                out.push({ text: t, icon: kind[0], what: kind[1] })
            }
            return out
        }

        function submit(stay) {
            const line = input.text.trim()
            if (!line) return
            Todo.capture(line, "", code => {
                if (code === 0) win.flash = Translation.tr("Added")
            })
            input.text = ""
            if (!stay) win.close()
        }

        Rectangle {
            id: card
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.18 }
            width: Math.min(660, parent.width - 48)
            implicitHeight: col.implicitHeight + 28
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) { win.close(); event.accepted = true }
            }

            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 10

                // ── the line ──
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 52
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    RowLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 14 }
                        spacing: 12
                        MaterialSymbol {
                            text: "add_task"
                            iconSize: 22
                            color: Appearance.colors.colPrimary
                        }
                        TextInput {
                            id: input
                            Layout.fillWidth: true
                            color: Appearance.colors.colOnLayer1
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.larger
                            selectionColor: Appearance.colors.colPrimaryContainer
                            selectedTextColor: Appearance.colors.colOnPrimaryContainer
                            clip: true
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) { win.close(); event.accepted = true }
                                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    win.submit(event.modifiers & Qt.ControlModifier); event.accepted = true
                                } else if (event.key === Qt.Key_O && (event.modifiers & Qt.ControlModifier)) {
                                    Todo.openApp(); win.close(); event.accepted = true
                                }
                            }
                            onTextChanged: if (text.length > 0) win.flash = ""
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: input.text.length === 0
                                text: win.flash.length > 0 ? win.flash + " — " + Translation.tr("add another, or Esc")
                                    : Translation.tr("Add a task…   @fri 14:00  !high  #tag  ~30m  +project")
                                color: win.flash.length > 0 ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.larger
                            }
                        }
                    }
                }

                // ── what it understood ──
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: chips.count > 0
                    Repeater {
                        id: chips
                        model: win.tokens(input.text)
                        delegate: Rectangle {
                            required property var modelData
                            implicitWidth: chipRow.implicitWidth + 18
                            implicitHeight: 26
                            radius: 13
                            color: Appearance.colors.colPrimaryContainer
                            RowLayout {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 5
                                MaterialSymbol { text: modelData.icon; iconSize: 15; color: Appearance.colors.colOnPrimaryContainer }
                                StyledText {
                                    text: modelData.text
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnPrimaryContainer
                                }
                            }
                        }
                    }
                }

                // ── up next ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    Layout.leftMargin: 4
                    StyledText {
                        text: Todo.open.length === 0 ? Translation.tr("Nothing open — a clear head")
                            : Translation.tr("Up next")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colSubtext
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        visible: Todo.open.length > 0
                        text: [Todo.overdue > 0 ? Translation.tr("%1 overdue").arg(Todo.overdue) : "",
                               Todo.dueToday > 0 ? Translation.tr("%1 today").arg(Todo.dueToday) : "",
                               Translation.tr("%1 open").arg(Todo.open.length)].filter(s => s).join("  ·  ")
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Todo.overdue > 0 ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        model: Todo.open.slice(0, 6)
                        delegate: DotosTaskRow {
                            required property var modelData
                            Layout.fillWidth: true
                            task: modelData
                        }
                    }
                }

                // ── keys ──
                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    text: Translation.tr("Enter add  ·  Ctrl+Enter add another  ·  Ctrl+O open Dotos  ·  Esc close")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }
    }
}
