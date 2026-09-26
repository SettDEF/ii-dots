// The now-playing card's backdrop: theme tint, blurred artwork, scrim.
//
// No rounding of its own — the card that hosts it owns the mask, so the dock
// card and its hover expansion can round different corners and still read as
// one continuous surface.
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

Item {
    id: root
    required property string art
    required property QtObject colors

    Rectangle {
        anchors.fill: parent
        color: ColorUtils.applyAlpha(root.colors.colLayer0, 1)
    }
    Image {
        id: blurredArt
        anchors.fill: parent
        source: root.art
        fillMode: Image.PreserveAspectCrop
        cache: false
        antialiasing: true
        asynchronous: true
        layer.enabled: true
        layer.effect: StyledBlurEffect { source: blurredArt }
    }
    Rectangle {
        anchors.fill: parent
        color: ColorUtils.transparentize(root.colors.colLayer0, 0.3)
    }
}
