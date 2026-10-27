import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// Flat command button.
Rectangle {
    id: cmd
    property string text: ""
    property bool primary: false
    property bool danger: false
    signal clicked()
    implicitHeight: 24
    implicitWidth: cmdText.implicitWidth + 18
    radius: 2
    readonly property color c: danger ? Appearance.m3colors.m3error : primary ? Appearance.m3colors.m3primary : Appearance.colors.colOnLayer1
    color: cmdMouse.containsMouse ? Qt.alpha(c, 0.16) : Qt.alpha(c, primary || danger ? 0.10 : 0.05)
    border.width: 1
    border.color: Qt.alpha(c, 0.4)
    opacity: enabled ? 1 : 0.4
    StyledText {
        id: cmdText
        anchors.centerIn: parent
        text: cmd.text
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 0.8
        color: cmd.c
    }
    MouseArea { id: cmdMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (cmd.enabled) cmd.clicked() }
}