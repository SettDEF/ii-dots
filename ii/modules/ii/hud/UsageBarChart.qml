import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Bar chart for screen-time usage — used for the weekly (Mon-Sun) and
 * the 24-hour daily charts. `bars` is an array of:
 *   { label: String, value: Number, highlight: bool }
 * Bars scale to the largest value; `label` may be "" for unlabelled
 * ticks (e.g. only 00:00/06:00/… on the 24-hour chart).
 */
Item {
    id: root

    property var bars: []
    property color accent: Appearance.m3colors.m3primary
    property bool dense: bars.length > 12     // 24-hour chart → thin bars

    readonly property real maxValue: {
        let m = 1
        for (const b of bars)
            if ((b.value ?? 0) > m) m = b.value
        return m
    }

    RowLayout {
        anchors.fill: parent
        spacing: root.dense ? 2 : 8

        Repeater {
            model: root.bars
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 4

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width * (root.dense ? 0.74 : 0.6)
                        height: Math.max(2, parent.height
                            * (modelData.value ?? 0) / root.maxValue)
                        radius: Math.min(width / 2, 5)
                        color: modelData.highlight
                            ? root.accent
                            : Qt.alpha(root.accent, 0.26)
                        Behavior on height {
                            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    visible: text.length > 0
                    text: modelData.label ?? ""
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: modelData.highlight
                        ? root.accent
                        : Appearance.colors.colSubtext
                }
            }
        }
    }
}
