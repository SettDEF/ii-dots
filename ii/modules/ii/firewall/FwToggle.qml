import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// Square on/off toggle (checkbox-like, not a pill switch).
Rectangle {
    id: tg
    property bool checked: false
    signal toggled()
    implicitWidth: 30
    implicitHeight: 16
    radius: 2
    color: checked ? Qt.alpha(Appearance.m3colors.m3primary, 0.22) : "transparent"
    border.width: 1
    border.color: checked ? Appearance.m3colors.m3primary : Qt.alpha(Appearance.colors.colOnLayer1, 0.35)
    opacity: enabled ? 1 : 0.4
    Rectangle {
        width: 10; height: 10; radius: 1
        anchors.verticalCenter: parent.verticalCenter
        x: tg.checked ? tg.width - width - 3 : 3
        color: tg.checked ? Appearance.m3colors.m3primary : Qt.alpha(Appearance.colors.colOnLayer1, 0.45)
        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (tg.enabled) tg.toggled() }
}