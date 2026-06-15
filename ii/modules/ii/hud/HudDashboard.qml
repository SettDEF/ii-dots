import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.calendar
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * HUD Dashboard tab — calendar, a clock ringed by an hourly weather
 * orbit, current conditions + condition gauges, and today's class
 * timetable. Timetable data comes from
 * ~/.config/illogical-impulse/timetable.json.
 */
Item {
    id: dash
    implicitHeight: rootCol.implicitHeight + 32

    // The HUD's first-open height is corrected by HudContent's _relayoutTick.

    // ── Time ──────────────────────────────────────────────────────────
    // Seconds precision so the clock's :SS ticks.
    SystemClock {
        id: secClock
        precision: SystemClock.Seconds
    }

    readonly property var dayKeys: ["sunday", "monday", "tuesday",
        "wednesday", "thursday", "friday", "saturday"]

    // ── Timetable ─────────────────────────────────────────────────────
    property var ttData: ({})
    property int dayOffset: 0   // day-nav: which weekday is shown

    readonly property var viewDate: {
        const d = new Date(secClock.date)
        d.setDate(d.getDate() + dash.dayOffset)
        return d
    }
    readonly property string viewDayKey: dayKeys[viewDate.getDay()]
    readonly property var viewClasses: {
        const c = ttData[viewDayKey]
        return (c && c.length) ? c : []
    }

    FileView {
        id: ttFile
        path: "/home/caesar/.config/illogical-impulse/timetable.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { dash.ttData = JSON.parse(ttFile.text()) }
            catch (e) { dash.ttData = ({}) }
        }
        onLoadFailed: dash.ttData = ({})
    }

    // Next weekday (1..7 ahead) that has classes — the "Upcoming" line.
    function upcomingText() {
        for (let i = 1; i <= 7; i++) {
            const d = new Date(secClock.date)
            d.setDate(d.getDate() + i)
            const cl = ttData[dayKeys[d.getDay()]]
            if (cl && cl.length > 0)
                return Qt.formatDate(d, "dddd, dd MMM") + qsTr(" (Upcoming)")
        }
        return qsTr("No upcoming classes")
    }

    // ── Weather helpers ───────────────────────────────────────────────
    readonly property int curTempNum: parseInt(Weather.data.temp) || 0
    readonly property int humidNum: parseInt(Weather.data.humidity) || 0

    // ════════════════════════════════════════════════════════════════
    //  Reusable pieces
    // ════════════════════════════════════════════════════════════════

    // Circular ring gauge — background ring + accent arc, big value
    // centred, icon + label beneath.
    component GaugeRing: Item {
        id: g
        property real frac: 0          // 0..1 arc fill
        property string big: ""
        property string label: ""
        property string icon: ""
        property color accent: Appearance.m3colors.m3primary
        implicitWidth: 66
        implicitHeight: 86

        Canvas {
            id: ring
            width: 54; height: 54
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            onPaint: {
                const c = getContext("2d")
                c.reset()
                const cx = width / 2, cy = height / 2, r = width / 2 - 4
                c.lineWidth = 4
                c.lineCap = "round"
                c.beginPath()
                c.arc(cx, cy, r, 0, 2 * Math.PI)
                c.strokeStyle = Qt.rgba(1, 1, 1, 0.10)
                c.stroke()
                c.beginPath()
                c.arc(cx, cy, r, -Math.PI / 2,
                      -Math.PI / 2 + Math.max(0.012, Math.min(g.frac, 1)) * 2 * Math.PI)
                c.strokeStyle = g.accent
                c.stroke()
            }
            Connections {
                target: g
                function onFracChanged() { ring.requestPaint() }
                function onAccentChanged() { ring.requestPaint() }
            }
        }
        StyledText {
            anchors.centerIn: ring
            text: g.big
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer0
        }
        RowLayout {
            anchors.top: ring.bottom
            anchors.topMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 3
            MaterialSymbol {
                text: g.icon
                iconSize: 13
                color: Appearance.colors.colSubtext
            }
            StyledText {
                text: g.label
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: Appearance.colors.colSubtext
            }
        }
    }

    // HourPill is now a standalone component (HourPill.qml).

    // ════════════════════════════════════════════════════════════════
    //  Layout
    // ════════════════════════════════════════════════════════════════
    ColumnLayout {
        id: rootCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 14

        // ── TOP: calendar · orbit · weather ────────────────────────────
        Item {
            Layout.fillWidth: true
            implicitHeight: 460

            // Calendar — left
            Rectangle {
                id: calCard
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 348
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                clip: true
                CalendarWidget {
                    anchors.centerIn: parent
                    width: parent.width - 24
                }
            }

            // Weather + gauges — right
            ColumnLayout {
                id: rightCol
                anchors { right: parent.right; top: parent.top }
                width: 312
                spacing: 4

                // Day navigator
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: 8
                    HudIconButton {
                        symbol: "chevron_left"
                        onClicked: dash.dayOffset--
                    }
                    StyledText {
                        text: Qt.formatDate(dash.viewDate, "dddd").toUpperCase()
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer0
                    }
                    HudIconButton {
                        symbol: "chevron_right"
                        onClicked: dash.dayOffset++
                    }
                }

                // Big current temperature
                StyledText {
                    Layout.alignment: Qt.AlignRight
                    Layout.topMargin: 6
                    text: dash.curTempNum + "°"
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: 76
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    Layout.alignment: Qt.AlignRight
                    text: Weather.data.desc !== "" ? Weather.data.desc : qsTr("…")
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.m3colors.m3primary
                }

                // Condition gauges
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    Layout.topMargin: 22
                    spacing: 6
                    GaugeRing {
                        icon: "air"; label: "WIND"
                        big: Math.round(Weather.data.windKmph / 3.6) + "m/s"
                        frac: Math.min(Weather.data.windKmph / 40, 1)
                    }
                    GaugeRing {
                        icon: "humidity_percentage"; label: "HUMID"
                        big: dash.humidNum + "%"
                        frac: dash.humidNum / 100
                    }
                    GaugeRing {
                        icon: "rainy"; label: "RAIN"
                        big: Weather.data.chanceOfRain + "%"
                        frac: Weather.data.chanceOfRain / 100
                    }
                    GaugeRing {
                        icon: "thermostat"; label: "FEELS"
                        big: Weather.data.feelsLikeNum + "°"
                        frac: Math.max(0, Math.min((Weather.data.feelsLikeNum + 10) / 50, 1))
                    }
                }
            }

            // Clock + weather orbit — centre
            Item {
                id: orbit
                anchors {
                    left: calCard.right; right: rightCol.left
                    top: parent.top; bottom: parent.bottom
                    leftMargin: 8; rightMargin: 8
                }
                readonly property real cx: width / 2
                readonly property real cy: height / 2
                // Wide ellipse — radii pushed out so the hourly pills
                // clear the central clock instead of overlapping it.
                readonly property real rx: Math.max(80, width / 2 - 24)
                readonly property real ry: Math.max(70, height / 2 - 52)

                // Slow ambient rotation — the hourly pills drift around
                // the fixed dashed track, one revolution every 3 min.
                property real spin: 0
                NumberAnimation on spin {
                    running: true
                    loops: Animation.Infinite
                    from: 0; to: 2 * Math.PI
                    duration: 180000
                }

                // Dashed elliptical track
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
                        function onWidthChanged() { parent.requestPaint?.() }
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

                // Hourly pills around the ellipse. The "current" pill is the one
                // whose hour is closest to wall-clock-now; computed ONCE in the
                // outer scope so each pill is O(1), not O(n).
                Repeater {
                    id: hourPills
                    model: Weather.hourly
                    readonly property int _nowH: secClock.date.getHours()
                    readonly property int nowHourIndex: {
                        const hrs = Weather.hourly
                        if (!hrs || hrs.length === 0) return -1
                        let bi = 0, bd = 99
                        for (let i = 0; i < hrs.length; i++) {
                            const d = Math.abs(hrs[i].hour - _nowH)
                            if (d < bd) { bd = d; bi = i }
                        }
                        return bi
                    }
                    delegate: HourPill {
                        required property var modelData
                        required property int index
                        readonly property int n: Weather.hourly.length
                        current: index === hourPills.nowHourIndex
                        hd: modelData
                        // Distribute around the ellipse, starting at the
                        // left and walking clockwise.
                        readonly property real ang:
                            Math.PI + (n > 0 ? index / n : 0) * 2 * Math.PI
                            + orbit.spin
                        x: orbit.cx + orbit.rx * Math.cos(ang) - implicitWidth / 2
                        y: orbit.cy + orbit.ry * Math.sin(ang) - implicitHeight / 2
                    }
                }
            }
        }

        // ── Divider ────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Appearance.colors.colLayer0Border
        }

        // ── Upcoming event row ─────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                implicitWidth: 34; implicitHeight: 34
                radius: 17
                color: Appearance.colors.colLayer2
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "calendar_month"
                    iconSize: 18
                    color: Appearance.m3colors.m3primary
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: dash.upcomingText()
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer0
            }
            Rectangle {
                id: openWebBtn
                implicitWidth: webRow.implicitWidth + 26
                implicitHeight: 34
                radius: 17
                color: webMouse.containsMouse
                    ? Appearance.colors.colLayer2
                    : "transparent"
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                RowLayout {
                    id: webRow
                    anchors.centerIn: parent
                    spacing: 6
                    StyledText {
                        text: qsTr("Open Web")
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer0
                    }
                    MaterialSymbol {
                        text: "open_in_new"
                        iconSize: 15
                        color: Appearance.colors.colOnLayer0
                    }
                }
                MouseArea {
                    id: webMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Qt.openUrlExternally(
                        dash.ttData.webUrl ?? "https://calendar.google.com")
                }
            }
        }

        // ── Today's timetable ──────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 12

            Repeater {
                model: dash.viewClasses
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: classCol.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    clip: true

                    ColumnLayout {
                        id: classCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 6
                        StyledText {
                            text: modelData.subject ?? ""
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnLayer0
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        RowLayout {
                            spacing: 5
                            MaterialSymbol {
                                text: "schedule"; iconSize: 14
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                text: (modelData.start ?? "") + "-" + (modelData.end ?? "")
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                        RowLayout {
                            spacing: 5
                            MaterialSymbol {
                                text: "location_on"; iconSize: 14
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                text: modelData.room ?? ""
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.m3colors.m3primary
                            }
                        }
                    }
                }
            }

            // Empty state when the viewed day has no classes.
            StyledText {
                visible: dash.viewClasses.length === 0
                Layout.fillWidth: true
                text: qsTr("No classes on %1").arg(
                    Qt.formatDate(dash.viewDate, "dddd"))
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }
    }

    // Small round icon button used by the day navigator.
    component HudIconButton: Rectangle {
        id: btn
        property string symbol: ""
        signal clicked()
        implicitWidth: 26; implicitHeight: 26
        radius: 13
        color: ibMouse.containsMouse
            ? Appearance.colors.colLayer2
            : "transparent"
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        MaterialSymbol {
            anchors.centerIn: parent
            text: btn.symbol
            iconSize: 16
            color: Appearance.colors.colOnLayer0
        }
        MouseArea {
            id: ibMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
