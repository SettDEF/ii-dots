// Reusable single-slider tile body. Same look as the QuickSlider
// component inside QuickSliders.qml, but extracted so atomic tiles
// (Volume / Brightness / Mic) can render it without duplicating the
// styling.
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls

StyledSlider {
    id: slider
    property string materialSymbol: ""
    // When true the slider's icon becomes tappable and fires `iconClicked`.
    // The drag area is shrunk on the icon side so taps don't accidentally
    // change the value while the user is aiming for the icon.
    property bool iconTappable: false
    signal iconClicked()
    configuration: StyledSlider.Configuration.M
    stopIndicatorValues: []

    MaterialSymbol {
        id: icon
        property bool nearFull: slider.value >= 0.9
        anchors {
            verticalCenter: parent.verticalCenter
            right: nearFull ? slider.handle.right : parent.right
            rightMargin: nearFull ? 14 : 8
        }
        iconSize: 20
        color: nearFull
            ? Appearance.colors.colOnPrimary
            : Appearance.colors.colOnSecondaryContainer
        text: slider.materialSymbol
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on anchors.rightMargin {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        // Tap target — slightly bigger than the glyph for easy hitting.
        // Sits on top of the slider's interaction layer (z: 10) so a click
        // here doesn't slide the value.
        MouseArea {
            anchors.centerIn: parent
            width: 30; height: 30
            visible: slider.iconTappable
            z: 10
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => mouse.accepted = true
            onClicked: slider.iconClicked()
        }
    }
}
