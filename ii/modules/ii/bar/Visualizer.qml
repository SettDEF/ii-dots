import QtQuick
import qs.services
import qs.modules.common

// Audio spectrum fed by CavaService. Adapted from the end4-pC fork.
Item {
    id: root

    readonly property list<real> points: CavaService.visualizerPoints
    readonly property bool playing: MprisController.anyPlaying

    property int barCount: 20
    property real dotSize: 3
    property real dotSpacing: 3
    property real maxBarHeight: Appearance.sizes.barHeight * 0.7
    property real maxValue: 1000 // cava's raw ceiling

    implicitWidth: barCount * (dotSize + dotSpacing)
    implicitHeight: Appearance.sizes.barHeight

    Row {
        anchors.centerIn: parent
        spacing: root.dotSpacing

        Repeater {
            model: root.barCount

            Rectangle {
                required property int index

                // Idle collapses to dots, so the bar never changes width.
                readonly property real level: {
                    if (!root.playing || root.points.length === 0)
                        return root.dotSize;
                    const i = Math.floor(index * root.points.length / root.barCount);
                    return Math.max(root.dotSize, (root.points[i] ?? 0) / root.maxValue * root.maxBarHeight);
                }

                width: root.dotSize
                height: level
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: Appearance.colors.colPrimary
                opacity: root.playing ? 0.85 : 0.3

                Behavior on height { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
                Behavior on opacity { NumberAnimation { duration: 300 } }
            }
        }
    }
}
