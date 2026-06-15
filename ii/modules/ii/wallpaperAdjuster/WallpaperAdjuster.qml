// Wallpaper adjuster — full-screen overlay that lets you drag/zoom the
// current wallpaper to choose the visible crop. Saves the result to
// Config.options.background.crop.perFile keyed by wallpaperPath so each
// wallpaper remembers its own framing.
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Qt5Compat.GraphicalEffects

Scope {
    id: root

    Loader {
        active: GlobalStates.wallpaperAdjusterOpen
        sourceComponent: PanelWindow {
            id: panel
            visible: GlobalStates.wallpaperAdjusterOpen
            WlrLayershell.namespace: "quickshell:wallpaperAdjuster"
            WlrLayershell.layer: WlrLayer.Overlay
            // No keyboardFocus claim — Hyprland warps the pointer to centre
            // a new layer surface that requests focus. We close on click-
            // outside / Cancel / Save / the Esc global shortcut instead.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: Qt.alpha("black", 0.85)
            anchors { top: true; bottom: true; left: true; right: true }

            readonly property string wallpaperPath: Config.options.background.wallpaperPath
            // Key crop entries by the ORIGINAL source path — walltune's
            // processed-[ab].png slots alternate every apply, so keying by
            // wallpaperPath splits one wallpaper's crop across two entries.
            readonly property string cropKey: {
                const src = Config.options.background.wallpaperSourcePath || ""
                return src.length > 0 ? src : wallpaperPath
            }
            readonly property bool isVideo: /\.(mp4|webm|mkv|avi|mov|m4v|gif)$/i.test(wallpaperPath || "")

            // Live editing values; seeded from any existing saved entry.
            property real offsetX: 0
            property real offsetY: 0
            property real scale:   1
            property bool fitMode: false    // true = show entire image, false = crop to fill

            function _loadExisting() {
                try {
                    const m = JSON.parse(Config.options.background.crop.perFile || "{}")
                    if (m && m[cropKey]) {
                        offsetX = m[cropKey].offsetX || 0
                        offsetY = m[cropKey].offsetY || 0
                        scale   = m[cropKey].scale   || 1
                        fitMode = m[cropKey].fit === true
                        return
                    }
                } catch (e) {}
                offsetX = Config.options.background.crop.offsetX
                offsetY = Config.options.background.crop.offsetY
                scale   = Config.options.background.crop.scale
                fitMode = false
            }
            function _save() {
                let m = {}
                try { m = JSON.parse(Config.options.background.crop.perFile || "{}") }
                catch (e) {}
                m[cropKey] = { offsetX: offsetX, offsetY: offsetY, scale: scale, fit: fitMode }
                Config.options.background.crop.perFile = JSON.stringify(m)
                Config.options.background.crop.rev = Config.options.background.crop.rev + 1
                GlobalStates.wallpaperAdjusterOpen = false
            }
            function _reset() {
                offsetX = 0; offsetY = 0; scale = 1; fitMode = false
            }

            Component.onCompleted: _loadExisting()

            // ── Editing surface ────────────────────────────────────────
            // Centred frame the size of the screen with the wallpaper
            // anchored inside it — drag the wallpaper to pan, scroll to
            // zoom. A bounding box overlay shows where the screen edges
            // will fall.
            Item {
                id: viewport
                anchors.centerIn: parent
                width: parent.width * 0.72
                height: parent.height * 0.72

                Rectangle {
                    anchors.fill: parent
                    color: Qt.alpha("white", 0.04)
                    border.width: 2
                    border.color: Appearance.colors.colPrimary
                    radius: 12
                }

                // Letterbox frame inside which the wallpaper pans/zooms.
                Item {
                    id: cropFrame
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true

                    // Wrapper sized + positioned by the pan/zoom math,
                    // hosting either an Image (static) or a VideoOutput.
                    // Tracks the media's NATURAL aspect ratio so vertical
                    // videos overflow vertically (giving pan headroom),
                    // not forced to viewport aspect.
                    Item {
                        id: wpContent
                        // Set by the child Image / MediaPlayer when its
                        // intrinsic size becomes known. 1 = unknown.
                        property real mediaAspect: 1
                        readonly property real viewportAspect: cropFrame.width / cropFrame.height
                        readonly property bool mediaWider: mediaAspect >= viewportAspect
                        // PreserveAspectCrop semantics — fill the SMALLER
                        // container dimension, overflow the LARGER. Portrait
                        // media (mediaWider=false) fills width and overflows
                        // top/bottom → vertical pan works. Landscape fills
                        // height, overflows sides → horizontal pan works.
                        width: mediaWider
                            ? cropFrame.height * mediaAspect * panel.scale
                            : cropFrame.width  * panel.scale
                        height: mediaWider
                            ? cropFrame.height * panel.scale
                            : cropFrame.width / mediaAspect * panel.scale
                        x: (cropFrame.width  - width)  / 2 + panel.offsetX * Math.max(0, (width  - cropFrame.width)  / 2)
                        y: (cropFrame.height - height) / 2 + panel.offsetY * Math.max(0, (height - cropFrame.height) / 2)

                        Behavior on x      { NumberAnimation { duration: 120 } }
                        Behavior on y      { NumberAnimation { duration: 120 } }
                        Behavior on width  { NumberAnimation { duration: 140 } }
                        Behavior on height { NumberAnimation { duration: 140 } }

                        // Static image branch.
                        Image {
                            anchors.fill: parent
                            visible: !panel.isVideo
                            source: panel.isVideo ? "" : ("file://" + panel.wallpaperPath)
                            // Fill the wpContent box exactly — wpContent
                            // is now sized to the media's natural aspect.
                            fillMode: Image.Stretch
                            asynchronous: true
                            cache: true
                            smooth: true
                            onSourceSizeChanged: {
                                if (sourceSize.height > 0)
                                    wpContent.mediaAspect = sourceSize.width / sourceSize.height
                            }
                        }

                        // Live video branch — same MediaPlayer pattern
                        // skwd's carousel uses, muted + looping. Unloads
                        // when the adjuster closes so the decoder dies.
                        Loader {
                            anchors.fill: parent
                            active: panel.isVideo && (panel.wallpaperPath || "").length > 0
                            visible: active
                            asynchronous: true
                            sourceComponent: Item {
                                MediaPlayer {
                                    id: wpPlayer
                                    source: "file://" + panel.wallpaperPath
                                    loops: MediaPlayer.Infinite
                                    audioOutput: AudioOutput { muted: true; volume: 0 }
                                    videoOutput: wpVidOut
                                    Component.onCompleted: play()
                                    onErrorOccurred: (e, msg) => console.warn("adjuster video:", e, msg)
                                    onMetaDataChanged: {
                                        const r = metaData.value(MediaMetaData.Resolution)
                                        if (r && r.height > 0)
                                            wpContent.mediaAspect = r.width / r.height
                                    }
                                }
                                VideoOutput {
                                    id: wpVidOut
                                    anchors.fill: parent
                                    fillMode: VideoOutput.Stretch
                                }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        property real _sx: 0
                        property real _sy: 0
                        property real _startOffsetX: 0
                        property real _startOffsetY: 0
                        onPressed: (mouse) => {
                            _sx = mouse.x; _sy = mouse.y
                            _startOffsetX = panel.offsetX
                            _startOffsetY = panel.offsetY
                        }
                        onPositionChanged: (mouse) => {
                            if (!pressed) return
                            // Pixels of pan → fraction of movable space.
                            const movX = Math.max(1, (wpContent.width  - cropFrame.width)  / 2)
                            const movY = Math.max(1, (wpContent.height - cropFrame.height) / 2)
                            panel.offsetX = Math.max(-1, Math.min(1,
                                _startOffsetX + (mouse.x - _sx) / movX))
                            panel.offsetY = Math.max(-1, Math.min(1,
                                _startOffsetY + (mouse.y - _sy) / movY))
                        }
                        onWheel: (event) => {
                            const dz = event.angleDelta.y / 1200
                            panel.scale = Math.max(1.0, Math.min(3.0, panel.scale + dz))
                            event.accepted = true
                        }
                    }
                }
            }

            // ── Bottom action bar ──────────────────────────────────────
            // M3 surface-container pill — matches the rest of the shell's
            // floating bars. Standard DialogButton / PrimaryActionButton /
            // ConfigSlider widgets so colours, ripple, and tooltips track
            // Appearance theme changes automatically.
            StyledRectangularShadow { target: actionBar }
            Rectangle {
                id: actionBar
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 30
                implicitWidth:  barRow.implicitWidth + 32
                implicitHeight: 64
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                RowLayout {
                    id: barRow
                    anchors.centerIn: parent
                    spacing: 14

                    ConfigSlider {
                        Layout.preferredWidth: 240
                        text: qsTr("Zoom")
                        buttonIcon: "zoom_in"
                        from: 1.0
                        to:   3.0
                        value: panel.scale
                        enabled: !panel.fitMode
                        opacity: enabled ? 1 : 0.5
                        onValueChanged: if (Math.abs(value - panel.scale) > 0.001) panel.scale = value
                    }

                    // Fit / Fill toggle — when "Fit" is on, the whole
                    // image is shown letterboxed; Zoom/pan are inert.
                    DialogButton {
                        buttonText: panel.fitMode ? qsTr("Showing whole image") : qsTr("Cropping to fill")
                        onClicked: panel.fitMode = !panel.fitMode
                    }

                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 32
                        color: Appearance.colors.colOnLayer0Border
                    }

                    DialogButton {
                        buttonText: qsTr("Reset")
                        onClicked: panel._reset()
                    }
                    DialogButton {
                        buttonText: qsTr("Cancel")
                        colBackground: "transparent"
                        onClicked: GlobalStates.wallpaperAdjusterOpen = false
                    }
                    PrimaryActionButton {
                        buttonText: qsTr("Save")
                        onClicked: panel._save()
                    }
                }
            }

            // Top help text
            StyledText {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 36
                text: qsTr("Drag to pan · Scroll to zoom · Esc to cancel")
                color: Qt.alpha("white", 0.7)
                font.pixelSize: Appearance.font.pixelSize.normal
            }
        }
    }

    IpcHandler {
        target: "wallpaperAdjuster"
        function toggle(): void { GlobalStates.wallpaperAdjusterOpen = !GlobalStates.wallpaperAdjusterOpen }
        function open():   void { GlobalStates.wallpaperAdjusterOpen = true }
        function close():  void { GlobalStates.wallpaperAdjusterOpen = false }
    }
}
