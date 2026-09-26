// Edit-mode chrome drawn over the dock: an outline plus a grab handle on the
// top edge that resizes the dock live.
import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Item {
    id: root
    visible: opacity > 0
    opacity: GlobalStates.dockEditMode ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: "transparent"
        border.width: 2
        border.color: Appearance.colors.colPrimary
    }

    Rectangle {
        id: handle
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: -3
        implicitWidth: 64
        implicitHeight: 7
        radius: Appearance.rounding.full
        color: dragArea.pressed || dragArea.containsMouse
            ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainer
        Behavior on color { ColorAnimation { duration: 120 } }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            anchors.margins: -8
            enabled: GlobalStates.dockEditMode
            hoverEnabled: true
            cursorShape: Qt.SizeVerCursor
            property real startY: 0
            property real startH: 0
            onPressed: event => {
                dragArea.startY = dragArea.mapToGlobal(event.x, event.y).y;
                dragArea.startH = Config.options.dock.height;
            }
            onPositionChanged: event => {
                if (!dragArea.pressed) return;
                // Up is taller. Rounded to 2 so a drag is not one config write
                // per pixel.
                const dy = dragArea.startY - dragArea.mapToGlobal(event.x, event.y).y;
                const next = Math.round((dragArea.startH + dy) / 2) * 2;
                Config.options.dock.height = Math.max(40, Math.min(120, next));
            }
        }
    }

    // Live readout while dragging.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: handle.bottom
        anchors.topMargin: 4
        visible: dragArea.pressed
        implicitWidth: sizeLabel.implicitWidth + 14
        implicitHeight: sizeLabel.implicitHeight + 6
        radius: Appearance.rounding.small
        color: Appearance.colors.colPrimary
        StyledText {
            id: sizeLabel
            anchors.centerIn: parent
            text: `${Math.round(Config.options.dock.height)} px`
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.family: Appearance.font.family.monospace
            color: Appearance.m3colors.m3onPrimary
        }
    }
}
