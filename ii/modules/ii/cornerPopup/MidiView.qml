pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    required property real popupRounding
    property bool isSidebar: false

    readonly property real pad:  isSidebar ? 6  : 16
    readonly property real gap:  isSidebar ? 6  : 4
    readonly property real btnH: 56
    // Fixed device area: max 2 rows visible, scrollable if more
    readonly property real devAreaH: btnH * 2 + gap

    implicitHeight: isSidebar
        ? col.implicitHeight + pad * 2
        : col.implicitHeight + pad * 2
    radius: isSidebar ? Appearance.rounding.normal : popupRounding
    color: isSidebar ? Appearance.colors.colLayer1 : Appearance.colors.colLayer0
    border.width: isSidebar ? 0 : 1
    border.color: Appearance.colors.colLayer0Border

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.pad }
        spacing: root.gap

        // ── Header ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: "piano"
                iconSize: Appearance.font.pixelSize.larger
                color: Midi.devices.length > 0
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colSubtext
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }
            StyledText {
                text: "MIDI"
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                width: 8; height: 8; radius: 4
                color: Midi.activity ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }
            StyledText {
                text: Midi.devices.length > 0
                    ? qsTr("%1 device%2").arg(Midi.devices.length).arg(Midi.devices.length === 1 ? "" : "s")
                    : Translation.tr("No devices")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }

        // ── Device list (fixed height, scrollable) ────────────────────────────
        Item {
            Layout.fillWidth: true
            // In sidebar: fixed height regardless of device count
            // In popup: grow naturally up to all devices
            implicitHeight: isSidebar
                ? root.devAreaH
                : devCol.implicitHeight
            clip: true

            // Scrollable if sidebar and more devices than visible
            Flickable {
                anchors.fill: parent
                contentHeight: devCol.implicitHeight
                contentWidth: width
                clip: true
                interactive: isSidebar && Midi.devices.length > 0

                ScrollBar.vertical: ScrollBar {
                    policy: (isSidebar && devCol.implicitHeight > root.devAreaH)
                        ? ScrollBar.AlwaysOn
                        : ScrollBar.AlwaysOff
                }

                Column {
                    id: devCol
                    width: parent.width
                    spacing: root.gap

                    // No devices placeholder
                    Rectangle {
                        visible: Midi.devices.length === 0
                        width: parent.width
                        height: root.btnH
                        radius: height / 2
                        color: Appearance.colors.colLayer2

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            MaterialSymbol {
                                text: "cable"; iconSize: 20
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                text: Translation.tr("Connect a MIDI device")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    // Device buttons — uniform colLayer2, no inner icon square
                    Repeater {
                        model: Midi.devices
                        delegate: Rectangle {
                            id: devItem
                            required property var modelData
                            readonly property bool active: Midi.activePort === modelData.port

                            width: devCol.width
                            height: root.btnH
                            radius: active ? Appearance.rounding.large : height / 2
                            color: active ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                            Behavior on color  { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                            Behavior on radius { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }

                            HoverHandler { id: devHov }
                            TapHandler   { onTapped: Midi.activePort = devItem.modelData.port }
                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                color: devHov.hovered
                                    ? (devItem.active ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover)
                                    : "transparent"
                                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                            }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 16; rightMargin: 14; topMargin: 10; bottomMargin: 10 }
                                spacing: 10

                                MaterialSymbol {
                                    text: "piano"
                                    fill: devItem.active ? 1 : 0
                                    iconSize: 22
                                    color: devItem.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                                }
                                Column {
                                    Layout.fillWidth: true
                                    spacing: -2
                                    StyledText {
                                        width: parent.width
                                        text: devItem.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.smallie
                                        font.weight: 600
                                        elide: Text.ElideRight
                                        color: devItem.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                                    }
                                    StyledText {
                                        width: parent.width
                                        text: devItem.modelData.client + " · port " + devItem.modelData.port
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: 100
                                        elide: Text.ElideRight
                                        color: devItem.active
                                            ? ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.3)
                                            : Appearance.colors.colSubtext
                                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Last event display ────────────────────────────────────────────────
        Rectangle {
            visible: Midi.devices.length > 0
            Layout.fillWidth: true
            implicitHeight: eventRow.implicitHeight + 14
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer2

            RowLayout {
                id: eventRow
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                spacing: 10

                Rectangle {
                    visible: Midi.lastEventType !== ""
                    implicitHeight: typeLabel.implicitHeight + 6
                    implicitWidth: typeLabel.implicitWidth + 12
                    radius: height / 2
                    color: Midi.activity ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                    StyledText {
                        id: typeLabel
                        anchors.centerIn: parent
                        text: Midi.lastEventType
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.SemiBold
                        color: Midi.activity ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                    }
                }
                StyledText {
                    visible: Midi.lastEventType === ""
                    text: "—"
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    visible: Midi.lastEventType === "Note on" || Midi.lastEventType === "Note off"
                    text: Midi.noteName(Midi.lastNote)
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    font.family: Appearance.font.family.numbers
                    color: Appearance.colors.colOnLayer2
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    visible: Midi.lastEventType !== ""
                    implicitWidth: 48; implicitHeight: 4
                    radius: 2
                    color: Appearance.colors.colLayer1
                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        radius: 2
                        color: Appearance.colors.colPrimary
                        width: {
                            if (Midi.lastEventType === "Note on" || Midi.lastEventType === "Note off")
                                return parent.width * (Midi.lastVelocity / 127)
                            if (Midi.lastEventType === "CC")
                                return parent.width * (Midi.lastValue / 127)
                            return 0
                        }
                        Behavior on width { NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }
                    }
                }

                StyledText {
                    visible: Midi.lastEventType !== ""
                    text: "CH " + (Midi.lastChannel + 1)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Medium
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
