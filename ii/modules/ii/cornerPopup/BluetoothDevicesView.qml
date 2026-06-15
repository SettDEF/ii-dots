// Bluetooth devices panel — clean rewrite.  Lists connected devices in
// a tidy rounded card with proper padding, smooth expand / collapse, and
// device-type-specific controls (mouse: DPI/SmartShift/Scroll via Solaar;
// audio: codec + volume).
pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

Rectangle {
    id: root

    required property real popupRounding
    property bool isSidebar: false

    // ── Sizing tokens ──────────────────────────────────────────────────────
    readonly property real outerPad: isSidebar ? 16 : 16
    readonly property real outerBottomPad: isSidebar ? 24 : 16
    readonly property real cardPad:  10
    readonly property real cardGap:  8
    // Use the global animation-speed factor so users can dial all
    // tweens in this widget down to instant by setting it to 0.
    readonly property real animMs: Appearance.animDur(220)

    radius: isSidebar ? Appearance.rounding.large : popupRounding
    color: isSidebar ? Appearance.colors.colLayer1 : Appearance.colors.colLayer0
    border.width: isSidebar ? 0 : 1
    border.color: Appearance.colors.colLayer0Border
    implicitHeight: body.implicitHeight + outerPad + outerBottomPad
    Behavior on implicitHeight {
        NumberAnimation { duration: animMs; easing.type: Easing.OutCubic }
    }

    // ── Helpers ─────────────────────────────────────────────────────────────
    function _kind(d) {
        const i = (d?.icon ?? "").toLowerCase()
        if (i.includes("mouse"))    return "mouse"
        if (i.includes("keyboard")) return "keyboard"
        if (i.includes("phone"))    return "phone"
        if (i.includes("audio") || i.includes("headset")
            || i.includes("headphone") || i.includes("speaker")) return "audio"
        return "generic"
    }
    function _icon(k) {
        switch (k) {
            case "mouse":    return "mouse"
            case "keyboard": return "keyboard"
            case "phone":    return "phone_iphone"
            case "audio":    return "headphones"
        }
        return "bluetooth"
    }
    function _runShell(line) {
        cmdProc.command = ["bash", "-c", line]
        cmdProc.running = true
    }
    Process { id: cmdProc }

    // ── Body ───────────────────────────────────────────────────────────────
    ColumnLayout {
        id: body
        anchors {
            left: parent.left; right: parent.right; top: parent.top
            leftMargin: root.outerPad; rightMargin: root.outerPad; topMargin: root.outerPad
        }
        spacing: 10

        // Header ------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol {
                text: BluetoothStatus.connected ? "bluetooth_connected" : "bluetooth"
                iconSize: Appearance.font.pixelSize.larger
                color: BluetoothStatus.connected
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                text: qsTr("Devices")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                text: BluetoothStatus.connectedDevices.length
                    + qsTr(" connected")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            height: 1
            color: Appearance.colors.colLayer0Border
            opacity: 0.5
        }

        // Device cards ------------------------------------------------------
        Repeater {
            model: BluetoothStatus.connectedDevices

            delegate: Rectangle {
                id: card
                required property var modelData
                required property int index

                readonly property string kind: root._kind(modelData)
                readonly property string addr: modelData?.address ?? ""
                readonly property string devName: modelData?.name ?? "?"
                readonly property int    bat:  Math.round(modelData?.batteryPercentage ?? -1)
                property bool expanded: false

                Layout.fillWidth: true
                implicitHeight: cardCol.implicitHeight + root.cardPad * 2
                Behavior on implicitHeight {
                    NumberAnimation { duration: root.animMs; easing.type: Easing.OutCubic }
                }
                clip: true
                radius: Appearance.rounding.normal
                color: cardHov.hovered
                    ? Qt.lighter(Appearance.colors.colLayer2, 1.05)
                    : Appearance.colors.colLayer2
                Behavior on color { ColorAnimation { duration: Appearance.animDur(120) } }
                HoverHandler { id: cardHov }

                ColumnLayout {
                    id: cardCol
                    anchors {
                        left: parent.left; right: parent.right; top: parent.top
                        leftMargin: root.cardPad
                        rightMargin: root.cardPad
                        topMargin: root.cardPad
                    }
                    spacing: 10

                    // Header row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: 18
                            color: Qt.alpha(Appearance.colors.colPrimary, 0.10)
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: root._icon(card.kind)
                                iconSize: 20
                                color: Appearance.colors.colPrimary
                            }
                        }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: card.devName
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer2
                                elide: Text.ElideRight
                            }
                            RowLayout {
                                spacing: 6
                                StyledText {
                                    text: card.kind.toUpperCase()
                                    font.pixelSize: 9
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    visible: card.bat >= 0
                                    text: "·  " + card.bat + "%"
                                    font.pixelSize: 9
                                    color: card.bat <= 20
                                        ? Appearance.m3colors.m3error
                                        : Appearance.colors.colSubtext
                                }
                            }
                        }

                        // Disconnect chip
                        ChipBtn {
                            id: discBtn
                            iconText: "link_off"
                            danger: true
                            onActivated: card.modelData?.disconnect()
                        }
                        // Expand chip
                        ChipBtn {
                            id: expBtn
                            iconText: card.expanded ? "expand_less" : "expand_more"
                            onActivated: card.expanded = !card.expanded
                        }
                    }

                    // Expanded controls (lazy)
                    Loader {
                        Layout.fillWidth: true
                        active: card.expanded
                        visible: card.expanded
                        sourceComponent:
                            card.kind === "mouse"
                                ? mouseCtrls
                                : card.kind === "audio"
                                    ? audioCtrls
                                    : genericCtrls
                    }
                }

                // Per-type controls --------------------------------------
                Component {
                    id: mouseCtrls
                    ColumnLayout {
                        spacing: 10
                        property int    dpi:        1000
                        property int    smartShift: 10
                        property string ratchet:    "Ratcheted"

                        Process {
                            id: readCfg
                            stdout: StdioCollector { onStreamFinished: {
                                for (const ln of text.split("\n")) {
                                    const m = ln.match(/^([a-z-]+)\s*=\s*(.+)$/)
                                    if (!m) continue
                                    if (m[1] === "dpi")            parent.parent.dpi = parseInt(m[2]) || 1000
                                    else if (m[1] === "smart-shift")    parent.parent.smartShift = parseInt(m[2]) || 10
                                    else if (m[1] === "scroll-ratchet") parent.parent.ratchet = m[2].trim()
                                }
                            }}
                        }
                        Component.onCompleted: {
                            readCfg.command = ["bash", "-c",
                                `solaar config '${card.devName.replace(/'/g, "'\\''")}' 2>/dev/null | grep -E '^(dpi|smart-shift|scroll-ratchet)\\s*='`]
                            readCfg.running = true
                        }

                        SliderRow {
                            label: "DPI"
                            valueText: dpiSlider.value.toFixed(0)
                            StyledSlider {
                                id: dpiSlider
                                Layout.fillWidth: true
                                from: 200; to: 4000; stepSize: 50
                                value: parent.parent.dpi
                                onPressedChanged: if (!pressed)
                                    root._runShell(`solaar config '${card.devName.replace(/'/g, "'\\''")}' dpi ${Math.round(value)}`)
                            }
                        }
                        SliderRow {
                            label: "Smart Shift"
                            valueText: ssSlider.value.toFixed(0)
                            StyledSlider {
                                id: ssSlider
                                Layout.fillWidth: true
                                from: 1; to: 50; stepSize: 1
                                value: parent.parent.smartShift
                                onPressedChanged: if (!pressed)
                                    root._runShell(`solaar config '${card.devName.replace(/'/g, "'\\''")}' smart-shift ${Math.round(value)}`)
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ChipPill {
                                Layout.fillWidth: true
                                iconText: "all_inclusive"
                                label: qsTr("Free-spin")
                                onActivated:
                                    root._runShell(`solaar config '${card.devName.replace(/'/g, "'\\''")}' scroll-ratchet Free-Spinning`)
                            }
                            ChipPill {
                                iconText: "settings"
                                label: qsTr("Solaar")
                                onActivated: Quickshell.execDetached(["solaar"])
                            }
                        }
                    }
                }

                Component {
                    id: audioCtrls
                    ColumnLayout {
                        spacing: 10
                        SliderRow {
                            label: "Volume"
                            valueText: vol.value.toFixed(0) + "%"
                            StyledSlider {
                                id: vol
                                Layout.fillWidth: true
                                from: 0; to: 100; stepSize: 1
                                value: 60
                                onPressedChanged: if (!pressed) {
                                    const sink = "bluez_output." + card.addr.replace(/:/g, "_") + ".1"
                                    root._runShell(`pactl set-sink-volume '${sink}' ${Math.round(value)}% 2>/dev/null`)
                                }
                            }
                        }
                        StyledText {
                            text: qsTr("Codec switching is unavailable in the rewrite.")
                            font.pixelSize: 10
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }

                Component {
                    id: genericCtrls
                    ColumnLayout {
                        spacing: 4
                        StyledText {
                            text: qsTr("Address: ") + card.addr
                            font.pixelSize: 10
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: qsTr("No device-specific controls available.")
                            font.pixelSize: 10
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        // Empty state -------------------------------------------------------
        Item {
            visible: BluetoothStatus.connectedDevices.length === 0
            Layout.fillWidth: true
            implicitHeight: 56
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 2
                StyledText {
                    text: qsTr("No connected devices")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    Layout.alignment: Qt.AlignHCenter
                }
                StyledText {
                    text: qsTr("Pair from the system Bluetooth panel.")
                    font.pixelSize: 9
                    color: Appearance.colors.colSubtext
                    opacity: 0.8
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }

    // ── Helpers (component types) ─────────────────────────────────────────
    component ChipBtn: Rectangle {
        property string iconText: ""
        property bool   danger:   false
        signal activated()

        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 32; implicitHeight: 32
        radius: 16
        color: hov.hovered
            ? (danger ? Qt.alpha(Appearance.m3colors.m3error, 0.16)
                      : Appearance.colors.colLayer3)
            : "transparent"
        Behavior on color { ColorAnimation { duration: Appearance.animDur(120) } }
        HoverHandler { id: hov }
        TapHandler   { onTapped: parent.activated() }
        MaterialSymbol {
            anchors.centerIn: parent
            text: parent.iconText
            iconSize: 16
            color: parent.danger && hov.hovered
                ? Appearance.m3colors.m3error
                : Appearance.colors.colOnLayer2
        }
    }

    component ChipPill: Rectangle {
        property string iconText: ""
        property string label:    ""
        signal activated()

        implicitHeight: 32
        implicitWidth: row.implicitWidth + 24
        radius: height / 2
        color: hov.hovered
            ? Qt.alpha(Appearance.colors.colPrimary, 0.18)
            : Appearance.colors.colLayer3
        Behavior on color { ColorAnimation { duration: Appearance.animDur(120) } }
        HoverHandler { id: hov }
        TapHandler   { onTapped: parent.activated() }
        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 6
            MaterialSymbol {
                text: parent.parent.iconText
                iconSize: 14
                color: hov.hovered
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colOnLayer2
            }
            StyledText {
                text: parent.parent.label
                font.pixelSize: 11
                color: hov.hovered
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colOnLayer2
            }
        }
    }

    component SliderRow: ColumnLayout {
        property string label: ""
        property string valueText: ""
        Layout.fillWidth: true
        spacing: 4
        // First child: label / value row.  Subsequent children (e.g. a
        // StyledSlider passed by the caller) flow underneath.
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: parent.parent.label
                font.pixelSize: 10
                color: Appearance.colors.colSubtext
            }
            StyledText {
                text: parent.parent.valueText
                font.pixelSize: 10
                color: Appearance.colors.colOnLayer2
            }
        }
    }
}
