import qs.modules.common
import QtQuick

StyledText {
    id: root
    property real iconSize: Appearance?.font.pixelSize.small ?? 16
    property real fill: 0
    property real truncatedFill: fill.toFixed(1) // Reduce memory consumption spikes from constant font remapping

    // Snap `opsz` to the four sizes Material Symbols actually designs for.
    //
    // Qt builds a SEPARATE font instance, with its own rasterised glyph cache,
    // for every distinct combination of variable-axis values. Passing the raw
    // pixel size meant 29 different iconSize values across this config, times
    // 11 truncated fill steps — up to 319 instances of a 14MB variable font,
    // which is how the font ended up holding 174MB resident.
    //
    // The axis only has design masters at 20/24/40/48, so intermediate values
    // are interpolations nobody can see at these sizes. Snapping collapses the
    // 29 down to 4 and costs nothing visually.
    readonly property int snappedOpsz: iconSize <= 22 ? 20
        : iconSize <= 32 ? 24
        : iconSize <= 44 ? 40
        : 48
    renderType: Text.NativeRendering
    font {
        hintingPreference: Font.PreferNoHinting
        family: Appearance?.font.family.iconMaterial ?? "Material Symbols Rounded"
        pixelSize: iconSize
        // Constant. This used to interpolate with `fill`, which multiplied the
        // font-instance count again for emphasis that FILL already conveys.
        weight: Font.Normal
        variableAxes: { 
            "FILL": truncatedFill,
            // "wght": font.weight,
            // "GRAD": 0,
            "opsz": snappedOpsz,
        }
    }

    Behavior on fill { // Leaky leaky, no good
        NumberAnimation {
            duration: Appearance?.animation.elementMoveFast.duration ?? 200
            easing.type: Appearance?.animation.elementMoveFast.type ?? Easing.BezierSpline
            easing.bezierCurve: Appearance?.animation.elementMoveFast.bezierCurve ?? [0.34, 0.80, 0.34, 1.00, 1, 1]
        }
    }
}
