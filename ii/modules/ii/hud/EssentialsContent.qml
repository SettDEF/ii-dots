pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

// Essentials HUD page — system controls, battery / power profile, and
// system info at a glance. Designed for the ASUS ROG Flow Z13: the
// power-profile card binds to Rog.profile + Rog.setProfile() so flipping
// from Quiet → Balanced → Performance lands in one tap.
Item {
    id: root
    implicitHeight: contentCol.implicitHeight + 28

    // System info refreshed on HUD open and every 30 s after that. uname /
    // hostname / uptime are dirt cheap — single readlink + open(/proc/...)
    // each — but no point polling at the perf-tab cadence.
    property string sysUptime: ""
    property string sysKernel: ""
    property string sysHostname: ""
    property string sysIp: ""

    // Mic mute state — polled from wpctl. Toggled with wpctl set-mute.
    property bool micMuted: false
    Process { id: micCheckProc; stdout: StdioCollector { onStreamFinished: {
        root.micMuted = text.indexOf("MUTED") >= 0
    }}}
    Process { id: micToggleProc }
    function refreshMic() {
        micCheckProc.exec({ command: ["bash","-c",
            "wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null"] })
    }
    function toggleMic() {
        micToggleProc.exec({ command: ["bash","-c",
            "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle && wpctl get-volume @DEFAULT_AUDIO_SOURCE@"] })
        refreshMic()
    }
    Timer { interval: 2000; running: root.visible; repeat: true; onTriggered: root.refreshMic() }

    Process { id: sysInfoProc; stdout: StdioCollector { onStreamFinished: {
        const lines = text.trim().split("\n")
        if (lines.length >= 4) {
            root.sysUptime   = lines[0]
            root.sysKernel   = lines[1]
            root.sysHostname = lines[2]
            root.sysIp       = lines[3]
        }
    }}}
    function refreshSysInfo() {
        sysInfoProc.exec({ command: ["bash","-c",
            "uptime -p | sed 's/^up //'; uname -r; hostname; " +
            "ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i==\"src\")print $(i+1)}' | head -1"
        ] })
    }
    Component.onCompleted: refreshSysInfo()
    Timer {
        interval: 30000; repeat: true; running: root.visible
        onTriggered: root.refreshSysInfo()
    }

    ColumnLayout {
        id: contentCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 12

        // ── Section 1 · Quick toggles ────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            component TogglePill: Rectangle {
                id: tg
                property string icon: ""
                property string label: ""
                property bool on: false
                property string sub: ""
                signal pressed()

                Layout.fillWidth: true
                Layout.preferredHeight: 76
                radius: Appearance.rounding.normal
                color: tg.on ? Appearance.colors.colPrimaryContainer
                             : Appearance.colors.colLayer1
                border.width: 1
                border.color: tg.on ? Qt.lighter(Appearance.colors.colPrimaryContainer, 1.2)
                                    : Appearance.colors.colLayer0Border
                Behavior on color { ColorAnimation { duration: 160 } }

                HoverHandler { id: pillHov }
                TapHandler { onTapped: tg.pressed() }

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    visible: pillHov.hovered || Appearance.touchUi
                    color: Appearance.colors.colLayer1Hover
                    opacity: 0.5
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 10
                    MaterialSymbol {
                        text: tg.icon; iconSize: 28
                        fill: tg.on ? 1 : 0
                        color: tg.on ? Appearance.m3colors.m3onPrimaryContainer
                                     : Appearance.colors.colOnLayer1
                    }
                    ColumnLayout {
                        spacing: -2
                        StyledText {
                            text: tg.label
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: tg.on ? Appearance.m3colors.m3onPrimaryContainer
                                         : Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            text: tg.sub
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            opacity: 0.6
                            color: tg.on ? Appearance.m3colors.m3onPrimaryContainer
                                         : Appearance.colors.colOnLayer1
                        }
                    }
                }
            }

            TogglePill {
                icon: "wifi"
                label: "Wi-Fi"
                on: Network.wifiEnabled
                sub: Network.wifiEnabled
                    ? (Network.networkName !== "" ? Network.networkName : "On")
                    : "Off"
                onPressed: Network.toggleWifi()
            }
            TogglePill {
                icon: "bluetooth"
                label: "Bluetooth"
                on: BluetoothStatus.enabled
                sub: BluetoothStatus.enabled
                    ? (BluetoothStatus.connected ? "Connected" : "On")
                    : "Off"
                onPressed: {
                    const a = Bluetooth.defaultAdapter
                    if (a) a.enabled = !a.enabled
                }
            }
            TogglePill {
                icon: root.micMuted ? "mic_off" : "mic"
                label: "Mic"
                on: !root.micMuted
                sub: root.micMuted ? "Muted" : "Live"
                onPressed: root.toggleMic()
            }
        }

        // ── Section 2 · Battery + ROG power profile ──────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: powerRow.implicitHeight + 28
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            RowLayout {
                id: powerRow
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 18

                // Battery — circular gauge + status text.
                Item {
                    Layout.preferredWidth: 96
                    Layout.preferredHeight: 96

                    readonly property real pct: Battery.percentage
                    readonly property color batColor: pct < 0.20
                        ? Appearance.m3colors.m3error
                        : pct < 0.40
                            ? Appearance.m3colors.m3tertiary
                            : Appearance.colors.colPrimary

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: 4
                        border.color: ColorUtils.transparentize(parent.batColor, 0.85)
                    }
                    // Foreground arc via Canvas — fills the ring up to pct.
                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            ctx.lineWidth = 4
                            ctx.lineCap = "round"
                            ctx.strokeStyle = parent.batColor
                            ctx.beginPath()
                            const cx = width / 2, cy = height / 2
                            const r = (width - 4) / 2
                            const start = -Math.PI / 2
                            const end = start + (parent.pct * 2 * Math.PI)
                            ctx.arc(cx, cy, r, start, end, false)
                            ctx.stroke()
                        }
                        Connections {
                            target: Battery
                            function onPercentageChanged() { parent.requestPaint() }
                        }
                    }
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: -2
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Math.round(Battery.percentage * 100) + "%"
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.Bold
                            color: parent.parent.batColor
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Battery.isCharging ? "Charging"
                                 : Battery.isPluggedIn ? "Plugged"
                                                       : "On battery"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer0
                            opacity: 0.55
                        }
                    }
                }

                // Power profile (ASUS ROG). Tap a chip to apply it via asusctl.
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StyledText {
                        text: "Power profile"
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.5
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: Rog.profiles
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool sel: Rog.profile === modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                radius: Appearance.rounding.normal
                                color: sel ? Appearance.colors.colPrimary
                                           : (chipHov.hovered ? Appearance.colors.colLayer1Hover
                                                              : Appearance.colors.colLayer2)
                                border.width: 1
                                border.color: sel ? Qt.lighter(Appearance.colors.colPrimary, 1.15)
                                                  : Appearance.colors.colLayer0Border
                                Behavior on color { ColorAnimation { duration: 150 } }

                                HoverHandler { id: chipHov }
                                TapHandler { onTapped: Rog.setProfile(modelData) }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    MaterialSymbol {
                                        text: modelData === "Performance" ? "rocket_launch"
                                            : modelData === "Quiet" ? "energy_savings_leaf"
                                                                    : "balance"
                                        iconSize: 18
                                        color: sel ? Appearance.colors.colOnPrimary
                                                   : Appearance.colors.colOnLayer1
                                    }
                                    StyledText {
                                        text: modelData
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: sel ? Font.DemiBold : Font.Normal
                                        color: sel ? Appearance.colors.colOnPrimary
                                                   : Appearance.colors.colOnLayer1
                                    }
                                }
                            }
                        }
                    }
                    StyledText {
                        text: "Charge limit: " + Rog.batteryLimit + "%"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.45
                    }
                }
            }
        }

        // ── Section 3 · System info ──────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: sysCol.implicitHeight + 28
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            ColumnLayout {
                id: sysCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 6

                StyledText {
                    text: "System"
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.45
                }

                component InfoRow: RowLayout {
                    property string icon: ""
                    property string label: ""
                    property string value: ""
                    Layout.fillWidth: true
                    spacing: 10
                    MaterialSymbol {
                        text: icon; iconSize: 18
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.55
                    }
                    StyledText {
                        text: label
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.55
                        Layout.preferredWidth: 80
                    }
                    StyledText {
                        text: value
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                InfoRow { icon: "schedule"; label: "Uptime";   value: root.sysUptime   || "—" }
                InfoRow { icon: "memory";   label: "Kernel";   value: root.sysKernel   || "—" }
                InfoRow { icon: "computer"; label: "Hostname"; value: root.sysHostname || "—" }
                InfoRow { icon: "lan";      label: "IP";       value: root.sysIp       || "—" }
            }
        }
    }
}
