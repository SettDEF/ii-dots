// Connectivity popup — a single unified floating card sitting under the
// bar-attached tab strip. Bluetooth occupies the left half, Wi-Fi the
// right; each half mounts an EssentialsRadar pinned to its mode. The
// card grows/shrinks to hold whichever halves are active. The tab strip
// hangs from the bar with the same Caelestia concave-shouldered shape
// the HUD's SubTabTray uses, so the popup reads as an extension of it.
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.hud
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Wayland

Scope {
    id: scope

    // This popup had no programmatic control at all — it could only be opened
    // by clicking the bar icons. Every other surface here has an IPC handler.
    IpcHandler {
        target: "connectivity"
        function wifi(): void { GlobalStates.connectivityWifiOpen = !GlobalStates.connectivityWifiOpen }
        function bt(): void   { GlobalStates.connectivityBluetoothOpen = !GlobalStates.connectivityBluetoothOpen }
        function vpn(): void  { GlobalStates.connectivityVpnOpen = !GlobalStates.connectivityVpnOpen }
        function close(): void {
            GlobalStates.connectivityWifiOpen = false;
            GlobalStates.connectivityBluetoothOpen = false;
            GlobalStates.connectivityVpnOpen = false;
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: popupWindow
            required property var modelData
            screen: modelData
            visible: GlobalStates.connectivityPopupOpen
                     || GlobalStates.connectivityBluetoothOpen
                     || GlobalStates.connectivityWifiOpen
                     || GlobalStates.connectivityVpnOpen

            exclusiveZone: 0
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:connectivityPopup"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors { top: true; bottom: true; left: true; right: true }

            // Only the tab strip and the merged card are interactive — clicks
            // outside dismiss via GlobalFocusGrab.
            mask: Region {
                item: tabStrip
                Region { item: card }
            }

            onVisibleChanged: {
                if (visible) {
                    GlobalFocusGrab.addDismissable(popupWindow)
                    Network.enableWifi()
                    Network.rescanWifi()
                    if (Bluetooth.defaultAdapter) {
                        Bluetooth.defaultAdapter.enabled = true
                        Bluetooth.defaultAdapter.discovering = true
                    }
                } else {
                    GlobalFocusGrab.removeDismissable(popupWindow)
                    if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = false
                }
            }
            Component.onDestruction: GlobalFocusGrab.removeDismissable(popupWindow)
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    GlobalStates.connectivityBluetoothOpen = false
                    GlobalStates.connectivityWifiOpen = false
                }
            }

            // ── Sizing tokens ───────────────────────────────────────────
            readonly property real halfWidth: 460
            readonly property real cardHeight: 540
            readonly property real cardTopMargin: 58
            readonly property real cardLeftMargin: 16
            readonly property bool btOpen:   GlobalStates.connectivityBluetoothOpen
            readonly property bool wifiOpen: GlobalStates.connectivityWifiOpen
            readonly property bool vpnOpen:  GlobalStates.connectivityVpnOpen
            readonly property int  openCount: (btOpen ? 1 : 0) + (wifiOpen ? 1 : 0) + (vpnOpen ? 1 : 0)

            // ── Tab strip — hangs from the bar, multi-select pills ──────
            Item {
                id: tabStrip
                readonly property real fil: 15
                readonly property real br: 18
                readonly property real bodyW: pillTabBar.implicitWidth + 28
                readonly property real bodyH: 44
                implicitWidth: bodyW + fil * 2
                width: implicitWidth
                height: bodyH
                anchors.horizontalCenter: parent.horizontalCenter
                y: -4
                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                onWidthChanged:  shapeCanvas.requestPaint()
                onHeightChanged: shapeCanvas.requestPaint()

                Canvas {
                    id: shapeCanvas
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d")
                        const cx = width / 2
                        const bw = tabStrip.bodyW, bh = tabStrip.bodyH
                        const f = tabStrip.fil, b = tabStrip.br
                        ctx.reset()
                        ctx.fillStyle = Appearance.colors.colLayer0
                        ctx.strokeStyle = Appearance.colors.colLayer0Border
                        ctx.lineWidth = 1
                        ctx.beginPath()
                        ctx.moveTo(cx - bw / 2 - f, 0)
                        ctx.arc(cx - bw / 2 - f, f, f, -Math.PI / 2, 0, false)
                        ctx.lineTo(cx - bw / 2, bh - b)
                        ctx.arc(cx - bw / 2 + b, bh - b, b, Math.PI, Math.PI / 2, true)
                        ctx.lineTo(cx + bw / 2 - b, bh)
                        ctx.arc(cx + bw / 2 - b, bh - b, b, Math.PI / 2, 0, true)
                        ctx.lineTo(cx + bw / 2, f)
                        ctx.arc(cx + bw / 2 + f, f, f, Math.PI, 3 * Math.PI / 2, false)
                        ctx.closePath()
                        ctx.fill()
                        ctx.stroke()
                    }
                    Connections {
                        target: Appearance.colors
                        function onColLayer0Changed() { shapeCanvas.requestPaint() }
                    }
                }

                PillTabBar {
                    id: pillTabBar
                    anchors.centerIn: parent
                    height: 32
                    multiSelect: true
                    forceExpanded: true
                    tabs: [
                        { id: "wifi", icon: "wifi",      label: qsTr("Wi-Fi")     },
                        { id: "bt",   icon: "bluetooth", label: qsTr("Bluetooth") },
                        { id: "vpn",  icon: "vpn_key",   label: qsTr("VPN")       },
                    ]
                    activeIds: [
                        ...(GlobalStates.connectivityWifiOpen      ? ["wifi"] : []),
                        ...(GlobalStates.connectivityBluetoothOpen ? ["bt"]   : []),
                        ...(GlobalStates.connectivityVpnOpen        ? ["vpn"]  : []),
                    ]
                    current: ""
                    onTabSelected: id => {
                        if (id === "wifi") {
                            GlobalStates.connectivityWifiOpen = !GlobalStates.connectivityWifiOpen
                            if (GlobalStates.connectivityWifiOpen) {
                                Network.enableWifi(); Network.rescanWifi()
                            }
                        } else if (id === "bt") {
                            GlobalStates.connectivityBluetoothOpen = !GlobalStates.connectivityBluetoothOpen
                            if (GlobalStates.connectivityBluetoothOpen && Bluetooth.defaultAdapter) {
                                Bluetooth.defaultAdapter.enabled = true
                                Bluetooth.defaultAdapter.discovering = true
                            }
                        } else if (id === "vpn") {
                            GlobalStates.connectivityVpnOpen = !GlobalStates.connectivityVpnOpen
                            if (GlobalStates.connectivityVpnOpen) Vpn.refresh()
                        }
                    }
                }
            }

            // ── Unified card ────────────────────────────────────────────
            Rectangle {
                id: card
                readonly property real targetWidth: popupWindow.halfWidth * Math.max(1, popupWindow.openCount)
                x: popupWindow.cardLeftMargin
                y: popupWindow.cardTopMargin
                width: targetWidth
                height: popupWindow.cardHeight
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                opacity: popupWindow.openCount > 0 ? 1 : 0
                scale:   popupWindow.openCount > 0 ? 1 : 0.94
                visible: opacity > 0.01
                transformOrigin: Item.Top
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on scale   { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on width   { NumberAnimation { duration: 260; easing.type: Easing.InOutCubic } }

                // Close (X) — top-right corner
                Rectangle {
                    id: closeBtn
                    width: 28; height: 28
                    radius: width / 2
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 10
                    color: closeHov.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover)
                    z: 10
                    Behavior on color { ColorAnimation { duration: 160 } }
                    HoverHandler { margin: Appearance.sizes.touchSlop; id: closeHov }
                    TapHandler {
                        margin: Appearance.sizes.touchSlop
                        onTapped: {
                            GlobalStates.connectivityBluetoothOpen = false
                            GlobalStates.connectivityWifiOpen = false
                            GlobalStates.connectivityVpnOpen = false
                        }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer0
                    }
                }

                // Side-by-side radar halves
                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    Item {
                        id: btHalf
                        Layout.fillHeight: true
                        Layout.preferredWidth: popupWindow.halfWidth
                        visible: popupWindow.btOpen
                        clip: true
                        EssentialsRadar {
                            anchors.fill: parent
                            forceMode: "bt"
                        }
                    }

                    // Divider between halves when both are open
                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        Layout.topMargin: 16
                        Layout.bottomMargin: 16
                        color: Appearance.colors.colLayer0Border
                        visible: popupWindow.btOpen && popupWindow.wifiOpen
                    }

                    Item {
                        id: wifiHalf
                        Layout.fillHeight: true
                        Layout.preferredWidth: popupWindow.halfWidth
                        visible: popupWindow.wifiOpen
                        clip: true
                        EssentialsRadar {
                            anchors.fill: parent
                            forceMode: "wifi"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        Layout.topMargin: 16
                        Layout.bottomMargin: 16
                        color: Appearance.colors.colLayer0Border
                        visible: popupWindow.vpnOpen && (popupWindow.btOpen || popupWindow.wifiOpen)
                    }

                    Item {
                        id: vpnHalf
                        Layout.fillHeight: true
                        Layout.preferredWidth: popupWindow.halfWidth
                        visible: popupWindow.vpnOpen
                        clip: true
                        VpnView { anchors.fill: parent }
                    }
                }
            }
        }
    }
}
