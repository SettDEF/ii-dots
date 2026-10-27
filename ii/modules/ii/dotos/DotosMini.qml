pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Scope {
    id: root

    PanelWindow {
        id: win
        visible: GlobalStates.dotosMiniOpen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.namespace: "quickshell:dotosMini"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        mask: Region { item: card }

        Component.onCompleted: GlobalFocusGrab.addDismissable(win)
        Component.onDestruction: GlobalFocusGrab.removeDismissable(win)
        Connections {
            target: GlobalFocusGrab
            function onDismissed() { GlobalStates.dotosMiniOpen = false }
        }
        function close() { GlobalStates.dotosMiniOpen = false }

        Rectangle {
            id: card
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.08 }
            width: Math.min(720, parent.width - 48)
            height: Math.min(520, parent.height - 80)
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            clip: true
            scale: 0.85
            opacity: 0

            Behavior on scale {
                NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
            }
            Behavior on opacity {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            Component.onCompleted: { scale = 1; opacity = 1 }
            onVisibleChanged: if (visible) { scale = 0.85; opacity = 0; Qt.callLater(() => { scale = 1; opacity = 1 }) }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) { win.close(); event.accepted = true }
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // ── collapsed sidebar with tabs ──
                Rectangle {
                    Layout.preferredWidth: 48
                    Layout.fillHeight: true
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        anchors { fill: parent; topMargin: 12; bottomMargin: 12 }
                        spacing: 4

                        Repeater {
                            model: [
                                { icon: "today", label: "Today" },
                                { icon: "checklist", label: "Tasks" },
                                { icon: "history", label: "History" },
                                { icon: "trending_up", label: "Progress" },
                                { icon: "library_books", label: "Library" },
                                { icon: "build", label: "Tools" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                Layout.alignment: Qt.AlignHCenter
                                radius: Appearance.rounding.small
                                color: tabMouse.containsMouse ? Appearance.colors.colLayer2 : "transparent"

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    iconSize: 20
                                    color: Appearance.colors.colOnLayer1
                                }

                                MouseArea {
                                    id: tabMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                }

                                StyledToolTip {
                                    visible: tabMouse.containsMouse
                                    text: modelData.label
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        // open full dotos
                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            Layout.alignment: Qt.AlignHCenter
                            radius: Appearance.rounding.small
                            color: openMouse.containsMouse ? Appearance.colors.colLayer2 : "transparent"

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "open_in_new"
                                iconSize: 20
                                color: Appearance.colors.colPrimary
                            }

                            MouseArea {
                                id: openMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { Todo.openApp(); win.close() }
                            }

                            StyledToolTip {
                                visible: openMouse.containsMouse
                                text: "Open Dotos"
                            }
                        }
                    }
                }

                // ── main content ──
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    // header
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        color: Appearance.colors.colLayer1

                        RowLayout {
                            anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                            spacing: 8

                            MaterialSymbol {
                                text: "checklist"
                                iconSize: 20
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: "Dotos"
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                            }
                            Rectangle {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                radius: Appearance.rounding.small
                                color: closeMouse.containsMouse ? Appearance.colors.colLayer2 : "transparent"

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: 18
                                    color: Appearance.colors.colOnLayer1
                                }

                                MouseArea {
                                    id: closeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.close()
                                }
                            }
                        }
                    }

                    // task list
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        ColumnLayout {
                            width: parent.width
                            spacing: 2
                            anchors { left: parent.left; right: parent.right; margins: 8; top: parent.top; topMargin: 8 }

                            Repeater {
                                model: Todo.open.slice(0, 12)
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 36
                                    radius: Appearance.rounding.small
                                    color: taskMouse.containsMouse ? Appearance.colors.colLayer1 : "transparent"

                                    RowLayout {
                                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                        spacing: 8

                                        MaterialSymbol {
                                            text: modelData.done ? "check_box" : "check_box_outline_blank"
                                            iconSize: 18
                                            color: modelData.done ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.title
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colOnLayer1
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            visible: modelData.priority === "high"
                                            text: "!"
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.Bold
                                            color: Appearance.m3colors.m3error
                                        }
                                    }

                                    MouseArea {
                                        id: taskMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Todo.markDone(Todo.list.findIndex(t => t.uid === modelData.uid))
                                    }
                                }
                            }

                            StyledText {
                                visible: Todo.open.length === 0
                                text: "Nothing open"
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 16
                            }
                        }
                    }
                }
            }
        }
    }
}