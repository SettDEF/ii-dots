// Floating sink picker invoked from the volume slider's speaker icon.
// Shows all PipeWire output devices; clicking one promotes it to the
// system default sink (Pipewire.preferredDefaultAudioSink). The volume
// slider naturally follows the default, so picking here is the same as
// "route the volume control to this device".
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

PopupWindow {
    id: root
    // Item under which the popup should appear (the slider icon).
    required property Item anchorItem
    color: "transparent"

    readonly property list<var> devices: Audio.outputDevices
    readonly property int currentDefaultId: Pipewire.defaultAudioSink?.id ?? -1

    function open() { root.visible = true }
    function close() { root.visible = false }

    function getDeviceIcon(node) {
        if (!node || !node.properties) return "volume_up";
        const formFactor = node.properties["device.form-factor"] || "";
        const iconName = node.properties["device.icon-name"] || "";
        const desc = (node.description || "").toLowerCase();

        if (formFactor === "headphone" || formFactor === "headset" || desc.includes("headphone") || desc.includes("headset")) {
            return "headphones";
        }
        if (formFactor === "speaker" || desc.includes("speaker")) {
            return "speaker";
        }
        if (formFactor === "bluetooth" || desc.includes("bluetooth")) {
            return "bluetooth";
        }
        if (formFactor === "internal" || desc.includes("internal") || desc.includes("built-in")) {
            return "laptop";
        }
        if (desc.includes("hdmi") || desc.includes("displayport") || desc.includes("monitor") || desc.includes("tv")) {
            return "tv";
        }
        return "volume_up";
    }

    anchor {
        window: anchorItem ? anchorItem.QsWindow.window : null
        gravity: Edges.Bottom
        edges: Edges.Bottom
        adjustment: PopupAdjustment.SlideY
        rect: anchorItem
            ? Qt.rect(
                anchorItem.QsWindow?.mapFromItem(anchorItem, 0, anchorItem.height + 6).x ?? 0,
                anchorItem.QsWindow?.mapFromItem(anchorItem, 0, anchorItem.height + 6).y ?? 0,
                1, 1)
            : Qt.rect(0, 0, 1, 1)
    }

    implicitWidth: panel.implicitWidth + 16
    implicitHeight: panel.implicitHeight + 16

    // Click outside dismisses.
    MouseArea {
        anchors.fill: parent
        onPressed: root.close()
    }

    Rectangle {
        id: panel
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        implicitWidth: Math.max(260, listCol.implicitWidth + 16)
        implicitHeight: listCol.implicitHeight + 16
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        // Soak inside clicks so they don't reach the dismiss MouseArea.
        MouseArea { anchors.fill: parent; preventStealing: true; onPressed: mouse => mouse.accepted = true }

        ColumnLayout {
            id: listCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.bottomMargin: 4
                text: qsTr("Output device")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                opacity: 0.75
            }

            Repeater {
                model: root.devices
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool isCurrent: modelData?.id === root.currentDefaultId
                    Layout.fillWidth: true
                    implicitHeight: 64
                    radius: 8
                    color: rowMa.containsMouse
                        ? Appearance.colors.colLayer2
                        : (isCurrent ? Qt.alpha(Appearance.colors.colPrimary, 0.08) : "transparent")
                    Behavior on color { ColorAnimation { duration: 140 } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 4

                        RowLayout {
                            id: headerRow
                            Layout.fillWidth: true
                            spacing: 8

                            MaterialSymbol {
                                text: root.getDeviceIcon(row.modelData)
                                iconSize: 18
                                color: row.isCurrent ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Audio.friendlyDeviceName(row.modelData)
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                                font.weight: row.isCurrent ? Font.DemiBold : Font.Normal
                            }

                            MaterialSymbol {
                                visible: row.isCurrent
                                text: "check"
                                iconSize: 16
                                color: Appearance.colors.colPrimary
                            }

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Audio.setDefaultSink(row.modelData)
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            RippleButton {
                                id: muteBtn
                                implicitWidth: 24
                                implicitHeight: 24
                                buttonRadius: Appearance.rounding.full
                                colBackgroundHover: Appearance.colors.colLayer3
                                colRipple: Appearance.colors.colLayer3
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: row.modelData?.audio?.muted ? "volume_off" : "volume_up"
                                    iconSize: 16
                                    color: row.modelData?.audio?.muted ? Appearance.colors.colError : Appearance.colors.colOnLayer1
                                }
                                onClicked: {
                                    if (row.modelData?.audio) {
                                        row.modelData.audio.muted = !row.modelData.audio.muted
                                    }
                                }
                            }

                            StyledSlider {
                                Layout.fillWidth: true
                                value: row.modelData?.audio?.volume ?? 0
                                onMoved: {
                                    if (row.modelData?.audio) {
                                        row.modelData.audio.volume = value
                                    }
                                }
                                configuration: StyledSlider.Configuration.S
                            }
                        }
                    }
                }
            }

            // Empty state — shouldn't happen on a working PipeWire stack but be defensive.
            StyledText {
                visible: root.devices.length === 0
                Layout.fillWidth: true
                Layout.margins: 8
                text: qsTr("No output devices")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                opacity: 0.7
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.bottomMargin: 2
                
                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    buttonRadius: 6
                    colBackground: Appearance.colors.colLayer2
                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            text: "tune"
                            iconSize: 16
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            text: Translation.tr("Volume Mixer")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                    onClicked: {
                        Quickshell.execDetached(["bash", "-c", `${Config.options.apps.volumeMixer}`]);
                        root.close();
                    }
                }
            }
        }
    }
}
