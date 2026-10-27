import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// The panel's small switch.
Rectangle {
    id: sw
    property bool checked: false
    signal toggled()
    implicitWidth: 28; implicitHeight: 16; radius: 8
    color: sw.checked ? Qt.alpha(Appearance.colors.colPrimary, 0.45)
                      : Qt.alpha(Appearance.colors.colOnLayer0, 0.20)
    Behavior on color { ColorAnimation { duration: 140 } }
    TapHandler { margin: Appearance.sizes.touchSlop + 6; onTapped: sw.toggled() }
    Rectangle {
        width: 12; height: 12; radius: 6
        anchors.verticalCenter: parent.verticalCenter
        x: sw.checked ? parent.width - width - 2 : 2
        color: sw.checked ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 140 } }
    }
}
