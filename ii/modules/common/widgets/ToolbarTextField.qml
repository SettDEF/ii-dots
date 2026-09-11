import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets

TextField {
    id: filterField

    property alias colBackground: background.color

    Layout.fillHeight: true
    implicitWidth: 200
    padding: 10

    placeholderTextColor: Appearance.colors.colSubtext
    color: Appearance.colors.colOnLayer1
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance.font.pixelSize.small
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
    renderType: Text.NativeRendering
    selectedTextColor: Appearance.colors.colOnSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer

    background: Rectangle {
        id: background
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.full
    }

    // Opt-out for hosts that want Qt's stock menu (or none at all).
    property bool themedContextMenu: true

    // Qt 6.9+ ships TextField with its own unstyled context menu and exposes no
    // property to disable it. This MouseArea sits ABOVE the field's content and
    // accepts ONLY the right button, so the press never reaches QQuickTextField's
    // own handler — the left button, drag-select and hover all still fall through
    // untouched because they are not in acceptedButtons.
    MouseArea {
        anchors.fill: parent
        z: 10
        enabled: filterField.themedContextMenu
        acceptedButtons: Qt.RightButton
        onPressed: mouse => {
            filterField.forceActiveFocus()
            textMenu.openAt(mouse.x, mouse.y)
            mouse.accepted = true
        }
    }

    TextFieldContextMenu {
        id: textMenu
        field: filterField
    }
}
