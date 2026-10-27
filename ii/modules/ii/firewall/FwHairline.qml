import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// 1 px rule.
Rectangle {
    Layout.fillWidth: true
    implicitHeight: 1
    color: Qt.alpha(Appearance.colors.colOnLayer1, 0.10)
}