import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: root
    property string displayText: ""
    colBackground: Appearance.colors.colLayer2

    // A fixed natural width: the language bar stretches the button anyway.
    // Deriving it from the label, while the label's maximum came from the
    // button's width, was a layout cycle — "polish() loop", hundreds of times a
    // second, and the left sidebar lagged.
    implicitWidth: 120
    implicitHeight: contentItem.implicitHeight + verticalPadding * 2

    contentItem: Item {
        anchors.centerIn: parent
        width: Math.max(0, root.width - root.horizontalPadding * 2)
        implicitWidth: languageRow.implicitWidth
        implicitHeight: languageText.implicitHeight
        RowLayout {
            id: languageRow
            anchors.centerIn: parent
            spacing: 0
            StyledText {
                id: languageText
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 5
                Layout.maximumWidth: Math.max(20, root.width - root.horizontalPadding * 2 - 30)
                elide: Text.ElideRight
                text: root.displayText
                color: Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.small
            }
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                iconSize: Appearance.font.pixelSize.hugeass
                text: "arrow_drop_down"
                color: Appearance.colors.colOnLayer2
            }
        }
    }
}
