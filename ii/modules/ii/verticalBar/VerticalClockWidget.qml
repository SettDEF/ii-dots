import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import qs.modules.ii.bar as Bar

Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    implicitHeight: clockColumn.implicitHeight
    implicitWidth: Appearance.sizes.verticalBarWidth

    ColumnLayout {
        id: clockColumn
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: DateTime.time.split(/[: ]/)
            delegate: StyledText {
                required property string modelData
                required property int index
                readonly property bool meridiem: modelData.match(/am|pm/i) !== null

                Layout.alignment: Qt.AlignHCenter
                // Pulled together, or the two halves read as separate numbers.
                Layout.topMargin: (index === 0 || meridiem) ? 0 : -3

                font.pixelSize: meridiem
                    ? Appearance.font.pixelSize.smaller
                    : Appearance.font.pixelSize.large
                // Tabular, or the digits shuffle sideways every minute.
                font.family: Appearance.font.family.numbers
                font.features: ({ "tnum": 1 })
                lineHeightMode: Text.ProportionalHeight
                lineHeight: 0.82

                // Quieter minutes give the pair a reading order a column cannot.
                color: Appearance.colors.colOnLayer1
                opacity: (index === 0 || meridiem) ? 1 : 0.72
                text: modelData.padStart(2, "0")
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow

        Bar.ClockWidgetPopup {
            hoverTarget: mouseArea
        }
    }
}
