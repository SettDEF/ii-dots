import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth

    PanelWindow {
        id: panelWindow
        visible: GlobalStates.sidebarRightOpen

        function hide() {
            GlobalStates.sidebarRightOpen = false;
        }

        exclusiveZone: 0
        implicitWidth: sidebarWidth
        WlrLayershell.namespace: "quickshell:sidebarRight"
        // OnDemand lets text fields (todo, wifi password) receive keyboard
        // input when interacted with, without the exclusive grab that breaks
        // click-outside-to-close. Matches SidebarLeft. (Exclusive was the wrong
        // fix — it's what broke the mouse grab; leaving it unset broke typing.)
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        color: "transparent"

        anchors {
            top: true
            right: true
            bottom: true
        }

        onVisibleChanged: {
            if (visible) {
                GlobalFocusGrab.addDismissable(panelWindow);
            } else {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
        }
        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                panelWindow.hide();
            }
        }

        Loader {
            id: sidebarContentLoader
            active: GlobalStates.sidebarRightOpen || Config?.options.sidebar.keepRightSidebarLoaded
            anchors {
                fill: parent
                margins: Appearance.sizes.hyprlandGapsOut
                leftMargin: Appearance.sizes.elevationMargin
            }
            width: sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
            height: parent.height - Appearance.sizes.hyprlandGapsOut * 2

            focus: GlobalStates.sidebarRightOpen
            // Vi-style keyboard navigation. Lets you drive the entire
            // sidebar from the keyboard:
            //   h / ←   previous top-tab
            //   l / →   next top-tab
            //   j / ↓   scroll down
            //   k / ↑   scroll up
            //   g       jump to top
            //   G       jump to bottom
            //   q / Esc close sidebar
            Keys.onPressed: event => {
                // Don't hijack keys while the user is typing in a text field
                // (todo input, wifi password, etc.). Text-input items expose
                // inputMethodComposing; buttons/loaders/flickables do not.
                const fi = panelWindow.activeFocusItem
                if (fi && typeof fi.inputMethodComposing === "boolean") {
                    return
                }
                const c = sidebarContentLoader.item
                switch (event.key) {
                    case Qt.Key_Q:
                    case Qt.Key_Escape:
                        panelWindow.hide()
                        event.accepted = true
                        break
                    case Qt.Key_H:
                    case Qt.Key_Left:
                        if (c && c.topTab !== undefined)
                            c.topTab = Math.max(0, c.topTab - 1)
                        event.accepted = true
                        break
                    case Qt.Key_L:
                    case Qt.Key_Right:
                        if (c && c.topTab !== undefined && c.userTabsCount !== undefined)
                            c.topTab = Math.min(c.userTabsCount - 1, c.topTab + 1)
                        event.accepted = true
                        break
                    case Qt.Key_J:
                    case Qt.Key_Down:
                        _scrollSidebar(1)
                        event.accepted = true
                        break
                    case Qt.Key_K:
                    case Qt.Key_Up:
                        _scrollSidebar(-1)
                        event.accepted = true
                        break
                    case Qt.Key_G:
                        const f = _findFlickable(c)
                        if (f) {
                            f.contentY = (event.modifiers & Qt.ShiftModifier)
                                ? Math.max(0, f.contentHeight - f.height)
                                : 0
                        }
                        event.accepted = true
                        break
                }
            }
            // Helper: descend into the loaded SidebarRightContent and
            // find the first Flickable so j/k can scroll it.
            function _findFlickable(node) {
                if (!node) return null
                if (node.flickableDirection !== undefined) return node
                const kids = node.children ?? []
                for (const k of kids) {
                    const f = _findFlickable(k)
                    if (f) return f
                }
                return null
            }
            function _scrollSidebar(dir) {
                const f = _findFlickable(sidebarContentLoader.item)
                if (!f) return
                const step = (f.height || 200) * 0.15 * dir
                f.contentY = Math.max(0, Math.min(
                    Math.max(0, f.contentHeight - f.height),
                    f.contentY + step))
            }

            sourceComponent: SidebarRightContent {}
        }
    }

    // IpcHandler + GlobalShortcuts moved to panelFamilies/Shortcuts.qml so they
    // stay registered even while this panel is unloaded by LazyPanelLoader.
}
