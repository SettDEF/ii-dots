import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

// Glyph plus a level bar along the bottom. Scroll to change, click to mute.
DockTile {
    id: root
    readonly property real vol: Audio.sink?.audio?.volume ?? 0
    readonly property bool muted: Audio.sink?.audio?.muted ?? false
    // Darkest step. colLayer2 alone is so close to the dock's own background
    // that the tile disappeared.
    tint: ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colLayer0, 0.45)
    tooltip: Audio.sink?.description ?? Translation.tr("Volume")

    MouseArea {
        anchors.fill: parent
        onClicked: if (Audio.sink?.audio) Audio.sink.audio.muted = !Audio.sink.audio.muted
        onWheel: wheel => {
            if (!Audio.sink?.audio) return;
            const pct = (DockWidgets.get("volume", "step") ?? 2) / 100;
            const step = wheel.angleDelta.y > 0 ? pct : -pct;
            Audio.sink.audio.volume = Math.max(0, Math.min(1, root.vol + step));
        }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -4
        text: root.muted ? "volume_off" : root.vol > 0.5 ? "volume_up" : "volume_down"
        iconSize: Appearance.font.pixelSize.large
        fill: 1
        color: Appearance.colors.colOnPrimaryContainer
    }
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.margins: 6
        implicitHeight: 4
        radius: Appearance.rounding.full
        color: Qt.alpha(Appearance.m3colors.m3onTertiaryContainer, 0.25)
        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.width * (root.muted ? 0 : Math.max(0, Math.min(1, root.vol)))
            radius: parent.radius
            color: Appearance.colors.colOnPrimaryContainer
            Behavior on width {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}
