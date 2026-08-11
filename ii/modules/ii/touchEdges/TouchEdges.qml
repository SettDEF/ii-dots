pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Invisible edge strips that detect finger touch and reveal a glowing
 * matugen-coloured trail behind the contact point. A second finger
 * arriving while the first is still down opens the corresponding panel.
 *
 * Each edge strip is wider than its input region so the trail glow can
 * bloom inward beyond the 12 px hit-zone without affecting input mask.
 *
 * Internal-screen-only — touch hardware lives on the laptop panel.
 */
Scope {
    id: root

    readonly property var touchScreens:
        Quickshell.screens.filter(s => /^(eDP|LVDS|DSI)/i.test(s.name))

    // One trailing glow dot — used 3× per strip with cascading follow times.
    // Position is clamped so circles are always fully visible inside the
    // panel — no screen-edge slice. Trail therefore leads INWARD from the
    // touch point instead of trying to wrap around it.
    component TrailDot: Rectangle {
        property real targetX: 0
        property real targetY: 0
        property real maxX: 0
        property real maxY: 0
        property bool down: false
        property int  followMs: 60
        property real intensity: 1.0    // 1.0 head, < 1 fading tail
        property real diameter: 64
        property color accent: Appearance.colors.colPrimary

        width: diameter; height: diameter
        radius: diameter / 2
        // Clamp center so radius padding (8 px breathing room) keeps the
        // disc fully inside the panel on all sides.
        x: Math.max(8, Math.min(maxX - diameter - 8, targetX - diameter / 2))
        y: Math.max(8, Math.min(maxY - diameter - 8, targetY - diameter / 2))
        color: Qt.alpha(accent, 0.32 * intensity)
        opacity: down ? 1 : 0
        visible: opacity > 0.01
        scale: down ? 1 : 0.6

        // Only animate position while the finger is actually down. Avoids
        // the visible "catch-up from (0,0)" slide on first touch and any
        // spurious motion when the watchdog forces a reset.
        Behavior on x       { enabled: down; NumberAnimation { duration: followMs; easing.type: Easing.OutCubic } }
        Behavior on y       { enabled: down; NumberAnimation { duration: followMs; easing.type: Easing.OutCubic } }
        Behavior on color   { ColorAnimation  { duration: 200 } }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }

    // Edge → which side of the screen ("left"|"right"|"top"|"bottom").
    component EdgeStrip: PanelWindow {
        id: stripWin
        required property ShellScreen modelData
        required property string side
        required property string hintIcon          // Material symbol name
        // Action when gesture fires (2-finger touch OR full drag).
        required property var onActivate

        screen: modelData

        readonly property bool horizontal: side === "top" || side === "bottom"
        // Window-aware adaptive band:
        //   • bottom    → always 0 (dock owns it)
        //   • edge has a window touching it → 4 px (don't fight the
        //     window for hover / resize / tap).
        //   • edge over empty desktop      → 64 px (forgiving finger
        //     landing zone for swipe gestures).
        // Refreshed automatically on Hyprland events via HyprlandData.
        readonly property bool _edgeCovered: {
            const sx = modelData?.x ?? 0
            const sy = modelData?.y ?? 0
            const sw = modelData?.width ?? 0
            const sh = modelData?.height ?? 0
            const tol = 6
            for (const w of (HyprlandData.windowList ?? [])) {
                if (!w?.at || !w?.size) continue
                const wx = w.at[0], wy = w.at[1]
                const ww = w.size[0], wh = w.size[1]
                // Window must overlap this monitor at all.
                if (wx + ww <= sx || wx >= sx + sw) continue
                if (wy + wh <= sy || wy >= sy + sh) continue
                // Touches our specific edge?
                if (side === "left"  && wx <= sx + tol)               return true
                if (side === "right" && wx + ww >= sx + sw - tol)     return true
                if (side === "top"   && wy <= sy + tol)               return true
            }
            return false
        }
        // Suppress every touch-edge band when a focus-grabbing fullscreen
        // overlay is up (ScreenDraw, etc) — otherwise the grab treats any
        // click hitting our band as "outside" and dismisses the overlay
        // before its own MouseArea can register the stroke.
        readonly property bool _suppressed:
            GlobalStates.screenDrawOpen ||
            GlobalStates.screenDrawFullOpen
        // "top" is zero-width like "bottom": its `anchors.top` is commented out
        // below because anchoring it put the surface above windows, which means
        // the window is UNANCHORED and the compositor places it wherever it
        // likes. Giving an unanchored 360 px Overlay surface a live input band
        // is how you lose clicks in the middle of the screen, so it takes no
        // input until the anchoring is sorted out. The HUD still opens from its
        // shortcut and from the bar.
        readonly property real bandSize: (side === "bottom" || side === "top" || _suppressed)
            ? 0
            : (_edgeCovered ? 4 : 64)
        readonly property real bloomSize: 360    // visible region for glow

        // Accent shifts when the gesture is about to fire (2nd finger down).
        readonly property color trailAccent: fingerCount >= 2
            ? Appearance.m3colors.m3secondary
            : Appearance.colors.colPrimary

        visible: true
        color: "transparent"
        exclusiveZone: 0
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:touch-edge-" + side
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors.left:   side === "left"
        anchors.right:  side === "right"
        //lanchors.top:    side === "top" // commented out because issues with the z-index. It goes above windows.
        anchors.bottom: side === "bottom"

        // Span the entire edge length so any touch along the edge fires
        // the gesture. The cross-axis (`bloomSize`) is the depth where
        // the trail blooms inward.
        implicitWidth:  horizontal ? (modelData?.width  ?? 1920) : bloomSize
        implicitHeight: horizontal ? bloomSize : (modelData?.height ?? 1080)

        // Limit input to a thin band on the actual edge — the glow can
        // render across the rest of the window without grabbing clicks.
        //
        // And take NO input at all unless the last pointer event came from a
        // finger or a pen. The docstring at the top of this file claimed this
        // already happened ("input-transparent under mouse / pen"), but nothing
        // implemented it: the band was live in every mode, so on a mouse these
        // strips silently ate clicks in a 4-64 px column down both screen edges
        // at Overlay layer. That is the single reason this module was left
        // commented out rather than fixed.
        //
        // An empty Region is the "off" state — a null item would mean the whole
        // surface, which is the opposite of what is wanted here.
        mask: (InputMode.isTouch || InputMode.isPen) ? maskBand : maskNone
        Region { id: maskNone }
        Region { id: maskBand; item: hitBand }

        Item {
            id: hitBand
            x: side === "right"  ? parent.width  - stripWin.bandSize : 0
            y: side === "bottom" ? parent.height - stripWin.bandSize : 0
            width:  stripWin.horizontal ? parent.width  : stripWin.bandSize
            height: stripWin.horizontal ? stripWin.bandSize : parent.height
        }

        // Sentinel start at -200 so dots are off-screen before first touch.
        property real f0X: -200; property real f0Y: -200; property bool f0Down: false
        property real f1X: -200; property real f1Y: -200; property bool f1Down: false
        property int  fingerCount: 0
        // Latch so a single 2-finger press triggers exactly once per gesture.
        property bool gestureFired: false
        // Convenience for parts that just want "any finger active".
        readonly property bool fingerDown: f0Down || f1Down

        // ── Drag progress (0..1) — how deep the deepest finger has gone
        // from the screen edge. Used to drive the hint icon's reveal.
        readonly property real dragThreshold: 140
        function _depthFor(x, y) {
            if (side === "left")   return x
            if (side === "right")  return width  - x
            if (side === "top")    return y
            return                        height - y       // bottom
        }
        readonly property real f0Depth: f0Down ? Math.max(0, _depthFor(f0X, f0Y)) : 0
        readonly property real f1Depth: f1Down ? Math.max(0, _depthFor(f1X, f1Y)) : 0
        readonly property real maxDepth: Math.max(f0Depth, f1Depth)
        readonly property real dragProgress: Math.min(1, maxDepth / dragThreshold)
        // Anchor the hint icon at the deepest finger so it follows naturally.
        readonly property real hintX: f0Depth >= f1Depth ? f0X : f1X
        readonly property real hintY: f0Depth >= f1Depth ? f0Y : f1Y

        // (Trail dots removed — the hint chip is the sole visual.)

        // Watchdog — if we've claimed fingerDown but no touch update has
        // landed in 700 ms, reset. Prevents the "stuck rings" failure when
        // a touch session is dropped without a Released or Canceled event.
        property real lastTouchAt: 0
        Timer {
            interval: 250
            repeat: true
            running: stripWin.fingerDown
            onTriggered: {
                if (Date.now() - stripWin.lastTouchAt > 700) {
                    stripWin.fingerDown = false
                    stripWin.fingerCount = 0
                    stripWin.gestureFired = false
                }
            }
        }

        // ── Drag-progress hint chip ──────────────────────────────────
        // Sits in the middle of the sidebar's edge — fixed position, not
        // following the finger. Slides INWARD from the screen edge as drag
        // progresses, scales + fades up. Replaces the dot trails.
        readonly property real _chipStartX: side === "left"  ? -chipSize/2
                                          : side === "right" ? width - chipSize/2
                                          : (width - chipSize) / 2
        readonly property real _chipStartY: side === "top"   ? -chipSize/2
                                          : side === "bottom"? height - chipSize/2
                                          : (height - chipSize) / 2
        readonly property real _chipEndX:   side === "left"  ? bandSize - chipSize/2
                                          : side === "right" ? width - bandSize - chipSize/2
                                          : (width - chipSize) / 2
        readonly property real _chipEndY:   side === "top"   ? bandSize - chipSize/2
                                          : side === "bottom"? height - bandSize - chipSize/2
                                          : (height - chipSize) / 2
        readonly property real chipSize: 64

        Item {
            id: hintChip
            x: stripWin._chipStartX + (stripWin._chipEndX - stripWin._chipStartX) * stripWin.dragProgress
            y: stripWin._chipStartY + (stripWin._chipEndY - stripWin._chipStartY) * stripWin.dragProgress
            width: stripWin.chipSize; height: stripWin.chipSize
            visible: stripWin.fingerDown
            scale: 0.55 + 0.45 * stripWin.dragProgress

            // Smooth position — long duration with InOutCubic so it glides
            // rather than snaps. No opacity behavior anywhere.
            Behavior on x     { NumberAnimation { duration: 280; easing.type: Easing.InOutCubic } }
            Behavior on y     { NumberAnimation { duration: 280; easing.type: Easing.InOutCubic } }
            Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

            // Rotating background shape — sits behind the icon and spins
            // while the chip is visible.
            SineCookie {
                anchors.centerIn: parent
                implicitSize: stripWin.chipSize
                sides: 6
                color: stripWin.trailAccent
                constantlyRotate: stripWin.fingerDown
                Behavior on color { ColorAnimation { duration: 200 } }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: stripWin.hintIcon
                iconSize: 26
                color: Appearance.m3colors.m3onSecondary
            }
        }

        MultiPointTouchArea {
            id: mta
            anchors.fill: hitBand
            mouseEnabled: false
            minimumTouchPoints: 1
            maximumTouchPoints: 5

            touchPoints: [
                TouchPoint { id: tp0 },
                TouchPoint { id: tp1 },
                TouchPoint { id: tp2 },
                TouchPoint { id: tp3 },
                TouchPoint { id: tp4 }
            ]

            // Walk the declared TouchPoints, assign each currently-pressed
            // one to a slot (0 or 1) so each finger gets a stable trail.
            //
            // tp.x / tp.y are in hitBand-local coords. The trail dots live
            // in stripWin coords, so we add hitBand's offset within the
            // strip — otherwise the trail renders far from the finger.
            function _trackFingers() {
                const tps = [tp0, tp1, tp2, tp3, tp4]
                const ox = hitBand.x
                const oy = hitBand.y
                let slotIdx = 0
                for (let i = 0; i < tps.length && slotIdx < 2; i++) {
                    if (!tps[i].pressed) continue
                    const px = ox + tps[i].x
                    const py = oy + tps[i].y
                    if (slotIdx === 0) {
                        stripWin.f0X = px; stripWin.f0Y = py
                        stripWin.f0Down = true
                    } else {
                        stripWin.f1X = px; stripWin.f1Y = py
                        stripWin.f1Down = true
                    }
                    slotIdx++
                }
                if (slotIdx === 0) { stripWin.f0Down = false; stripWin.f1Down = false }
                else if (slotIdx === 1) stripWin.f1Down = false
            }

            function _maybeFire() {
                // Fire on either: 2 fingers down (instant-open in tablet
                // mode where the band is wide enough) OR 1-finger drag
                // fully past threshold.
                if (stripWin.gestureFired) return
                if (stripWin.fingerCount >= 2 || stripWin.dragProgress >= 1.0) {
                    stripWin.gestureFired = true
                    stripWin.onActivate()
                }
            }

            onPressed: (points) => {
                InputMode.reportDevice(PointerDevice.TouchScreen)
                stripWin.fingerCount += points.length
                stripWin.lastTouchAt = Date.now()
                _trackFingers()
                _maybeFire()
            }
            onUpdated: (points) => {
                stripWin.lastTouchAt = Date.now()
                _trackFingers()
                _maybeFire()
            }
            onReleased: (points) => {
                stripWin.fingerCount = Math.max(0, stripWin.fingerCount - points.length)
                stripWin.lastTouchAt = Date.now()
                if (stripWin.fingerCount === 0) {
                    stripWin.f0Down = false
                    stripWin.f1Down = false
                    stripWin.gestureFired = false
                } else {
                    _trackFingers()
                }
            }
            onCanceled: (points) => {
                stripWin.fingerCount = 0
                stripWin.f0Down = false
                stripWin.f1Down = false
                stripWin.gestureFired = false
            }
        }
    }

    Variants {
        model: root.touchScreens
        EdgeStrip {
            side: "left"
            hintIcon: "menu_open"
            onActivate: () => GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen
        }
    }
    Variants {
        model: root.touchScreens
        EdgeStrip {
            side: "right"
            hintIcon: "tune"
            onActivate: () => GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
        }
    }
    Variants {
        model: root.touchScreens
        EdgeStrip {
            side: "top"
            hintIcon: "expand_more"
            onActivate: () => GlobalStates.hudOpen = !GlobalStates.hudOpen
        }
    }
    Variants {
        model: root.touchScreens
        EdgeStrip {
            side: "bottom"
            hintIcon: "dock_to_bottom"
            onActivate: () => GlobalStates.dockOpen = !GlobalStates.dockOpen
        }
    }
}
