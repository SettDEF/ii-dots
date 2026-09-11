pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Scope {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panelWindow
            required property var modelData
            screen: modelData
            visible: GlobalStates.gestureMenuOpen
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            implicitWidth: 320
            implicitHeight: 320
            color: "transparent"
            WlrLayershell.namespace: "quickshell:gestureMenu"
            WlrLayershell.layer: WlrLayer.Overlay

            anchors {
                top: false
                bottom: false
                left: false
                right: false
            }

            mask: Region { item: mainCard }

            Rectangle {
                id: mainCard
                anchors.fill: parent
                color: "transparent"

                // Scale/opacity entry animation on the main card container
                scale: panelWindow.visible ? 1.0 : 0.8
                opacity: panelWindow.visible ? 1.0 : 0.0
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                Behavior on opacity { NumberAnimation { duration: 120 } }

                // Center Node (12-sided gear/cookie shape)
                MaterialShape {
                    width: 70
                    height: 70
                    anchors.centerIn: parent
                    shape: MaterialShape.Shape.Cookie12Sided
                    color: Appearance.colors.colLayer2
                    implicitSize: 70
                    
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "mouse"
                        iconSize: 28
                        color: Appearance.colors.colPrimary
                    }
                }

                // Up Segment (Overview)
                GestureNode {
                    label: "Overview"
                    icon: "dashboard"
                    active: GlobalStates.gestureDirection === "Up"
                    anchors.bottom: parent.verticalCenter
                    anchors.bottomMargin: 55
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                // Down Segment (Mixer)
                GestureNode {
                    label: "Volume Mixer"
                    icon: "volume_up"
                    active: GlobalStates.gestureDirection === "Down"
                    anchors.top: parent.verticalCenter
                    anchors.topMargin: 55
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                // Left Segment (Prev Workspace)
                GestureNode {
                    label: "Workspace Left"
                    icon: "arrow_back"
                    active: GlobalStates.gestureDirection === "Left"
                    anchors.right: parent.horizontalCenter
                    anchors.rightMargin: 55
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Right Segment (Next Workspace)
                GestureNode {
                    label: "Workspace Right"
                    icon: "arrow_forward"
                    active: GlobalStates.gestureDirection === "Right"
                    anchors.left: parent.horizontalCenter
                    anchors.leftMargin: 55
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // Material 3 morphing nodes
    component GestureNode: Item {
        required property string label
        required property string icon
        required property bool active

        width: 100
        height: 100
        
        scale: active ? 1.08 : 1.0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

        MaterialShape {
            anchors.fill: parent
            shape: active ? MaterialShape.Shape.Puffy : MaterialShape.Shape.Circle
            color: active ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
            implicitSize: 100
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2
            
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: parent.parent.icon
                iconSize: 22
                color: parent.parent.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: parent.parent.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.bold: true
                color: parent.parent.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            }
        }
    }
}
