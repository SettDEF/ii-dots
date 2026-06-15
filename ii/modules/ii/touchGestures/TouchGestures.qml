// Tablet-mode-only fullscreen touch gesture overlay. Detects:
//   • 3-finger tap (anywhere)              → Nexus launcher
//   • 4-finger swipe up (drag past 100 px) → Overview
//   • Long-press (600 ms) in top-right     → power menu
//
// Only loaded while tabletMode is true — the input region covers the
// whole screen and would block mouse events otherwise.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services

Scope {
    id: root

    readonly property var touchScreens:
        Quickshell.screens.filter(s => /^(eDP|LVDS|DSI)/i.test(s.name))

    Variants {
        model: root.touchScreens

        PanelWindow {
            id: gestureWin
            required property ShellScreen modelData
            screen: modelData

            visible: true
            color: "transparent"
            exclusiveZone: 0
            exclusionMode: ExclusionMode.Ignore
            // Bottom layer: above the wallpaper, below regular windows AND
            // panels (sidebars, HUD, dock). Gestures only fire on empty
            // desktop space — clicks on real UI go to the real UI.
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "quickshell:touch-gestures"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors { top: true; bottom: true; left: true; right: true }

            // Per-finger tracking
            property real f0X: 0; property real f0Y: 0
            property real fStartT: 0
            property int  fingerCount: 0
            property int  peakFingerCount: 0
            property real swipeStartY: 0
            property bool gestureFired: false
            // Was the very first touch in the top-right corner?
            property bool startedInCorner: false
            readonly property real cornerSize: 80

            // Long-press timer — fires for top-right corner gesture.
            Timer {
                id: cornerLongPress
                interval: 600
                repeat: false
                onTriggered: {
                    if (!gestureWin.startedInCorner) return
                    if (gestureWin.fingerCount !== 1) return
                    if (gestureWin.gestureFired) return
                    gestureWin.gestureFired = true
                    GlobalStates.sessionOpen = true
                }
            }

            MultiPointTouchArea {
                anchors.fill: parent
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

                function _firstActive() {
                    if (tp0.pressed) return tp0
                    if (tp1.pressed) return tp1
                    if (tp2.pressed) return tp2
                    if (tp3.pressed) return tp3
                    if (tp4.pressed) return tp4
                    return null
                }

                onPressed: (points) => {
                    InputMode.reportDevice(PointerDevice.TouchScreen)
                    gestureWin.fingerCount += points.length
                    gestureWin.peakFingerCount = Math.max(gestureWin.peakFingerCount, gestureWin.fingerCount)

                    // First finger going down — capture start state.
                    const head = _firstActive()
                    if (head && gestureWin.fingerCount === points.length) {
                        gestureWin.f0X = head.x
                        gestureWin.f0Y = head.y
                        gestureWin.fStartT = Date.now()
                        gestureWin.swipeStartY = head.y
                        gestureWin.gestureFired = false
                        gestureWin.startedInCorner =
                            (head.x > gestureWin.width  - gestureWin.cornerSize) &&
                            (head.y < gestureWin.cornerSize)
                        if (gestureWin.startedInCorner) cornerLongPress.restart()
                    }
                }

                onUpdated: (points) => {
                    // Cancel corner long-press if finger moved out
                    if (gestureWin.startedInCorner && cornerLongPress.running) {
                        const head = _firstActive()
                        if (head && (Math.abs(head.x - gestureWin.f0X) > 12
                                  || Math.abs(head.y - gestureWin.f0Y) > 12)) {
                            cornerLongPress.stop()
                            gestureWin.startedInCorner = false
                        }
                    }

                    // 4-finger swipe up — when 4 are down and they've moved up
                    // past 100 px from the start, fire Overview.
                    if (gestureWin.fingerCount >= 4 && !gestureWin.gestureFired) {
                        const head = _firstActive()
                        if (head && (gestureWin.swipeStartY - head.y) > 100) {
                            gestureWin.gestureFired = true
                            GlobalStates.overviewOpen = true
                        }
                    }
                }

                onReleased: (points) => {
                    gestureWin.fingerCount = Math.max(0, gestureWin.fingerCount - points.length)

                    // All fingers up — evaluate tap-style gestures.
                    if (gestureWin.fingerCount === 0) {
                        const dt = Date.now() - gestureWin.fStartT
                        // 3-finger tap → overview search
                        if (!gestureWin.gestureFired
                            && gestureWin.peakFingerCount === 3
                            && dt < 350) {
                            GlobalStates.overviewOpen = true
                        }
                        gestureWin.peakFingerCount = 0
                        gestureWin.gestureFired = false
                        gestureWin.startedInCorner = false
                        cornerLongPress.stop()
                    }
                }

                onCanceled: (points) => {
                    gestureWin.fingerCount = 0
                    gestureWin.peakFingerCount = 0
                    gestureWin.gestureFired = false
                    gestureWin.startedInCorner = false
                    cornerLongPress.stop()
                }
            }
        }
    }
}
