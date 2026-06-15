// On-screen virtual touchpad. Mirrors the OnScreenKeyboard pattern:
// floating layer-shell PanelWindow, mask region for input on the card
// only, lazy via outer Loader gated on GlobalStates.touchpadOpen.
//
// Drag inside the surface → relative cursor motion via ydotool.
// Tap                    → left click.
// Long-press / two-finger → right click.
// Buttons row below the surface for explicit L / M / R clicks.
//
// Movement is batched and flushed at ~60 Hz to avoid spawning ydotool
// per pointer event.
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    // Sensitivity multiplier — tune to taste.
    readonly property real sensitivity: 1.6
    // Drag threshold (pixels) below which we treat release as a tap.
    readonly property real tapMaxDistance: 8
    // Long-press for right click (ms).
    readonly property int longPressMs: 450

    Timer {
        id: tpCloseTimer
        interval: 250
        repeat: false
    }

    Connections {
        target: GlobalStates
        function onTouchpadOpenChanged() {
            if (!GlobalStates.touchpadOpen) {
                tpCloseTimer.start();
            }
        }
    }

    Loader {
        id: tpLoader
        active: GlobalStates.touchpadOpen || tpCloseTimer.running

        sourceComponent: PanelWindow {
            id: tpRoot
            visible: GlobalStates.touchpadOpen && !GlobalStates.screenLocked

            readonly property string side: Config.options?.touchpad?.side ?? "right"

            implicitWidth:  card.width  + Appearance.sizes.elevationMargin * 2
            implicitHeight: card.height + Appearance.sizes.elevationMargin * 2
            color: "transparent"
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:touchpad"
            WlrLayershell.layer: WlrLayer.Overlay

            mask: Region { item: card }

            Component.onCompleted: {
                GlobalStates.touchpadWindow = tpRoot;
            }
            Component.onDestruction: {
                GlobalStates.touchpadWindow = null;
            }

            // ── Batched motion flush ────────────────────────────────────
            property real pendingDx: 0
            property real pendingDy: 0
            Timer {
                id: flush
                interval: 16; repeat: true; running: true
                onTriggered: {
                    const dx = Math.round(tpRoot.pendingDx)
                    const dy = Math.round(tpRoot.pendingDy)
                    if (dx === 0 && dy === 0) return
                    tpRoot.pendingDx -= dx
                    tpRoot.pendingDy -= dy
                    moveProc.command = ["ydotool", "mousemove", "--", String(dx), String(dy)]
                    moveProc.running = true
                }
            }
            Process { id: moveProc }
            Process { id: clickProc }
            function click(button) {
                // 0xC0 = left, 0xC1 = right, 0xC2 = middle
                clickProc.command = ["ydotool", "click", button]
                clickProc.running = true
            }

            // ── Drop shadow + card ──────────────────────────────────────
            StyledRectangularShadow { target: card }
            Rectangle {
                id: card
                anchors.centerIn: parent
                width: 360
                height: 280
                radius: Appearance.rounding.windowRounding
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                opacity: 0
                transform: Translate {
                    id: tpTranslate
                    x: tpRoot.side === "left" ? -(card.width + 50) : (card.width + 50)
                }

                states: [
                    State {
                        name: "visible"
                        when: tpRoot.visible
                        PropertyChanges { target: tpTranslate; x: 0 }
                        PropertyChanges { target: card; opacity: 1 }
                    },
                    State {
                        name: "hidden"
                        when: !tpRoot.visible
                        PropertyChanges { target: tpTranslate; x: tpRoot.side === "left" ? -(card.width + 50) : (card.width + 50) }
                        PropertyChanges { target: card; opacity: 0 }
                    }
                ]

                transitions: [
                    Transition {
                        from: "hidden"; to: "visible"
                        ParallelAnimation {
                            NumberAnimation { properties: "x"; duration: 250; easing.type: Easing.OutCubic }
                            NumberAnimation { properties: "opacity"; duration: 200; easing.type: Easing.OutCubic }
                        }
                    },
                    Transition {
                        from: "visible"; to: "hidden"
                        ParallelAnimation {
                            NumberAnimation { properties: "x"; duration: 220; easing.type: Easing.InCubic }
                            NumberAnimation { properties: "opacity"; duration: 180; easing.type: Easing.InCubic }
                        }
                    }
                ]

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    // Title row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        MaterialSymbol {
                            text: "touchpad_mouse"
                            iconSize: 18
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            text: Translation.tr("Touchpad")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer0
                            Layout.fillWidth: true
                        }
                        PanelPositioner {
                            window: tpRoot
                            stateObject: Persistent.states.touchpad
                            defaultAlign: "right"
                            vertical: false
                        }
                        Rectangle {
                            implicitWidth: 26; implicitHeight: 26
                            radius: 13
                            color: closeHov.hovered
                                ? Appearance.colors.colLayer2Hover
                                : "transparent"
                            HoverHandler { id: closeHov }
                            TapHandler { onTapped: GlobalStates.touchpadOpen = false }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"; iconSize: 16
                                color: Appearance.colors.colOnLayer0
                            }
                        }
                    }

                    // ── Touch surface ───────────────────────────────────
                    Rectangle {
                        id: surface
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Appearance.rounding.normal
                        color: surfaceMa.pressed
                            ? Appearance.colors.colLayer1Hover
                            : Appearance.colors.colLayer1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        clip: true

                        // Dot grid — drawn once via Canvas (no per-frame cost).
                        Canvas {
                            anchors.fill: parent
                            antialiasing: true
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.fillStyle = Qt.rgba(0, 0, 0, 0.18)
                                const step = 14
                                const r = 1.1
                                for (let y = step; y < height - 2; y += step) {
                                    for (let x = step; x < width - 2; x += step) {
                                        ctx.beginPath()
                                        ctx.arc(x, y, r, 0, Math.PI * 2)
                                        ctx.fill()
                                    }
                                }
                            }
                            // Repaint on color theme reload (cheap, fires rarely).
                            Connections {
                                target: Appearance
                                function onColorsChanged() { parent.requestPaint() }
                            }
                        }

                        // Subtle hint label when idle
                        StyledText {
                            anchors.centerIn: parent
                            visible: !surfaceMa.pressed && surfaceMa.totalDistance < 1
                            text: Translation.tr("Drag to move · tap to click")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Qt.alpha(Appearance.colors.colOnLayer0, 0.38)
                        }

                        MouseArea {
                            id: surfaceMa
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            hoverEnabled: false
                            preventStealing: true

                            property real lastX: 0
                            property real lastY: 0
                            property real totalDistance: 0
                            property bool longPressFired: false

                            Timer {
                                id: longPressTimer
                                interval: root.longPressMs
                                repeat: false
                                onTriggered: {
                                    if (!surfaceMa.pressed) return
                                    if (surfaceMa.totalDistance < root.tapMaxDistance) {
                                        surfaceMa.longPressFired = true
                                        tpRoot.click("0xC1")  // right
                                    }
                                }
                            }

                            onPressed: (e) => {
                                lastX = e.x; lastY = e.y
                                totalDistance = 0
                                longPressFired = false
                                longPressTimer.restart()
                            }
                            onPositionChanged: (e) => {
                                const dx = e.x - lastX
                                const dy = e.y - lastY
                                lastX = e.x; lastY = e.y
                                tpRoot.pendingDx += dx * root.sensitivity
                                tpRoot.pendingDy += dy * root.sensitivity
                                totalDistance += Math.abs(dx) + Math.abs(dy)
                            }
                            onReleased: (e) => {
                                longPressTimer.stop()
                                if (longPressFired) return
                                if (totalDistance < root.tapMaxDistance) {
                                    const btn = e.button === Qt.RightButton ? "0xC1" : "0xC0"
                                    tpRoot.click(btn)
                                }
                            }
                            onCanceled: longPressTimer.stop()
                        }
                    }

                }
            }
        }
    }
}
