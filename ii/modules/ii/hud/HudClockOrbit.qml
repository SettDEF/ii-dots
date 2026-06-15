// Centre orbit element from the HUD Dashboard, extracted so it can be
// reused by the ConnectivityPopup as the middle column. Renders a dashed
// elliptical track with the hourly weather pills slowly drifting around a
// fixed centred clock.
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: orbit

    // HourPill is a standalone component (HourPill.qml in this directory).

    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real rx: Math.max(80, width / 2 - 24)
    readonly property real ry: Math.max(70, height / 2 - 52)

    SystemClock {
        id: secClock
        precision: SystemClock.Seconds
    }

    // Slow ambient rotation — one revolution every 3 min.
    property real spin: 0
    NumberAnimation on spin {
        running: true
        loops: Animation.Infinite
        from: 0; to: 2 * Math.PI
        duration: 180000
    }

    Canvas {
        anchors.fill: parent
        onPaint: {
            const c = getContext("2d")
            c.reset()
            c.setLineDash([3, 6])
            c.lineWidth = 1.5
            c.strokeStyle = Qt.alpha(Appearance.colors.colOnLayer0, 0.28)
            c.beginPath()
            c.ellipse(orbit.cx - orbit.rx, orbit.cy - orbit.ry,
                      orbit.rx * 2, orbit.ry * 2)
            c.stroke()
        }
        Component.onCompleted: requestPaint()
        Connections {
            target: orbit
            function onWidthChanged()  { parent.requestPaint?.() }
            function onHeightChanged() { parent.requestPaint?.() }
        }
    }

    // Clock
    Column {
        anchors.centerIn: parent
        spacing: 2
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4
            StyledText {
                text: Qt.formatTime(secClock.date, "HH:mm")
                font.family: Appearance.font.family.monospace
                font.pixelSize: 76
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                text: ":" + Qt.formatTime(secClock.date, "ss")
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.Bold
                color: Appearance.colors.colSubtext
            }
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(secClock.date, "dddd, MMMM d")
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colSubtext
        }
    }

    // Hourly pills around the ellipse
    Repeater {
        model: Weather.hourly
        delegate: HourPill {
            required property var modelData
            required property int index
            readonly property int n: Weather.hourly.length
            current: {
                const nowH = secClock.date.getHours()
                let bi = 0, bd = 99
                for (let i = 0; i < Weather.hourly.length; i++) {
                    const d = Math.abs(Weather.hourly[i].hour - nowH)
                    if (d < bd) { bd = d; bi = i }
                }
                return index === bi
            }
            hd: modelData
            readonly property real ang:
                Math.PI + (n > 0 ? index / n : 0) * 2 * Math.PI + orbit.spin
            x: orbit.cx + orbit.rx * Math.cos(ang) - implicitWidth / 2
            y: orbit.cy + orbit.ry * Math.sin(ang) - implicitHeight / 2
        }
    }
}
