// One reading in the dock: a filled ring with its glyph inside, then the
// value. The bar draws its stats this way (see bar/Resource.qml), so the dock
// reads as the same shell rather than as loose text next to the app icons.
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property string icon: ""
    property real value: 0          // 0..1, drives the ring
    property string label: ""
    property string tooltip: ""
    property bool warning: false
    property bool dimmed: false

    readonly property color tint: root.warning ? Appearance.m3colors.m3error
        : root.dimmed ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer0

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    HoverHandler { id: hov }
    StyledToolTip {
        extraVisibleCondition: false
        alternativeVisibleCondition: hov.hovered && root.tooltip.length > 0
        text: root.tooltip
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 4

        ClippedFilledCircularProgress {
            Layout.alignment: Qt.AlignVCenter
            implicitSize: 22
            lineWidth: Appearance.rounding.unsharpen
            value: root.value
            // The ring takes the bar's muted container colour, not the text
            // tint — near-white rings read as blobs against the dock.
            colPrimary: root.warning ? Appearance.colors.colError
                : root.dimmed ? Appearance.colors.colSubtext
                : Appearance.colors.colOnSecondaryContainer
            accountForLightBleeding: !root.warning
            enableAnimation: false

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.icon
                iconSize: Appearance.font.pixelSize.normal
                fill: 1
                font.weight: Font.DemiBold
                color: Appearance.m3colors.m3onSecondaryContainer
            }
        }

        // Width reserved for "100%", so a changing value doesn't resize the
        // whole dock once a second.
        Item {
            Layout.alignment: Qt.AlignVCenter
            visible: root.label.length > 0
            implicitWidth: widest.width
            implicitHeight: valueText.implicitHeight

            TextMetrics {
                id: widest
                text: "100%"
                font.pixelSize: Appearance.font.pixelSize.small
            }
            StyledText {
                id: valueText
                anchors.left: parent.left
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.tint
            }
        }
    }
}
