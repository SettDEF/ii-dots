// Wide button styled like the original RogView entries — icon block on
// the left, label + status text on the right.  Used inside the ROG
// drawer for GPU / Battery / Charge tiles.
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: wb
    property string iconName:   ""
    property string label:      ""
    property string statusText: ""
    property bool   toggled:    false
    property real   pad: 2
    property real   btnH: 56
    signal tap()

    Layout.fillWidth: true
    width: parent ? parent.width : 0
    height: btnH
    implicitHeight: btnH
    radius: height / 2
    // No outer gray pill — the icon-block on the left carries the accent.
    color: "transparent"

    HoverHandler { id: wbHov }
    TapHandler   { onTapped: wb.tap() }
    Rectangle {
        anchors.fill: parent; radius: parent.radius
        color: wbHov.hovered ? Qt.alpha(Appearance.colors.colOnLayer1, 0.06) : "transparent"
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
    }

    RowLayout {
        anchors { fill: parent; margins: wb.pad }
        spacing: 8

        // Bigger icon block — fills the row height.
        Rectangle {
            implicitWidth:  parent.height
            implicitHeight: parent.height
            radius: parent.height / 2
            color: wb.toggled ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
            Behavior on color  { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            Behavior on radius { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
            MaterialSymbol {
                anchors.centerIn: parent
                text: wb.iconName
                fill: wb.toggled ? 1 : 0
                iconSize: 26
                color: wb.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }
        }

        Column {
            Layout.fillWidth: true
            spacing: -2
            StyledText {
                width: parent.width
                text: wb.label
                font.pixelSize: Appearance.font.pixelSize.smallie
                font.weight: 600
                elide: Text.ElideRight
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                width: parent.width
                visible: wb.statusText !== ""
                text: wb.statusText
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: 100
                elide: Text.ElideRight
                color: Appearance.colors.colSubtext
            }
        }
    }
}
