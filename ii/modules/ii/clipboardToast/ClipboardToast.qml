pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

/**
 * Copy confirmation overlay.
 *
 * Geometry taken from the phone's version rather than invented:
 *
 *  - The container is a SHORT rounded bar (~84 px). It does not grow to fit
 *    the preview.
 *  - The preview tile is much TALLER than the bar and overhangs its top edge
 *    by roughly half its own height. That overhang is the defining feature —
 *    the tile reads as a card resting in the bar, not as content inside it.
 *  - The tile's height follows the CONTENT: square-ish for text, the image's
 *    own aspect for a picture, so a portrait screenshot gives a tall tile.
 *  - Two large filled circles sit beside it, about 60% of the bar's height.
 *
 * "Send" pushes to a paired phone over KDE Connect — the same channel that
 * raises this overlay when the phone copies something.
 */
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            visible: card.shown || card.opacity > 0.01

            WlrLayershell.namespace: "quickshell:clipboardToast"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: card.editing
                ? WlrKeyboardFocus.OnDemand
                : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            anchors { right: true; bottom: true }
            margins { right: 14; bottom: 14 }
            // FIXED surface size, deliberately.
            //
            // These were bound to animated values, which meant the Wayland
            // layer surface was resized on every frame of the animation — the
            // compositor reallocating and recompositing each time is what made
            // the motion stutter. The window is now large enough for the
            // biggest state and never changes; only scale and opacity animate,
            // which stay on the GPU.
            implicitWidth: 460
            implicitHeight: 520

            // The nested Region cannot resolve `shareSheet` by id from inside
            // the mask binding, so it is handed over as a property.
            property Item sheetItem: shareSheet

            mask: Region {
                item: card
                Region { item: win.sheetItem; intersection: Intersection.Combine }
            }

            // Tied to the card's own opacity. RectangularShadow paints whether or
            // not its target is visible, so an unbound shadow keeps casting
            // through the fade-out and lingers as a dark rounded blob with
            // nothing above it — the window outlives the card via
            // `card.opacity > 0.01`.
            StyledRectangularShadow {
                target: card
                opacity: card.opacity
            }

            // shareSheet deliberately has NO shadow. It is hidden except while
            // sharing, and its shadow was painting the whole time — a phantom
            // blob above the card in every other state.

            // ── Share sheet ───────────────────────────────────────────────
            // Linux has no system share sheet, so this is built from what is
            // actually available: paired KDE Connect devices, plus actions
            // that suit the copied content.
            Rectangle {
                id: shareSheet
                visible: card.sharing && card.opacity > 0.01
                anchors {
                    right: card.right
                    // Above the TILE, not the bar: the tile overhangs card.top,
                    // so anchoring to the bar put this underneath it.
                    bottom: card.top
                    bottomMargin: 10 + Math.max(0, tile.height - card.barHeight + 12)
                }
                // 24px grid margins per the share-sheet spec.
                implicitWidth: Math.max(150, shareGrid.implicitWidth + 48)
                implicitHeight: shareGrid.implicitHeight + 48
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainerHigh

                opacity: card.sharing ? 1 : 0
                scale: card.sharing ? 1 : 0.94
                transformOrigin: Item.BottomRight
                Behavior on opacity {
                    NumberAnimation {
                        duration: card.sharing ? 200 : 200
                        easing.type: Easing.Bezier
                        easing.bezierCurve: card.sharing ? card.easeIn : card.easeOut
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: card.sharing ? 300 : 250
                        easing.type: Easing.Bezier
                        easing.bezierCurve: card.sharing ? card.easeIn : card.easeOut
                    }
                }

                Flow {
                    id: shareGrid
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                    spacing: 12

                    Repeater {
                        model: KdeConnectService.reachableDevices
                        delegate: ShareTarget {
                            required property var modelData
                            icon: "smartphone"
                            label: modelData.name ?? "Phone"
                            onActivated: card.share("kde", modelData.id)
                        }
                    }

                    ShareTarget {
                        visible: ClipboardWatch.isImage
                        icon: "download"
                        label: Translation.tr("Save")
                        onActivated: card.share("save", "")
                    }

                    ShareTarget {
                        visible: ClipboardWatch.url.length > 0
                        icon: "open_in_new"
                        label: Translation.tr("Open")
                        onActivated: card.share("open", "")
                    }

                    ShareTarget {
                        icon: "folder_open"
                        label: Translation.tr("Files")
                        onActivated: card.share("files", "")
                    }
                }
            }

            // ── The bar ───────────────────────────────────────────────────
            Rectangle {
                id: card
                property bool shown: false
                property bool editing: false
                property bool sharing: false
                readonly property int barHeight: 84

                anchors {
                    right: parent.right
                    bottom: parent.bottom
                    rightMargin: 10
                    bottomMargin: 10
                }
                implicitWidth: tile.width + actions.implicitWidth + 34
                implicitHeight: barHeight
                radius: Appearance.rounding.large
                // Raw M3 role, not colLayer2: the colLayer* roles are computed
                // through contentTransparency, so the bar showed the app behind it.
                color: Appearance.m3colors.m3surfaceContainerHigh

                // Symmetric ease-in-out both ways: eases out of rest, eases
                // back into it. Material's "emphasized" curve is the in-out
                // form — cubic-bezier(0.2, 0.0, 0.0, 1.0).
                readonly property var easeIn:  [0.2, 0.0, 0.0, 1.0, 1, 1]
                readonly property var easeOut: [0.2, 0.0, 0.0, 1.0, 1, 1]

                opacity: shown ? 1 : 0
                scale: shown ? 1 : 0.9
                transformOrigin: Item.BottomRight
                Behavior on opacity {
                    NumberAnimation {
                        duration: card.shown ? 150 : 200
                        easing.type: Easing.Bezier
                        easing.bezierCurve: card.shown ? card.easeIn : card.easeOut
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: card.shown ? 350 : 300
                        easing.type: Easing.Bezier
                        easing.bezierCurve: card.shown ? card.easeIn : card.easeOut
                    }
                }

                // ── Preview tile — overhangs the bar's top edge ───────────
                Rectangle {
                    id: tile
                    readonly property int minHeight: 96
                    readonly property int maxHeight: 190

                    // Images keep their own aspect (a portrait screenshot gives
                    // a tall tile); text sits near square.
                    readonly property real imgAspect:
                        (thumb.implicitWidth > 0 && thumb.implicitHeight > 0)
                            ? thumb.implicitHeight / thumb.implicitWidth
                            : 1.0

                    // Trails the bar slightly. Everything arriving on the same
                    // frame reads as one flat block; a short offset makes the
                    // tile look like it lands in the bar.
                    transform: Translate {
                        y: card.shown ? 0 : 26
                        Behavior on y {
                            SequentialAnimation {
                                PauseAnimation { duration: card.shown ? 50 : 0 }
                                NumberAnimation { duration: 350; easing.type: Easing.Bezier
                                                  easing.bezierCurve: card.shown ? card.easeIn : card.easeOut }
                            }
                        }
                    }
                    opacity: card.shown ? 1 : 0
                    Behavior on opacity {
                        SequentialAnimation {
                            PauseAnimation { duration: card.shown ? 50 : 0 }
                            NumberAnimation { duration: 200; easing.type: Easing.Bezier
                                              easing.bezierCurve: card.shown ? card.easeIn : card.easeOut }
                        }
                    }

                    width: 96
                    height: ClipboardWatch.isImage
                        ? Math.max(minHeight, Math.min(maxHeight, width * imgAspect))
                        : 108
                    Behavior on height {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }

                    anchors {
                        left: parent.left
                        bottom: parent.bottom
                        leftMargin: 12
                        bottomMargin: 12
                    }
                    radius: Appearance.rounding.normal
                    color: ClipboardWatch.isImage
                        ? Appearance.m3colors.m3surfaceContainerHighest
                        : Appearance.m3colors.m3primaryContainer
                    clip: true

                    Image {
                        id: thumb
                        anchors.fill: parent
                        visible: ClipboardWatch.isImage
                        source: ClipboardWatch.imagePath
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 240
                        cache: false
                    }

                    StyledText {
                        anchors { fill: parent; margins: 9 }
                        visible: !ClipboardWatch.isImage && !card.editing
                        text: ClipboardWatch.preview
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        maximumLineCount: 5
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: Appearance.m3colors.m3onPrimaryContainer
                    }

                    TextEdit {
                        id: editor
                        anchors { fill: parent; margins: 9 }
                        visible: card.editing
                        text: ClipboardWatch.preview
                        wrapMode: TextEdit.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        font.family: Appearance.font.family.main
                        color: Appearance.m3colors.m3onPrimaryContainer
                        selectByMouse: true
                        selectionColor: Appearance.colors.colPrimary
                        Keys.onEscapePressed: card.editing = false
                    }
                }

                // ── Actions ───────────────────────────────────────────────
                RowLayout {
                    id: actions
                    anchors {
                        left: tile.right
                        leftMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 8

                    ToastButton {
                        visible: ClipboardWatch.url.length > 0 && !card.editing
                        icon: "open_in_new"
                        tip: Translation.tr("Open link")
                        onActivated: {
                            Quickshell.execDetached(["xdg-open", ClipboardWatch.url]);
                            card.shown = false;
                        }
                    }

                    ToastButton {
                        visible: !card.editing
                        icon: "share"
                        tip: Translation.tr("Share")
                        onActivated: {
                            card.sharing = !card.sharing;
                            hideTimer.restart();
                        }
                    }

                    ToastButton {
                        visible: !ClipboardWatch.isImage
                        icon: card.editing ? "check" : "edit"
                        tip: card.editing ? Translation.tr("Save") : Translation.tr("Edit")
                        onActivated: {
                            if (card.editing) card.commitEdit();
                            else {
                                card.editing = true;
                                hideTimer.restart();
                                editor.forceActiveFocus();
                                editor.selectAll();
                            }
                        }
                    }
                }

                function share(kind, arg) {
                    const path = ClipboardWatch.imagePath.split("?")[0];
                    if (kind === "kde") {
                        if (ClipboardWatch.isImage) KdeConnectService.share(arg, path);
                        else KdeConnectService.shareText(arg, ClipboardWatch.preview);
                    } else if (kind === "save") {
                        // Timestamped so repeated copies do not overwrite.
                        Quickshell.execDetached(["bash", "-c",
                            `mkdir -p ~/Pictures/Clipboard && cp '${path}' ~/Pictures/Clipboard/clip-$(date +%Y%m%d-%H%M%S).png`]);
                    } else if (kind === "files") {
                        Quickshell.execDetached(["bash", "-c",
                            ClipboardWatch.isImage
                                ? `xdg-open "$(dirname '${path}')"`
                                : "xdg-open ~/Pictures/Clipboard 2>/dev/null || xdg-open ~"]);
                    } else if (kind === "open") {
                        Quickshell.execDetached(["xdg-open", ClipboardWatch.url]);
                    }
                    card.sharing = false;
                    card.shown = false;
                }

                function commitEdit() {
                    card.editing = false;
                    Quickshell.execDetached(["wl-copy", "--", editor.text]);
                    hideTimer.restart();
                }

                Timer {
                    id: hideTimer
                    // Longer while the user is doing something, but never
                    // infinite: an open share sheet used to stop this outright,
                    // which left the overlay stuck on screen forever.
                    interval: card.editing ? 20000 : (card.sharing ? 9000 : 3400)
                    onTriggered: {
                        card.sharing = false;
                        card.editing = false;
                        card.shown = false;
                    }
                }

                Connections {
                    target: ClipboardWatch
                    function onRevisionChanged() {
                        card.editing = false;
                        card.shown = true;
                        hideTimer.restart();
                    }
                }
            }
        }
    }
}
