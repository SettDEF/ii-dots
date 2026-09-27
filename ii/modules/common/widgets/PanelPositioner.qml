import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root
    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    required property var window
    required property var stateObject
    property string defaultAlign: "right"
    property bool vertical: false

    property real dragStartX: 0
    property real dragStartY: 0
    property real windowStartX: 0
    property real windowStartY: 0

    function alignToDefault() {
        stateObject.hasCustomPos = false;
        if (defaultAlign === "bottom") {
            alignToBottomCenter();
        } else if (defaultAlign === "right") {
            alignToCenterRight();
        } else if (defaultAlign === "left") {
            alignToCenterLeft();
        }
    }

    function alignToCenterRight() {
        var screenWidth = window.screen.width;
        var screenHeight = window.screen.height;
        var marginX = Appearance.sizes.hyprlandGapsOut + 12;
        var newX = screenWidth - window.implicitWidth - marginX;
        var newY = (screenHeight - window.implicitHeight) / 2;
        savePosition(newX, newY);
    }

    function alignToCenterLeft() {
        var screenWidth = window.screen.width;
        var screenHeight = window.screen.height;
        var marginX = Appearance.sizes.hyprlandGapsOut + 12;
        var newX = marginX;
        var newY = (screenHeight - window.implicitHeight) / 2;
        savePosition(newX, newY);
    }

    function alignToBottomCenter() {
        var screenWidth = window.screen.width;
        var screenHeight = window.screen.height;
        var marginY = Appearance.sizes.hyprlandGapsOut + 12;
        var newX = (screenWidth - window.implicitWidth) / 2;
        var newY = screenHeight - window.implicitHeight - marginY;
        savePosition(newX, newY);
    }

    function alignToTopCenter() {
        var screenWidth = window.screen.width;
        var screenHeight = window.screen.height;
        var marginY = Appearance.sizes.hyprlandGapsOut + 12;
        var newX = (screenWidth - window.implicitWidth) / 2;
        var newY = marginY;
        savePosition(newX, newY);
    }

    function alignToCenter() {
        var screenWidth = window.screen.width;
        var screenHeight = window.screen.height;
        var newX = (screenWidth - window.implicitWidth) / 2;
        var newY = (screenHeight - window.implicitHeight) / 2;
        savePosition(newX, newY);
    }

    function savePosition(newX, newY) {
        var screenWidth = window.screen.width;
        var screenHeight = window.screen.height;

        newX = Math.max(0, Math.min(screenWidth - window.implicitWidth, newX));
        newY = Math.max(0, Math.min(screenHeight - window.implicitHeight, newY));

        window.margins.left = newX;
        window.margins.top = newY;

        stateObject.x = newX;
        stateObject.y = newY;
        stateObject.hasCustomPos = true;
    }

    Component.onCompleted: {
        window.anchors.top = true;
        window.anchors.left = true;
        window.anchors.bottom = false;
        window.anchors.right = false;

        if (stateObject.hasCustomPos) {
            window.margins.left = stateObject.x;
            window.margins.top = stateObject.y;
        } else {
            alignToDefault();
        }
    }

    GridLayout {
        id: layout
        anchors.fill: parent
        columns: root.vertical ? 1 : -1
        rows: root.vertical ? -1 : 1
        rowSpacing: 4
        columnSpacing: 4

        // 1. Drag Handle
        Rectangle {
            id: dotGrip
            implicitWidth: 24
            implicitHeight: 24
            radius: 12
            color: dragMa.pressed
                ? Appearance.colors.colPrimary
                : (dragMa.containsMouse ? Appearance.colors.colLayer2Hover : ColorUtils.transparentize(Appearance.colors.colLayer2Hover))
            Behavior on color { ColorAnimation { duration: 150 } }

            Rectangle {
                anchors.centerIn: parent
                width: 8
                height: 8
                radius: 4
                color: dragMa.pressed
                    ? Appearance.m3colors.m3onPrimary
                    : Appearance.colors.colOnLayer0
            }

            MouseArea {
                id: dragMa
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.SizeAllCursor

                onPressed: (mouse) => {
                    root.dragStartX = mouse.x;
                    root.dragStartY = mouse.y;
                    root.windowStartX = root.window.margins.left;
                    root.windowStartY = root.window.margins.top;
                }

                onPositionChanged: (mouse) => {
                    if (!pressed) return;
                    var dx = mouse.x - root.dragStartX;
                    var dy = mouse.y - root.dragStartY;

                    var targetX = root.window.margins.left + dx;
                    var targetY = root.window.margins.top + dy;

                    var screenWidth = root.window.screen.width;
                    var screenHeight = root.window.screen.height;
                    var marginX = Appearance.sizes.hyprlandGapsOut + 12;
                    var marginY = Appearance.sizes.hyprlandGapsOut + 12;

                    // Edge Snapping
                    if (targetX < marginX + 20 && targetX > marginX - 20) {
                        targetX = marginX;
                    } else if (targetX < 20) {
                        targetX = 0;
                    }

                    if (targetX > screenWidth - root.window.implicitWidth - marginX - 20 &&
                        targetX < screenWidth - root.window.implicitWidth - marginX + 20) {
                        targetX = screenWidth - root.window.implicitWidth - marginX;
                    } else if (targetX > screenWidth - root.window.implicitWidth - 20) {
                        targetX = screenWidth - root.window.implicitWidth;
                    }

                    if (targetY < marginY + 20 && targetY > marginY - 20) {
                        targetY = marginY;
                    } else if (targetY < 20) {
                        targetY = 0;
                    }

                    if (targetY > screenHeight - root.window.implicitHeight - marginY - 20 &&
                        targetY < screenHeight - root.window.implicitHeight - marginY + 20) {
                        targetY = screenHeight - root.window.implicitHeight - marginY;
                    } else if (targetY > screenHeight - root.window.implicitHeight - 20) {
                        targetY = screenHeight - root.window.implicitHeight;
                    }

                    // Center Snapping
                    var centerX = (screenWidth - root.window.implicitWidth) / 2;
                    if (Math.abs(targetX - centerX) < 20) {
                        targetX = centerX;
                    }

                    var centerY = (screenHeight - root.window.implicitHeight) / 2;
                    if (Math.abs(targetY - centerY) < 20) {
                        targetY = centerY;
                    }

                    // Window-to-window snapping (Magnet)
                    if (root.stateObject === Persistent.states.touchpad) {
                        var osk = GlobalStates.oskWindow;
                        if (osk && osk.visible) {
                            var oskX = osk.margins.left;
                            var oskY = osk.margins.top;
                            var oskW = osk.implicitWidth;
                            var oskH = osk.implicitHeight;

                            if (Math.abs(targetX - (oskX + oskW)) < 25) {
                                targetX = oskX + oskW + 8;
                            } else if (Math.abs((targetX + root.window.implicitWidth) - oskX) < 25) {
                                targetX = oskX - root.window.implicitWidth - 8;
                            }

                            if (Math.abs((targetY + root.window.implicitHeight) - oskY) < 25) {
                                targetY = oskY - root.window.implicitHeight - 8;
                            } else if (Math.abs(targetY - (oskY + oskH)) < 25) {
                                targetY = oskY + oskH + 8;
                            }

                            if (Math.abs(targetY - oskY) < 20) {
                                targetY = oskY;
                            } else if (Math.abs((targetY + root.window.implicitHeight) - (oskY + oskH)) < 20) {
                                targetY = oskY + oskH - root.window.implicitHeight;
                            }
                        }
                    } else if (root.stateObject === Persistent.states.osk) {
                        var tp = GlobalStates.touchpadWindow;
                        if (tp && tp.visible) {
                            var tpX = tp.margins.left;
                            var tpY = tp.margins.top;
                            var tpW = tp.implicitWidth;
                            var tpH = tp.implicitHeight;

                            if (Math.abs(targetX - (tpX + tpW)) < 25) {
                                targetX = tpX + tpW + 8;
                            } else if (Math.abs((targetX + root.window.implicitWidth) - tpX) < 25) {
                                targetX = tpX - root.window.implicitWidth - 8;
                            }

                            if (Math.abs((targetY + root.window.implicitHeight) - tpY) < 25) {
                                targetY = tpY - root.window.implicitHeight - 8;
                            } else if (Math.abs(targetY - (tpY + tpH)) < 25) {
                                targetY = tpY + tpH + 8;
                            }

                            if (Math.abs(targetY - tpY) < 20) {
                                targetY = tpY;
                            } else if (Math.abs((targetY + root.window.implicitHeight) - (tpY + tpH)) < 20) {
                                targetY = tpY + tpH - root.window.implicitHeight;
                            }
                        }
                    }

                    root.savePosition(targetX, targetY);
                }
            }
        }

        // 2. Align Option Menu
        Rectangle {
            id: alignBtn
            implicitWidth: 24
            implicitHeight: 24
            radius: 12
            color: alignHov.hovered ? Appearance.colors.colLayer2Hover : "transparent"
            HoverHandler { id: alignHov }
            TapHandler {
                onTapped: {
                    const mx = root.vertical ? alignBtn.width : 0;
                    const my = root.vertical ? 0 : alignBtn.height;
                    const pt = alignBtn.mapToItem(alignMenu.parent, mx, my);
                    const items = [
                        { icon: "restart_alt", label: qsTr("Default"), onTriggered: () => root.alignToDefault() },
                        { icon: "dock_to_left", label: qsTr("Left Side"), onTriggered: () => root.alignToCenterLeft() },
                        { icon: "dock_to_right", label: qsTr("Right Side"), onTriggered: () => root.alignToCenterRight() },
                        { icon: "align_vertical_bottom", label: qsTr("Bottom Center"), onTriggered: () => root.alignToBottomCenter() },
                        { icon: "align_vertical_top", label: qsTr("Top Center"), onTriggered: () => root.alignToTopCenter() },
                        { icon: "center_focus_strong", label: qsTr("Screen Center"), onTriggered: () => root.alignToCenter() }
                    ];
                    alignMenu.popup(pt.x, pt.y, items);
                }
            }
            MaterialSymbol {
                anchors.centerIn: parent
                text: "grid_view"
                iconSize: 16
                color: Appearance.colors.colOnLayer0
            }
        }

        // 3. Reset Button
        Rectangle {
            id: resetBtn
            implicitWidth: 24
            implicitHeight: 24
            radius: 12
            color: resetHov.hovered ? Appearance.colors.colLayer2Hover : "transparent"
            HoverHandler { id: resetHov }
            TapHandler {
                onTapped: root.alignToDefault()
            }
            MaterialSymbol {
                anchors.centerIn: parent
                text: "restart_alt"
                iconSize: 16
                color: Appearance.colors.colOnLayer0
            }
        }
    }

    PopupContextMenu {
        id: alignMenu
        Component.onCompleted: {
            let p = parent;
            while (p && p.parent) {
                p = p.parent;
            }
            if (p) {
                alignMenu.parent = p;
            }
        }
    }
}
