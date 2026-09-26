import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects

/// Album artwork at any size, shared by the dock card and the media popup.
/// With no art it draws a mark derived from `seed`, so one track keeps one
/// identity.
Item {
    id: root

    property string source: ""
    property real size: 36
    property color accent: Appearance.colors.colPrimary
    property color surface: Appearance.colors.colLayer1
    /// Usually "<title><artist>" — anything stable per track.
    property string seed: ""
    property real radius: Config.options?.media.coverRadius ?? Appearance.rounding.small

    implicitWidth: root.size
    implicitHeight: root.size

    readonly property int _hash: {
        let h = 0;
        const s = String(root.seed);
        for (let i = 0; i < s.length; ++i) h = ((h << 5) - h + s.charCodeAt(i)) | 0;
        return Math.abs(h);
    }
    readonly property color _tint: Qt.hsla((root._hash % 360) / 360, 0.45, 0.55, 1)
    readonly property bool hasArt: img.status === Image.Ready

    Rectangle {
        id: clipper
        anchors.fill: parent
        radius: root.radius
        color: root.hasArt ? "transparent" : ColorUtils.mix(root._tint, root.surface, 0.45)

        // clip ignores radius — only a mask rounds child content.
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: clipper.width
                height: clipper.height
                radius: clipper.radius
            }
        }

        Image {
            id: img
            anchors.fill: parent
            source: root.source
            fillMode: Image.PreserveAspectCrop
            cache: false
            asynchronous: true
            antialiasing: true
            sourceSize.width: root.size
            sourceSize.height: root.size
        }

        // Circle / rounded square / diamond off one Rectangle — no Canvas.
        Rectangle {
            visible: !root.hasArt
            anchors.centerIn: parent
            width: parent.width * 0.52
            height: width
            rotation: root._hash % 3 === 2 ? 45 : 0
            radius: root._hash % 3 === 0 ? width / 2 : width * 0.22
            color: ColorUtils.mix(root._tint, "white", 0.75)
            opacity: 0.9
        }
    }
}
