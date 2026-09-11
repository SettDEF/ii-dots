import qs.services
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
// HyprlandToplevel is an ATTACHED property from this module; without the
// import it silently reads undefined and every address match fails.
import Quickshell.Hyprland

/**
 * Window-scope half of AppDisplay: one click-through surface pinned over each
 * window whose app profile uses scope "window".
 *
 * This is the only way to confine a display effect to a single window on
 * Wayland. A surface composites ON TOP of what's below it and cannot sample
 * it, which is exactly why window scope offers dim and tint and nothing else
 * — saturation or contrast would require reading the pixels underneath.
 *
 * Two details that matter:
 *   * `mask: Region {}` gives an empty input region, so clicks, hover and
 *     scroll pass straight through to the app. Without it the overlay would
 *     swallow every event over the window.
 *   * Layer is Top, not Overlay: it must sit above the window but below the
 *     bar and the panels, which live on Overlay.
 */
Scope {
    id: root

    Variants {
        model: AppDisplay.overlays

        delegate: Component {
            PanelWindow {
                id: ov
                required property var modelData

                // Hyprland gives us an address; ScreencopyView needs the
                // Toplevel object, so bridge the two.
                readonly property var toplevel: {                    const tls = ToplevelManager.toplevels?.values ?? [];
                    for (let i = 0; i < tls.length; ++i) {
                        const a = tls[i]?.HyprlandToplevel?.address;
                        if (a && ("0x" + a) === ov.modelData.address) return tls[i];
                    }
                    return null;
                }

                // Hyprland reports window geometry in logical coords, and
                // monitor x/y in the same space — but monitor width/height in
                // PHYSICAL pixels, so the logical extent needs the scale
                // divided out before testing which monitor holds the window.
                readonly property var mon: {
                    const ms = HyprlandData.monitors ?? [];
                    const cx = ov.modelData.x + ov.modelData.w / 2;
                    const cy = ov.modelData.y + ov.modelData.h / 2;
                    for (let i = 0; i < ms.length; ++i) {
                        const m = ms[i];
                        const s = m.scale || 1;
                        const lw = m.width / s;
                        const lh = m.height / s;
                        if (cx >= m.x && cx < m.x + lw && cy >= m.y && cy < m.y + lh)
                            return m;
                    }
                    return ms.length > 0 ? ms[0] : null;
                }

                screen: {
                    const n = ov.mon?.name ?? "";
                    return Quickshell.screens.find(s => s.name === n) ?? null;
                }

                WlrLayershell.namespace: "quickshell:appDisplayOverlay"
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                // -1, not 0: zero still positions the surface inside the area
                // left over by other exclusive-zone layers, so the bar's 40px
                // reservation pushed every overlay 40px down the screen. -1
                // opts out of that entirely and anchors to the true monitor
                // edge, which is the space window geometry is reported in.
                exclusiveZone: -1
                color: "transparent"

                // Empty input region — the overlay is purely visual.
                mask: Region {}

                anchors.top: true
                anchors.left: true
                margins.left: ov.modelData.x - (ov.mon?.x ?? 0)
                margins.top: ov.modelData.y - (ov.mon?.y ?? 0)
                implicitWidth: ov.modelData.w
                implicitHeight: ov.modelData.h

                Item {
                    id: fxWrap
                    anchors.fill: parent

                    // A glsl effect owns its own timing entirely — every pixel
                    // is computed from `time` in the shader. Fading the layer
                    // in on top of that composites a second, unrelated
                    // animation over it, so the shader appears to ramp rather
                    // than simply start. The dim/tint kinds have no such clock
                    // and still want the fade.
                    readonly property bool rawGlsl: ov.modelData.effect?.kind === "glsl"

                    opacity: fxWrap.rawGlsl ? 1 : 0
                    Component.onCompleted: if (!fxWrap.rawGlsl) opacity = 1;
                    Behavior on opacity {
                        enabled: !fxWrap.rawGlsl
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }

                    // Dim first, then tint on top: the tint keeps its hue
                    // instead of being muddied by the black underneath.
                    Rectangle {
                        anchors.fill: parent
                        radius: ov.modelData.rounding
                        antialiasing: true
                        color: Qt.rgba(0, 0, 0, ov.modelData.dim)
                        Behavior on color { ColorAnimation { duration: 160 } }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: ov.modelData.rounding
                        antialiasing: true
                        color: Qt.alpha(ov.modelData.tint, ov.modelData.tintStrength)
                        Behavior on color { ColorAnimation { duration: 160 } }
                    }

                    // ── Animated effect from a pack ─────────────────────
                    // The renderer is shared with the effect-list previews, so
                    // an effect is described in exactly one place.
                    Loader {
                        anchors.fill: parent
                        active: !!ov.modelData.effect
                        sourceComponent: EffectRenderer {
                            fx: ov.modelData.effect
                            rounding: ov.modelData.rounding
                            // Only resolved for effects that sample: finding
                            // the Toplevel is cheap, but holding a live
                            // capture of the window is not.
                            captureSource: ov.modelData.effect?.samples === true
                                ? ov.toplevel : null
                        }
                    }
                }
            }
        }
    }
}


