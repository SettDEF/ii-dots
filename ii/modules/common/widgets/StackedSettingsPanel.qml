pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The shared chrome for the top-right settings panels.
 *
 * Display, WallTune, KinetiX, the stats overlay and audio each had their own
 * copy of this: the same layershell flags, the same PanelStack registration,
 * the same ScreenFit height, the same header with an X, the same Esc handler.
 * Five copies meant five chances to drift, and they did — panels ended up with
 * different widths, different heights, and one sat 40px lower than the rest
 * because it was missing ExclusionMode.Ignore.
 *
 * Usage — everything panel-specific goes in `content`:
 *
 *     StackedSettingsPanel {
 *         panelId: "audio"                 // must also appear in PanelStack.order
 *         title: "Audio"
 *         icon: "graphic_eq"
 *         onRequestClose: GlobalStates.audioSettingsOpen = false
 *         content: ColumnLayout { ... }
 *     }
 *
 * The caller still owns its own Loader and open-state: a panel decides when it
 * exists, this decides what it looks like.
 */
PanelWindow {
    id: win

    // Identity in the horizontal stack. Panels ranked earlier in
    // PanelStack.order sit further right.
    required property string panelId
    required property string title
    property string icon: "settings"
    // How long the fade-out lasts. The owning Loader must stay active at least
    // this long after the open-state flips, or the animation never renders.
    // Matches the slide-out below, so the Loader holds the panel just long
    // enough for it to be seen.
    readonly property int exitDuration: 150
    // Forwarded so a Loader can trigger the exit without reaching into `card`.
    function playExit() { card.playExit() }
    // Extra header controls, inserted left of the close button.
    property list<Item> headerItems
    default property alias content: contentHolder.data
    signal requestClose()

    WlrLayershell.namespace: "quickshell:" + win.panelId
    WlrLayershell.layer: WlrLayer.Overlay
    // A fullscreen XWayland game locks the cursor. OnDemand can't break that
    // (you can't click to take focus while the cursor is trapped), so grab
    // keyboard focus Exclusively when a game is fullscreen — that pulls focus
    // off the game and releases its pointer lock. Normal case stays OnDemand.
    readonly property bool _anyFullscreen: {
        const ws = HyprlandData.activeWorkspace?.id;
        const wl = HyprlandData.windowList ?? [];
        for (let i = 0; i < wl.length; ++i)
            if (wl[i]?.workspace?.id === ws && wl[i].fullscreen > 0) return true;
        return false;
    }
    WlrLayershell.keyboardFocus: win._anyFullscreen
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    // Without Ignore the compositor places the panel AFTER the reserved strip,
    // dropping it ~40px below the panels it is supposed to line up with.
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    color: "transparent"

    anchors.top: true
    anchors.right: true
    // Sit exactly where the right sidebar does: below the compositor-reserved
    // top strip (the bar) by one gap, and one gap in from the right edge. Using
    // the real reserved value — the same thing the sidebar rides under — keeps
    // it aligned across bar styles instead of re-deriving the bar height here.
    // Extra room above the panel, e.g. to sit below the corner popup rather
    // than behind it. Animated so opening that popup slides the panel down
    // instead of teleporting it.
    property int topOffset: 0
    margins.top: ScreenFit.reservedTop(win) + Appearance.sizes.hyprlandGapsOut + win.topOffset
    Behavior on margins.top {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    margins.right: Appearance.sizes.hyprlandGapsOut + PanelStack.offsetFor(win.panelId)
    Behavior on margins.right {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    implicitWidth: ScreenFit.panelWidth
    implicitHeight: card.implicitHeight
    // Empty region (item: null) while a screenshot region-select is up, so the
    // panel stays visible but the drag passes through instead of being eaten.
    mask: Region { item: GlobalStates.regionSelectorOpen ? null : card }

    // Registered in BOTH places on purpose: implicitWidth is a constant here,
    // so onImplicitWidthChanged never fires by itself and the stack offset
    // would stay 0 — every panel would land on top of its neighbour.
    onImplicitWidthChanged: PanelStack.register(win.panelId, implicitWidth)
    Component.onCompleted: PanelStack.register(win.panelId, implicitWidth)
    Component.onDestruction: PanelStack.unregister(win.panelId)

    // NO focus grab. These are settings panels, not context menus: the point is
    // to click a control and watch the thing you are configuring change, and a
    // dismiss-on-outside-click grab closed the panel every time you looked at
    // what you had just done. Esc and the X are the ways out.
    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: win.requestClose()
    }

    // Slides in, the same way the corner popups do (they animate their own
    // `margins.top`). A Translate is a GPU transform: no relayout, no surface
    // resize, nothing re-rendered.
    //
    // What it deliberately does NOT do is fade `opacity` on this card. Opacity
    // on a container forces Qt to render the ENTIRE subtree — every slider,
    // label and icon — into an offscreen buffer on every frame of the tween.
    // These panels are not small, and that was the stutter on open.
    Rectangle {
        id: card
        opacity: 1
        transform: Translate { id: cardLift; y: 14 }
        Component.onCompleted: entryAnim.start()

        // Called by the owning Loader just before teardown; it stays active for
        // exitDuration so this is actually visible.
        function playExit() {
            entryAnim.stop();
            exitAnim.start();
        }
        NumberAnimation {
            id: entryAnim
            target: cardLift; property: "y"
            to: 0; duration: 220; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            id: exitAnim
            target: cardLift; property: "y"
            to: 12; duration: win.exitDuration; easing.type: Easing.InCubic
        }
        width: parent.width
        // Size to content, capped at the available screen height (same as the
        // right sidebar): a short panel stays short, and only a panel that
        // actually overflows grows to full height and lets the flickable scroll.
        implicitHeight: Math.min(col.implicitHeight + 32, ScreenFit.maxHeight(win))
        // Height is NOT animated. Animating it resizes the layer-shell surface on
        // every frame of the tween, which the compositor must honour each time —
        // that cost is what made expanding a section feel like dragging.
        radius: Appearance.rounding.large
        // colLayer0Base, not the literal "#141418" this used to be.
        //
        // That hex is a near-miss for the theme's own background (m3background
        // is #141313) and it does not retheme: matugen repaints the palette
        // from the wallpaper and the card stayed put. Worse, every themed child
        // placed on it mismatched by a hair — most visibly PillTextField's
        // notch, the little patch that hides the outline behind a floated
        // label, which defaults to colLayer0 and so never quite matched the
        // card it sat on.
        color: Appearance.colors.colLayer0Base
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        StyledFlickable {
            id: scroller
            anchors.fill: parent
            anchors.margins: 16
            contentHeight: col.implicitHeight
            contentWidth: width
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: col
                width: scroller.width
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialSymbol {
                        text: win.icon
                        iconSize: 20
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: win.title
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer0
                    }
                    Repeater {
                        model: win.headerItems
                        delegate: Item {
                            required property var modelData
                            implicitWidth: modelData?.implicitWidth ?? 0
                            implicitHeight: modelData?.implicitHeight ?? 0
                            Component.onCompleted: if (modelData) modelData.parent = this
                        }
                    }
                    RippleButton {
                        implicitWidth: 28
                        implicitHeight: 28
                        buttonRadius: 14
                        onClicked: win.requestClose()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 18
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                }

                // Panel-specific content lands here.
                ColumnLayout {
                    id: contentHolder
                    Layout.fillWidth: true
                    spacing: 14
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
