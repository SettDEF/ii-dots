import qs.services
import QtQuick
import qs.modules.ii.onScreenDisplay

OsdValueIndicator {
    id: osdValues
    // value drives the icon rotation (0 → 0°, 1 → 180°) so the symbol
    // visibly flips on every caps-lock state change. No progress bar
    // since this is binary on/off.
    value: root.capslockActive ? 1 : 0
    showProgress: false
    rotateIcon: true
    // Full 360° spin → animates the rotation but ends in the original
    // upright orientation so the caps-lock arrow keeps pointing UP
    // (not upside-down like a 180° rotation would leave it).
    iconRotationAngle: 360
    showShadow: false
    customValueText: root.capslockActive ? Translation.tr("ON") : Translation.tr("OFF")
    icon: "keyboard_capslock"
    highlightIcon: root.capslockActive
    name: Translation.tr("Caps Lock")
}
