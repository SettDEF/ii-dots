pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.looks

Item {
    id: root
    Layout.alignment: Qt.AlignTop
    property alias sourceSize: avatar.sourceSize
    implicitWidth: avatar.sourceSize.width
    implicitHeight: avatar.sourceSize.height

    StyledImage {
        id: avatar
        anchors.fill: parent
        sourceSize: Qt.size(32, 32)
        source: Directories.userAvatarPathAccountsService
        fallbacks: [Directories.userAvatarPathRicersAndWeirdSystems, Directories.userAvatarPathRicersAndWeirdSystems2]

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Circle {
                diameter: avatar.height
            }
        }
    }

    // No picture anywhere: the initial on a circle, as Windows does, instead of an empty space
    // (StyledImage hides itself when every source fails, so this sits beside it)
    Rectangle {
        anchors.fill: parent
        visible: avatar.status !== Image.Ready
        radius: width / 2
        color: Looks.colors.accentUnfocused
        WText {
            anchors.centerIn: parent
            text: (SystemInfo.username || "?").charAt(0).toUpperCase()
            color: Looks.colors.fg
            font.pixelSize: Math.round(parent.height * 0.45)
            font.weight: Looks.font.weight.strong
        }
    }
}
