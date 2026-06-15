// Single hourly-forecast capsule used by the HUD weather orbit. The pill
// representing the current hour grows and switches to the primary tint;
// every other pill stays compact and uses the neutral surface colour.
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

Item {
    id: hp
    property var hd: ({})
    property bool current: false
    implicitWidth: current ? 78 : 58
    implicitHeight: current ? 104 : 80
    Behavior on implicitWidth  { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: hp.current
            ? Appearance.m3colors.m3primary
            : Qt.alpha(Appearance.colors.colLayer2, 0.94)
        border.width: 1
        border.color: hp.current
            ? "transparent"
            : Appearance.colors.colLayer0Border

        ColumnLayout {
            anchors.centerIn: parent
            spacing: hp.current ? 3 : 1
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: hp.hd.time ?? ""
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: hp.current
                    ? Appearance.m3colors.m3background
                    : Appearance.colors.colSubtext
            }
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: Icons.getWeatherIcon(hp.hd.code ?? "113")
                iconSize: hp.current ? 26 : 19
                fill: 1
                color: hp.current
                    ? Appearance.m3colors.m3background
                    : Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: (hp.hd.temp ?? 0) + "°"
                font.family: Appearance.font.family.monospace
                font.pixelSize: hp.current
                    ? Appearance.font.pixelSize.normal
                    : Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: hp.current
                    ? Appearance.m3colors.m3background
                    : Appearance.colors.colOnLayer0
            }
        }
    }
}
