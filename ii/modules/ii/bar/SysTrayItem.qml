import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

MouseArea {
    id: root
    required property SystemTrayItem item
    property bool targetMenuOpen: false

    signal menuOpened(qsWindow: var)
    signal menuClosed()

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    implicitWidth: 20
    implicitHeight: 20
    // Long-press is the touch spelling of right-click. Without it a tray
    // item's menu — often the only UI an app has — is unreachable on a
    // tablet. `heldOpen` stops the release from also activating the app.
    property bool heldOpen: false
    pressAndHoldInterval: 450
    onPressAndHold: (event) => {
        if (event.button !== Qt.LeftButton || !item.hasMenu) return;
        root.heldOpen = true;
        menu.open();
    }
    onPressed: (event) => {
        root.heldOpen = false;
        switch (event.button) {
        case Qt.LeftButton:
            break;   // acted on release, so a hold can pre-empt it
        case Qt.RightButton:
            if (item.hasMenu) menu.open();
            break;
        }
        event.accepted = true;
    }
    onReleased: (event) => {
        if (event.button === Qt.LeftButton && !root.heldOpen) {
            item.activate();
            if (root.activateIsUnreliable)
                activateFallback.restart();
        }
        root.heldOpen = false;
        event.accepted = true;
    }

    // Electron apps on Wayland stop honouring SNI Activate once they have
    // unmapped their window (closed to tray) — the icon becomes a dead end
    // with no way back. Re-running the launcher reaches the app's own
    // singleton, which does restore it.
    readonly property bool activateIsUnreliable:
        (root.item?.id ?? "").toLowerCase().includes("discord")

    Timer {
        id: activateFallback
        interval: 1500
        onTriggered: {
            const shown = HyprlandData.windowList.some(w =>
                (w.class ?? "").toLowerCase().includes("discord"));
            if (!shown)
                Quickshell.execDetached(["discord-open"]);
        }
    }
    onEntered: {
        tooltip.text = TrayService.getTooltipForItem(root.item);
    }

    Loader {
        id: menu
        function open() {
            menu.active = true;
        }
        active: false
        sourceComponent: SysTrayMenu {
            Component.onCompleted: this.open();
            trayItemMenuHandle: root.item.menu
            anchor {
                window: root.QsWindow.window
                rect.x: root.x + (Config.options.bar.vertical ? 0 : QsWindow.window?.width)
                rect.y: root.y + (Config.options.bar.vertical ? QsWindow.window?.height : 0)
                rect.height: root.height
                rect.width: root.width
                edges: Config.options.bar.bottom ? (Edges.Top | Edges.Left) : (Edges.Bottom | Edges.Right)
                gravity: Config.options.bar.bottom ? (Edges.Top | Edges.Left) : (Edges.Bottom | Edges.Right)
            }
            onMenuOpened: (window) => root.menuOpened(window);
            onMenuClosed: {
                root.menuClosed();
                menu.active = false;
            }
        }
    }

    IconImage {
        id: trayIcon
        visible: !Config.options.tray.monochromeIcons
        source: root.item.icon
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
    }

    Loader {
        active: Config.options.tray.monochromeIcons
        anchors.fill: trayIcon
        sourceComponent: Item {
            Desaturate {
                id: desaturatedIcon
                visible: false // There's already color overlay
                anchors.fill: parent
                source: trayIcon
                desaturation: 0.8 // 1.0 means fully grayscale
            }
            ColorOverlay {
                anchors.fill: desaturatedIcon
                source: desaturatedIcon
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9)
            }
        }
    }

    // An item whose icon won't load is otherwise a 20×20 invisible hit area:
    // the app is in the tray and clickable, but you cannot see it or find it.
    // Discord does exactly this — it hands over a pixmap Quickshell can't
    // build ("Unable to create pixmap for tray icon"), so closing it to tray
    // makes it unreachable. A placeholder keeps it findable.
    MaterialSymbol {
        anchors.centerIn: parent
        visible: trayIcon.status !== Image.Ready
        text: "adjust"
        iconSize: Appearance.font.pixelSize.larger
        color: Appearance.colors.colOnLayer0
    }

    PopupToolTip {
        id: tooltip
        extraVisibleCondition: root.containsMouse
        alternativeVisibleCondition: extraVisibleCondition
        anchorEdges: (!Config.options.bar.bottom && !Config.options.bar.vertical) ? Edges.Bottom : Edges.Top
    }

}
