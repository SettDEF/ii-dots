import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * Connection and hardware facts for the MX Master.
 *
 * Shared by the Pointer panel and the Bluetooth device card. Both were showing
 * a subset of this, and the Bluetooth card was getting it by shelling out to
 * `solaar config` on every expand — a multi-second HID++ round-trip over the
 * very link that is already the bottleneck. LogiTune has the same values
 * instantly from /dev/shm.
 *
 * The layout leads with the three numbers that decide how the pointer feels —
 * DPI, link rate, battery — because a flat label/value list buries the one
 * that is wrong. Link rate comes from the engine, which is the only thing that
 * sees every report; battery is here because below ~20% Logitech mice throttle
 * transmit power and report rate, which reads as stutter long before any
 * battery warning appears.
 */
ColumnLayout {
    id: info

    property string address: ""
    property string transport: "Bluetooth"
    /// Extra rows appended below, as [{label, value, icon}].
    property var extraRows: []

    spacing: 10

    readonly property bool lowBattery: LogiTune.available && LogiTune.battery > 0
                                       && LogiTune.battery <= 20
    readonly property bool slowLink: PointerLink.available && PointerLink.hz > 0
                                     && PointerLink.hz < 150

    // ── Headline stats ──────────────────────────────────────────────────
    component Tile: Rectangle {
        id: tile
        property string label: ""
        property string value: ""
        property string icon: ""
        property bool warn: false
        // `tile.` throughout rather than parent-chains: the chain depends on
        // the layout nesting, so adding a wrapper silently rebinds it to the
        // wrong object and qmllint cannot see the break.
        readonly property color fg: tile.warn ? Appearance.m3colors.m3error
                                              : Appearance.colors.colSubtext

        Layout.fillWidth: true
        implicitHeight: 58
        radius: Appearance.rounding.small
        color: tile.warn ? ColorUtils.transparentize(Appearance.m3colors.m3error, 0.88)
                         : Appearance.colors.colLayer2

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 1
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4
                MaterialSymbol {
                    text: tile.icon
                    iconSize: 13
                    color: tile.fg
                }
                StyledText {
                    text: tile.label
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: tile.fg
                }
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: tile.value
                font.pixelSize: Appearance.font.pixelSize.normal
                font.family: Appearance.font.family.numbers
                font.weight: Font.DemiBold
                color: tile.warn ? Appearance.m3colors.m3error
                                 : Appearance.colors.colOnLayer2
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Tile {
            label: qsTr("DPI")
            icon: "mouse"
            value: LogiTune.available && LogiTune.dpi > 0 ? `${LogiTune.dpi}` : "—"
        }
        Tile {
            label: qsTr("Link")
            icon: "network_check"
            warn: info.slowLink
            value: PointerLink.available && PointerLink.hz > 0
                ? `${PointerLink.hz} Hz` : "—"
        }
        Tile {
            label: qsTr("Battery")
            icon: info.lowBattery ? "battery_alert" : "battery_full"
            warn: info.lowBattery
            value: LogiTune.available && LogiTune.battery > 0
                ? `${LogiTune.battery}%` : "—"
        }
    }

    // ── Problems worth stating plainly ──────────────────────────────────
    component Note: RowLayout {
        id: note
        property string text_: ""
        property string icon: "info"
        Layout.fillWidth: true
        spacing: 6
        MaterialSymbol {
            Layout.alignment: Qt.AlignTop
            text: note.icon
            iconSize: 14
            color: Appearance.m3colors.m3error
        }
        StyledText {
            Layout.fillWidth: true
            text: note.text_
            wrapMode: Text.WordWrap
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.m3colors.m3error
        }
    }

    Note {
        visible: info.slowLink
        icon: "speed"
        text_: qsTr("%1 Hz is low. The pointer holds still between reports and then "
                  + "jumps, which no curve setting can smooth away.").arg(PointerLink.hz)
    }
    Note {
        visible: PointerLink.bursty
        icon: "stacked_line_chart"
        text_: qsTr("%1% of reports arrive in bursts — the link is delivering unevenly.")
            .arg(Math.round(PointerLink.batchedPct))
    }
    Note {
        visible: info.lowBattery
        icon: "battery_alert"
        text_: qsTr("Below 20%%, Logitech mice cut transmit power and report rate. "
                  + "Charge before blaming the settings.")
    }

    // ── Detail ──────────────────────────────────────────────────────────
    component Row_: RowLayout {
        id: r
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: 8
        StyledText {
            Layout.fillWidth: true
            text: r.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        StyledText {
            text: r.value
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.family: Appearance.font.family.numbers
            color: Appearance.colors.colOnLayer1
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Row_ {
            label: qsTr("Transport")
            value: info.transport
        }
        Row_ {
            visible: info.address.length > 0
            label: qsTr("Address")
            value: info.address
        }
        Row_ {
            label: qsTr("Smart shift")
            value: !LogiTune.available ? "—"
                : (LogiTune.smartShift ? qsTr("on, at %1").arg(LogiTune.smartShiftThreshold)
                                       : qsTr("off"))
        }
        Row_ {
            label: qsTr("Hi-res scroll")
            value: !LogiTune.available ? "—"
                : (LogiTune.hiResScroll ? qsTr("on") : qsTr("off"))
        }
        Row_ {
            label: qsTr("Engine")
            value: PointerLink.available ? qsTr("running") : qsTr("not running")
        }

        Repeater {
            model: info.extraRows
            delegate: Row_ {
                required property var modelData
                label: modelData.label ?? ""
                value: modelData.value ?? ""
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: !LogiTune.available
        text: qsTr("logitune-cli is not publishing — hardware values unavailable.")
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colSubtext
    }
}
