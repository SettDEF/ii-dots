// AI chats at a glance: how many need you, are working, have finished.
// Click: jump to the most urgent one (needs you, else the latest finished).
// Right click: mark the finished ones as seen. Hover: every chat.
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    required property string widgetId

    readonly property bool showIdle: BarWidgets.get(root.widgetId, "showIdle") === true
    readonly property int nNeed: AiActivity.needsYou.length
    readonly property int nWork: AiActivity.working.length
    readonly property int nDone: AiActivity.finished.length

    visible: root.showIdle || AiActivity.count > 0
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    implicitWidth: row.implicitWidth + 4
    implicitHeight: row.implicitHeight + 8
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) AiActivity.markAllSeen();
        else AiActivity.jump(AiActivity.urgent);
    }

    function rank(s) { return ({ needs_you: 0, working: 1, finished: 2, ready: 3 })[s.state] ?? 4; }

    // a tick so "working 3 min" stays true while the popup is open
    property int tick: 0
    Timer { interval: 1000; running: root.containsMouse; repeat: true; onTriggered: root.tick++ }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6

        MaterialSymbol {
            text: "forum"
            iconSize: Appearance.font.pixelSize.normal
            fill: root.nNeed > 0 ? 1 : 0
            color: root.nNeed > 0 ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
            // a chat waiting for you: a slow pulse, not a blink. STEPPED, once a second:
            // a running animation redraws the bar (and Hyprland recomposites it) at full
            // refresh rate for as long as it runs — a smooth pulse kept the GPU busy all day.
            Timer {
                running: root.nNeed > 0 && root.visible
                interval: 1000; repeat: true
                onTriggered: parent.opacity = parent.opacity < 1 ? 1 : 0.5
                onRunningChanged: if (!running) parent.opacity = 1
            }
        }
        // a small badge per state that is not zero: needs you · working · finished
        Repeater {
            model: [
                { n: root.nNeed, icon: "priority_high", col: Appearance.m3colors.m3error, spin: false },
                { n: root.nWork, icon: "progress_activity", col: Appearance.colors.colPrimary, spin: true },
                { n: root.nDone, icon: "check", col: Appearance.colors.colSubtext, spin: false }
            ].filter(c => c.n > 0)
            delegate: Rectangle {
                id: badge
                required property var modelData
                // one width for every badge, so the gaps between them look the same
                implicitWidth: Math.max(34, badgeRow.implicitWidth + 12)
                implicitHeight: 18
                radius: height / 2
                color: Qt.alpha(badge.modelData.col, 0.16)
                Row {
                    id: badgeRow
                    anchors.centerIn: parent
                    spacing: 2
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: badge.modelData.icon
                        iconSize: 13
                        fill: 1
                        color: badge.modelData.col
                        // stepped, 5 a second (a smooth spin redrew the bar every frame while any chat worked)
                        Timer { running: badge.modelData.spin && root.visible; interval: 200; repeat: true; onTriggered: parent.rotation = (parent.rotation + 45) % 360 }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: badge.modelData.n
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: badge.modelData.col
                    }
                }
            }
        }
    }

    StyledPopup {
        hoverTarget: root

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 6

            StyledPopupHeaderRow { icon: "forum"; label: Translation.tr("AI chats") }
            StyledText {
                visible: AiActivity.count === 0
                text: Translation.tr("No chats running")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            // most urgent first: needs you, working, finished, ready
            Repeater {
                model: AiActivity.live.slice(0).sort((a, b) => root.rank(a) - root.rank(b) || (b.updated ?? 0) - (a.updated ?? 0))
                delegate: Rectangle {
                    id: chatRow
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 400
                    implicitHeight: chat.implicitHeight + 12
                    radius: Appearance.rounding.small
                    color: rowHov.hovered ? Appearance.colors.colLayer2Hover : "transparent"
                    HoverHandler { id: rowHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: AiActivity.jump(chatRow.modelData) }
                RowLayout {
                    id: chat
                    readonly property var modelData: chatRow.modelData
                    readonly property color tone: chat.modelData.state === "needs_you" ? Appearance.m3colors.m3error
                        : chat.modelData.state === "working" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 8 }
                    spacing: 10
                    // one slot for every icon, so the names line up
                    Item {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        Layout.alignment: Qt.AlignTop
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: AiActivity.stateIcon(chat.modelData)
                            iconSize: Appearance.font.pixelSize.larger
                            fill: chat.modelData.state === "needs_you" ? 1 : 0
                            color: chat.tone
                            Timer { running: chat.modelData.state === "working" && chat.visible; interval: 200; repeat: true; onTriggered: parent.rotation = (parent.rotation + 45) % 360 }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1   // exactly the space between icon and time
                        spacing: 0
                        RowLayout {
                            spacing: 8
                            StyledText {
                                text: chat.modelData.project
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }
                            // the state as a small tinted pill
                            Rectangle {
                                implicitWidth: stateText.implicitWidth + 14
                                implicitHeight: 18
                                radius: 9
                                color: Qt.alpha(chat.tone, 0.16)
                                StyledText {
                                    id: stateText
                                    anchors.centerIn: parent
                                    text: AiActivity.stateLabel(chat.modelData)
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: chat.tone
                                }
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: AiActivity.clean(chat.modelData.state === "needs_you" ? chat.modelData.message : chat.modelData.prompt)
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 64
                        horizontalAlignment: Text.AlignRight
                        text: (root.tick, AiActivity.elapsed(chat.modelData))
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                }
            }
            StyledText {
                visible: AiActivity.count > 0
                Layout.fillWidth: true
                Layout.maximumWidth: 400
                Layout.leftMargin: 6
                Layout.topMargin: 2
                wrapMode: Text.WordWrap
                text: Translation.tr("Click a chat to jump to it · right click the chip to clear finished")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }
}
