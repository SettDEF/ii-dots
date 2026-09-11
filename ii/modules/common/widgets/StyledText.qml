import qs.modules.common
import QtQuick
import QtQuick.Window

Text {
    id: root
    property bool animateChange: false
    property real animationDistanceX: 0
    property real animationDistanceY: 6

    // NativeRendering rasterises glyphs for an untransformed, whole-pixel
    // target. This display runs at scale 1.67, and the sidebar wraps its
    // pages in layer.enabled masks — so those glyphs get rendered once at
    // native size and then resampled, which is exactly what makes the text
    // look soft. Distance-field rendering survives both the fractional scale
    // and the layer.
    //
    // Integer-scale screens keep NativeRendering, where it really is the
    // sharper of the two, so the external monitor is unaffected.
    renderType: (Screen.devicePixelRatio % 1 === 0)
        ? Text.NativeRendering : Text.QtRendering
    verticalAlignment: Text.AlignVCenter
    property bool shouldUseNumberFont: /^\d+$/.test(root.text)
    property var defaultFont: shouldUseNumberFont ? Appearance.font.family.numbers : Appearance.font.family.main
    
    font {
        hintingPreference: Font.PreferDefaultHinting
        family: defaultFont
        pixelSize: Appearance?.font.pixelSize.small ?? 15
        variableAxes: shouldUseNumberFont ? ({}) : Appearance.font.variableAxes.main
    }
    color: Appearance?.m3colors.m3onBackground ?? "black"
    linkColor: Appearance?.m3colors.m3primary

    component Anim: NumberAnimation {
        target: root
        duration: 300 / 2
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
    }

    Component.onCompleted: {
        textAnimationBehavior.originalX = root.x;
        textAnimationBehavior.originalY = root.y;
    }

    Behavior on text {
        id: textAnimationBehavior
        property real originalX: root.x
        property real originalY: root.y
        enabled: root.animateChange

        SequentialAnimation {
            alwaysRunToEnd: true
            ParallelAnimation {
                Anim {
                    property: "x"
                    to: textAnimationBehavior.originalX - root.animationDistanceX
                    easing.type: Easing.InSine
                }
                Anim {
                    property: "y"
                    to: textAnimationBehavior.originalY - root.animationDistanceY
                    easing.type: Easing.InSine
                }
                Anim {
                    property: "opacity"
                    to: 0
                    easing.type: Easing.InSine
                }
            }
            PropertyAction {} // Tie the text update to this point (we don't want it to happen during the first slide+fade)
            PropertyAction {
                target: root
                property: "x"
                value: textAnimationBehavior.originalX + root.animationDistanceX
            }
            PropertyAction {
                target: root
                property: "y"
                value: textAnimationBehavior.originalY + root.animationDistanceY
            }
            ParallelAnimation {
                Anim {
                    property: "x"
                    to: textAnimationBehavior.originalX
                    easing.type: Easing.OutSine
                }
                Anim {
                    property: "y"
                    to: textAnimationBehavior.originalY
                    easing.type: Easing.OutSine
                }
                Anim {
                    property: "opacity"
                    to: 1
                    easing.type: Easing.OutSine
                }
            }
        }
    }
}
