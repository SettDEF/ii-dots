import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// Icon · title (+ subtitle) · value · chevron or switch. One height.
RippleButton {
    id: row
    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    property string value: ""
    property bool lit: false
    /// "chevron" | "switch" | ""
    property string trailing: "chevron"
    /// Chevron glyph and turn, e.g. "expand_more" turning 180 for a dropdown.
    property string chevronIcon: "chevron_right"
    property real chevronRotation: 0
    property bool isOn: false
    signal switched()

    Layout.fillWidth: true
    implicitHeight: subtitle.length > 0 ? 52 : 44
    buttonRadius: Appearance.rounding.small
    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer1Hover
    onClicked: if (row.trailing === "switch") row.switched()

    contentItem: RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 12
        MaterialSymbol {
            Layout.preferredWidth: 22
            horizontalAlignment: Text.AlignHCenter
            text: row.glyph
            iconSize: Appearance.font.pixelSize.larger
            color: row.lit ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: row.title
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                visible: row.subtitle.length > 0
                text: row.subtitle
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
        StyledText {
            visible: row.value.length > 0
            text: row.value
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: row.lit ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
        }
        MaterialSymbol {
            visible: row.trailing === "chevron"
            text: row.chevronIcon
            rotation: row.chevronRotation
            Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colSubtext
        }
        PaletteSwitch {
            visible: row.trailing === "switch"
            checked: row.isOn
            onToggled: row.switched()
        }
    }
}
