// Charge as a bar readout; the dock's battery panel is its hover popup.
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    required property string widgetId

    readonly property bool showPercent: BarWidgets.get(root.widgetId, "showPercent") !== false
    readonly property int pct: Math.round(Battery.percentage * 100)

    visible: Battery.available
    hoverEnabled: true
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight + 8

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 2
        MaterialSymbol {
            text: Battery.isCharging ? "bolt" : "battery_full"
            iconSize: Appearance.font.pixelSize.large
            fill: 1
            color: Battery.isLow ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
        }
        StyledText {
            visible: root.showPercent
            text: `${root.pct}%`
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.family: Appearance.font.family.monospace
            color: Battery.isLow ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
        }
    }

    StyledPopup {
        hoverTarget: root
        // The panel is the dock's, loaded by path: the same content in a
        // different frame. Loaded, not instantiated, so this file does not
        // depend on the type being registered.
        Loader {
            anchors.centerIn: parent
            width: 220
            source: Qt.resolvedUrl("../../common/widgets/BatteryPanel.qml")
        }
    }
}
