// One step of the finance setup wizard: an icon+title header, an explanatory
// line, then whatever controls the step needs as default children.
//
// Extracted because all five steps share this shape exactly, and the section
// idiom (colLayer1 card, 12px inner margin, 17px primary icon) is the one used
// by the stacked settings panels elsewhere in the config.
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: sec

    property string icon: "settings"
    property string title: ""
    property string body: ""
    default property alias extra: inner.data

    Layout.fillWidth: true
    implicitHeight: visible ? inner.implicitHeight + 24 : 0
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    ColumnLayout {
        id: inner
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol {
                text: sec.icon
                iconSize: 17
                color: Appearance.colors.colPrimary
            }
            StyledText {
                Layout.fillWidth: true
                text: sec.title
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: sec.body.length > 0
            text: sec.body
            wrapMode: Text.WordWrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
