import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

// Animated connectivity radar — the local adapter and the connected device
// orbit on a pulsing radar, linked by shimmering strands to floating info
// chips. Opened as a full overlay from the Essentials HUD tab; the bottom
// toggle swaps between Bluetooth and Wi-Fi.
Item {
    id: root
    anchors.fill: parent

    // Per-instance mode override — set to "wifi" / "bt" to fix this radar
    // to a specific mode regardless of GlobalStates. Empty string falls
    // back to the singleton (preserves the existing HUD behaviour).
    property string forceMode: ""
    readonly property bool isWifi: (forceMode.length > 0
        ? forceMode : GlobalStates.essentialsRadarMode) === "wifi"
    readonly property bool radioOn: isWifi
        ? Network.wifiEnabled
        : BluetoothStatus.enabled

    // ── Live data ─────────────────────────────────────────────────────
    readonly property var  btDevice:   BluetoothStatus.firstActiveDevice
    readonly property var  btAdapter:  Bluetooth.defaultAdapter
    readonly property bool btScanning: Bluetooth.defaultAdapter?.discovering ?? false

    readonly property bool deviceConnected: isWifi
        ? (Network.wifiStatus === "connected" || !!Network.active)
        : BluetoothStatus.connected

    readonly property string deviceTitle: isWifi
        ? (Network.networkName !== "" ? Network.networkName : qsTr("No network"))
        : (btDevice ? btDevice.name : qsTr("No device"))
    readonly property string deviceSub: deviceConnected ? qsTr("Connected") : qsTr("Not connected")

    readonly property string adapterTitle: isWifi ? qsTr("Wi-Fi") : qsTr("Bluetooth")
    readonly property string adapterSub: radioOn ? qsTr("Powered on") : qsTr("Powered off")

    // ── Theme ─────────────────────────────────────────────────────────
    readonly property color bg:            Qt.darker(Appearance.colors.colLayer0, 1.18)
    readonly property color adapterAccent: Appearance.colors.colPrimary
    readonly property color deviceAccent:  Appearance.colors.colTertiary
    readonly property color chipBg:        Qt.darker(Appearance.colors.colLayer2, 1.28)
    readonly property color chipBorder:    ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9)

    // ── Animation drivers ─────────────────────────────────────────────
    property real ang: 0
    NumberAnimation on ang {
        from: 0; to: 2 * Math.PI
        duration: 140000; loops: Animation.Infinite; running: root.visible
    }
    property real strandPhase: 0
    Timer {
        interval: 33; repeat: true; running: root.visible
        onTriggered: { root.strandPhase += 0.09; strandCanvas.requestPaint() }
    }
    property real appear: 0
    Component.onCompleted: appear = 1
    Behavior on appear { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

    opacity: appear
    transform: Scale {
        origin.x: root.width / 2; origin.y: root.height / 2
        xScale: 0.95 + root.appear * 0.05
        yScale: 0.95 + root.appear * 0.05
    }

    Keys.onEscapePressed: GlobalStates.essentialsRadarOpen = false

    // ════════════════════════════════════════════════════════════════
    Rectangle {
        id: stage
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: root.bg
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        clip: true

        readonly property real coreSize: 148
        readonly property point cAdapter: Qt.point(width * 0.30, height * 0.45)
        readonly property point cDevice:  Qt.point(width * 0.70, height * 0.45)

        // ── Ambient drifting blobs ────────────────────────────────────
        Repeater {
            model: 2
            Rectangle {
                required property int index
                readonly property real f: index === 0 ? 1.0 : -1.4
                width: stage.width * (index === 0 ? 0.62 : 0.5)
                height: width; radius: width / 2
                x: stage.width / 2 - width / 2 + Math.cos(root.ang * f) * 120
                y: stage.height / 2 - height / 2 + Math.sin(root.ang * f) * 80
                color: index === 0 ? root.adapterAccent : root.deviceAccent
                opacity: root.radioOn ? (index === 0 ? 0.08 : 0.06) : 0.02
                Behavior on opacity { NumberAnimation { duration: 700 } }
            }
        }

        // ── Concentric radar rings ────────────────────────────────────
        Repeater {
            model: 5
            Rectangle {
                required property int index
                readonly property real d: stage.height * (0.34 + index * 0.30)
                width: d; height: d; radius: d / 2
                anchors.centerIn: parent
                color: "transparent"
                border.width: 1
                border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.93)
            }
        }
        Rectangle {
            id: pulse
            anchors.centerIn: parent
            color: "transparent"
            border.width: 2
            border.color: root.adapterAccent
            property real p: 0
            visible: root.radioOn
            width: stage.height * (0.34 + p * 1.4)
            height: width; radius: width / 2
            opacity: (1 - p) * 0.35
            SequentialAnimation on p {
                running: root.radioOn && root.visible
                loops: Animation.Infinite
                NumberAnimation { from: 0; to: 1; duration: 3200; easing.type: Easing.OutCubic }
                PauseAnimation { duration: 400 }
            }
        }

        // ── Strand connectors ─────────────────────────────────────────
        Canvas {
            id: strandCanvas
            anchors.fill: parent
            renderStrategy: Canvas.Threaded
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.lineCap = "round"
                ctx.lineJoin = "round"

                function strand(sx, sy, tx, ty, accent) {
                    const dx = tx - sx, dy = ty - sy
                    const dist = Math.sqrt(dx * dx + dy * dy)
                    if (dist < 24) return
                    const a = Math.atan2(dy, dx)
                    const ca = Math.cos(a), sa = Math.sin(a)
                    const px = -sa, py = ca
                    const startOff = stage.coreSize / 2 + 4
                    const draw = dist - startOff - 22
                    if (draw <= 0) return
                    const bx = sx + ca * startOff, by = sy + sa * startOff
                    const steps = 9
                    function trace(amp, freq, phase) {
                        ctx.beginPath()
                        ctx.moveTo(bx, by)
                        for (let j = 1; j <= steps; j++) {
                            const t = j / steps
                            const env = Math.sin(t * Math.PI)
                            const off = Math.sin(phase + t * freq) * amp * env
                            ctx.lineTo(bx + ca * draw * t + px * off,
                                       by + sa * draw * t + py * off)
                        }
                    }
                    trace(6, 6, root.strandPhase * 2.5)
                    ctx.lineWidth = 7;  ctx.strokeStyle = accent;  ctx.globalAlpha = 0.13; ctx.stroke()
                    ctx.lineWidth = 1.6; ctx.strokeStyle = "#ffffff"; ctx.globalAlpha = 0.55; ctx.stroke()
                    trace(11, 8, -root.strandPhase * 1.6)
                    ctx.lineWidth = 2; ctx.strokeStyle = accent; ctx.globalAlpha = 0.3; ctx.stroke()
                    ctx.globalAlpha = 1
                }

                if (root.radioOn) {
                    const ax = adapterCore.x + adapterCore.width / 2
                    const ay = adapterCore.y + adapterCore.height / 2
                    const aChips = [chipA0, chipA1, chipA2]
                    for (const c of aChips)
                        strand(ax, ay, c.x + c.width / 2, c.y + c.height / 2, root.adapterAccent)
                }
                if (root.deviceConnected) {
                    const dx2 = deviceCore.x + deviceCore.width / 2
                    const dy2 = deviceCore.y + deviceCore.height / 2
                    const dChips = [chipD0, chipD1, chipD2]
                    for (const c of dChips)
                        strand(dx2, dy2, c.x + c.width / 2, c.y + c.height / 2, root.deviceAccent)
                }
            }
        }

        // ── Cores ─────────────────────────────────────────────────────
        component Core: Item {
            id: c
            property string title
            property string subtitle
            property string glyph
            property bool   on: false
            property color  accent
            width: stage.coreSize; height: stage.coreSize

            Rectangle {
                anchors.centerIn: parent
                width: parent.width + 56; height: width; radius: width / 2
                color: c.accent
                opacity: c.on ? 0.16 : 0
                Behavior on opacity { NumberAnimation { duration: 400 } }
            }
            scale: 1 + (c.on ? Math.sin(root.ang * 6) * 0.012 : 0)

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: c.on ? c.accent : Qt.lighter(root.bg, 1.7)
                Behavior on color { ColorAnimation { duration: 400 } }
                border.width: 1
                border.color: c.on ? Qt.lighter(c.accent, 1.15)
                                   : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.86)

                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - 26
                    spacing: 1
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: c.glyph; iconSize: 30; fill: 1
                        color: c.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: c.title; elide: Text.ElideMiddle
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: c.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: c.subtitle
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        opacity: 0.7
                        color: c.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        Core {
            id: adapterCore
            x: stage.cAdapter.x - width / 2
            y: stage.cAdapter.y - height / 2
            title: root.adapterTitle
            subtitle: root.adapterSub
            glyph: root.isWifi ? "router" : "bluetooth"
            on: root.radioOn
            accent: root.adapterAccent
        }
        Core {
            id: deviceCore
            x: stage.cDevice.x - width / 2
            y: stage.cDevice.y - height / 2
            title: root.deviceTitle
            subtitle: root.deviceSub
            glyph: root.isWifi ? "wifi" : "headphones"
            on: root.deviceConnected
            accent: root.deviceAccent
        }

        // ── Info chips ────────────────────────────────────────────────
        component Chip: Rectangle {
            id: chip
            property string icon
            property string big
            property string small
            property point coreAt
            property real dx: 0
            property real dy: 0
            implicitWidth: chipRow.implicitWidth + 22
            implicitHeight: 44
            width: implicitWidth; height: implicitHeight
            x: coreAt.x + dx - width / 2 + Math.cos(root.ang * 4 + dy) * 3
            y: coreAt.y + dy - height / 2 + Math.sin(root.ang * 4 + dx) * 3
            radius: 11
            color: root.chipBg
            border.width: 1
            border.color: root.chipBorder

            RowLayout {
                id: chipRow
                anchors.centerIn: parent
                spacing: 8
                MaterialSymbol {
                    text: chip.icon; iconSize: 18
                    color: root.adapterAccent
                }
                ColumnLayout {
                    spacing: -2
                    StyledText {
                        text: chip.big
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        text: chip.small
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        opacity: 0.5
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }
        }

        Chip {
            id: chipA0
            coreAt: stage.cAdapter; dx: -22; dy: -118
            icon: root.isWifi ? "settings_ethernet" : "settings_bluetooth"
            big: root.radioOn ? qsTr("On") : qsTr("Off")
            small: qsTr("Adapter")
        }
        Chip {
            id: chipA1
            coreAt: stage.cAdapter; dx: -150; dy: 4
            icon: "devices"
            big: root.isWifi
                ? (Network.wifiNetworks.length + "")
                : ((BluetoothStatus.connectedDevices.length
                    + BluetoothStatus.pairedButNotConnectedDevices.length) + "")
            small: root.isWifi ? qsTr("Networks") : qsTr("Paired")
        }
        Chip {
            id: chipA2
            coreAt: stage.cAdapter; dx: -66; dy: 116
            icon: "radar"
            big: (root.isWifi ? Network.wifiScanning : root.btScanning) ? qsTr("Scanning") : qsTr("Idle")
            small: qsTr("Status")
        }

        Chip {
            id: chipD0
            coreAt: stage.cDevice; dx: 26; dy: -118
            icon: "battery_full"
            big: {
                if (root.isWifi) return Network.networkStrength > 0 ? Network.networkStrength + "%" : "—"
                if (root.btDevice && root.btDevice.batteryAvailable)
                    return Math.round(root.btDevice.battery * 100) + "%"
                // BlueZ publishes no Battery1 for JBL speakers; that number only
                // exists behind Harman's own BLE control service.
                if (JblBattery.isSupported(root.btDevice?.name ?? "") && JblBattery.percent >= 0)
                    return JblBattery.percent + "%"
                return "—"
            }
            small: root.isWifi ? qsTr("Signal") : qsTr("Battery")
        }
        Chip {
            id: chipD1
            coreAt: stage.cDevice; dx: 150; dy: 4
            icon: root.isWifi ? "lan" : "tag"
            big: root.isWifi
                ? (Network.networkName !== "" ? Network.networkName : "—")
                : (root.btDevice ? root.btDevice.address : "—")
            small: root.isWifi ? qsTr("Network") : qsTr("MAC Address")
        }
        Chip {
            id: chipD2
            coreAt: stage.cDevice; dx: 66; dy: 116
            icon: root.isWifi ? "lock" : "headphones"
            big: root.isWifi
                ? qsTr("Secured")
                : (root.btDevice ? qsTr("Audio") : qsTr("None"))
            small: root.isWifi ? qsTr("Security") : qsTr("Profile")
        }

        // ── Center scan pill ──────────────────────────────────────────
        Rectangle {
            id: scanPill
            anchors.horizontalCenter: parent.horizontalCenter
            y: stage.cAdapter.y - height / 2
            implicitWidth: scanRow.implicitWidth + 26
            implicitHeight: 46
            width: implicitWidth; height: implicitHeight
            radius: 12
            color: scanHov.hovered ? Qt.lighter(root.chipBg, 1.4) : root.chipBg
            border.width: 1
            border.color: root.chipBorder
            Behavior on color { ColorAnimation { duration: 120 } }

            RowLayout {
                id: scanRow
                anchors.centerIn: parent
                spacing: 7
                MaterialSymbol { text: "search"; iconSize: 18; color: root.adapterAccent }
                ColumnLayout {
                    spacing: -2
                    StyledText {
                        text: qsTr("Scan Devices")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        text: qsTr("Refresh nearby")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        opacity: 0.5
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }
            HoverHandler { id: scanHov }
            TapHandler {
                onTapped: {
                    if (root.isWifi) Network.rescanWifi()
                    else if (root.btAdapter) root.btAdapter.discovering = true
                }
            }
        }

        // ── Bottom mode toggle ────────────────────────────────────────
        // Hidden when forceMode is set — the host (e.g. ConnectivityPopup)
        // has already pinned the mode, so the toggle would do nothing.
        Rectangle {
            id: modeToggle
            visible: root.forceMode.length === 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            implicitWidth: 280
            implicitHeight: 46
            radius: 14
            color: root.chipBg
            border.width: 1
            border.color: root.chipBorder

            Rectangle {
                width: parent.width / 2 - 4
                height: parent.height - 8
                y: 4
                x: root.isWifi ? 4 : parent.width / 2
                radius: 11
                color: root.adapterAccent
                Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }
            Row {
                anchors.fill: parent
                Repeater {
                    model: [
                        { id: "wifi", icon: "wifi",      label: qsTr("Wi-Fi")     },
                        { id: "bt",   icon: "bluetooth", label: qsTr("Bluetooth") }
                    ]
                    Item {
                        id: modeBtn
                        required property var modelData
                        width: modeToggle.width / 2
                        height: modeToggle.height
                        readonly property bool sel: GlobalStates.essentialsRadarMode === modelData.id

                        // Subtle hover overlay — only visible on the inactive
                        // half (the active half is already the bright pill).
                        HoverHandler { id: modeBtnHov }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 4
                            radius: 11
                            visible: !modeBtn.sel && (modeBtnHov.hovered || Appearance.touchUi)
                            color: Appearance.colors.colLayer1Hover
                            opacity: 0.55
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                        }
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 7
                            MaterialSymbol {
                                text: modeBtn.modelData.icon; iconSize: 19
                                color: modeBtn.sel ? Appearance.colors.colOnPrimary
                                                   : Appearance.colors.colOnLayer1
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                            StyledText {
                                text: modeBtn.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: modeBtn.sel ? Appearance.colors.colOnPrimary
                                                   : Appearance.colors.colOnLayer1
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                        }
                        TapHandler {
                            cursorShape: Qt.PointingHandCursor
                            onTapped: GlobalStates.essentialsRadarMode = modeBtn.modelData.id
                        }
                    }
                }
            }
        }

        // ── Power button (toggle radio) ───────────────────────────────
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 18
            implicitWidth: 46; implicitHeight: 46
            width: 46; height: 46
            radius: width / 2
            color: root.radioOn ? root.adapterAccent : root.chipBg
            border.width: 1
            border.color: root.radioOn ? Qt.lighter(root.adapterAccent, 1.15) : root.chipBorder
            Behavior on color { ColorAnimation { duration: 200 } }
            MaterialSymbol {
                anchors.centerIn: parent
                text: "power_settings_new"; iconSize: 22
                color: root.radioOn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
            }
            TapHandler {
                onTapped: {
                    if (root.isWifi) Network.toggleWifi()
                    else if (root.btAdapter) root.btAdapter.enabled = !root.btAdapter.enabled
                }
            }
            StyledToolTip { text: qsTr("Toggle %1").arg(root.adapterTitle) }
        }

        // ── Close button ──────────────────────────────────────────────
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            implicitWidth: 38; implicitHeight: 38
            width: 38; height: 38
            radius: width / 2
            color: closeHov.hovered ? Qt.lighter(root.chipBg, 1.5) : root.chipBg
            border.width: 1
            border.color: root.chipBorder
            Behavior on color { ColorAnimation { duration: 120 } }
            MaterialSymbol {
                anchors.centerIn: parent
                text: "close"; iconSize: 20
                color: Appearance.colors.colOnLayer1
            }
            HoverHandler { id: closeHov }
            TapHandler { onTapped: GlobalStates.essentialsRadarOpen = false }
        }
    }
}
