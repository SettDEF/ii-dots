import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Screen Time · Week — a Mon-Sun timeline (each day a 00:00-23:00
 * strip shaded by usage), a Daily-average and Peak-hours card, and
 * the week's per-app usage list (reference image 134).
 */
Item {
    id: root
    signal appSelected(string id)
    implicitHeight: col.implicitHeight + 28

    property int weekOffset: 0
    readonly property var weekStart: {
        const d = new Date()
        const dow = (d.getDay() + 6) % 7          // Mon = 0
        d.setDate(d.getDate() - dow + weekOffset * 7)
        return d
    }
    readonly property var weekDays: {
        AppUsage.revision
        const out = []
        for (let i = 0; i < 7; i++) {
            const d = new Date(weekStart)
            d.setDate(d.getDate() + i)
            const key = Qt.formatDate(d, "yyyy-MM-dd")
            out.push({ date: key, label: Qt.formatDate(d, "ddd"),
                       info: AppUsage.dayData(key) })
        }
        return out
    }
    readonly property int weekAvg: {
        let s = 0
        for (const d of weekDays) s += d.info.total
        return Math.round(s / 7)
    }
    readonly property real maxHour: {
        let m = 1
        for (const d of weekDays)
            for (const h of d.info.hours) if (h > m) m = h
        return m
    }
    readonly property int peakHour: {
        const sums = new Array(24).fill(0)
        for (const d of weekDays)
            for (let h = 0; h < 24; h++) sums[h] += d.info.hours[h]
        let bi = 0, bm = -1
        for (let h = 0; h < 24; h++) if (sums[h] > bm) { bm = sums[h]; bi = h }
        return bi
    }
    readonly property var weekApps: {
        AppUsage.revision
        const agg = ({})
        for (const d of weekDays) {
            const a = d.info.apps
            for (const k in a) agg[k] = (agg[k] || 0) + a[k]
        }
        return Object.keys(agg).map(k => ({ app: k, seconds: agg[k] }))
            .sort((x, y) => y.seconds - x.seconds)
    }
    readonly property int maxApp: weekApps.length > 0 ? weekApps[0].seconds : 1
    readonly property color accent: Appearance.m3colors.m3primary

    function hh(h) { return (h < 10 ? "0" + h : "" + h) + ":00" }

    component Card: Rectangle {
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 12

        // ── Header ────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            HudIconButton { symbol: "chevron_left"; onClicked: root.weekOffset-- }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: {
                    const e = new Date(root.weekStart)
                    e.setDate(e.getDate() + 6)
                    return Qt.formatDate(root.weekStart, "MMM d") + " - "
                         + Qt.formatDate(e, "MMM d")
                }
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer0
            }
            HudIconButton {
                symbol: "chevron_right"
                enabled: root.weekOffset < 0
                onClicked: if (root.weekOffset < 0) root.weekOffset++
            }
        }

        // ── Timeline + side cards ─────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Card {
                Layout.fillWidth: true
                Layout.preferredHeight: 188
                implicitHeight: 188
                ColumnLayout {
                    id: tl
                    anchors { fill: parent; margins: 12 }
                    spacing: 5
                    Repeater {
                        model: root.weekDays
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 8
                            StyledText {
                                Layout.preferredWidth: 34
                                text: modelData.label
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 1
                                Repeater {
                                    model: 24
                                    delegate: Rectangle {
                                        required property int index
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 2
                                        readonly property real v: modelData.info.hours[index] / root.maxHour
                                        color: modelData.info.hours[index] <= 0
                                            ? Qt.alpha(Appearance.colors.colOnLayer0, 0.06)
                                            : Qt.alpha(root.accent, 0.25 + 0.75 * Math.min(v, 1))
                                    }
                                }
                            }
                        }
                    }
                    // hour ticks
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 42
                        StyledText {
                            text: "00:00"; Layout.fillWidth: true
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: "12:00"; Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: "23:00"
                            horizontalAlignment: Text.AlignRight
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.preferredWidth: 150
                Layout.maximumWidth: 150
                Layout.alignment: Qt.AlignTop
                spacing: 10
                Card {
                    Layout.fillWidth: true
                    implicitHeight: 89
                    Layout.preferredHeight: 89
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 1
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Daily average"
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: AppUsage.pretty(root.weekAvg)
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                }
                Card {
                    Layout.fillWidth: true
                    implicitHeight: 89
                    Layout.preferredHeight: 89
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 1
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Peak hours"
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.hh(root.peakHour) + " - " + root.hh((root.peakHour + 1) % 24)
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: root.accent
                        }
                    }
                }
            }
        }

        // ── App list ──────────────────────────────────────────────
        Card {
            Layout.fillWidth: true
            implicitHeight: appCol.implicitHeight + 20
            ColumnLayout {
                id: appCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 4
                StyledText {
                    text: root.weekApps.length > 0 ? "Apps this week" : "No usage this week"
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                Repeater {
                    model: root.weekApps
                    delegate: UsageAppRow {
                        required property var modelData
                        Layout.fillWidth: true
                        appId: modelData.app
                        seconds: modelData.seconds
                        maxSeconds: root.maxApp
                        accent: root.accent
                        onClicked: root.appSelected(modelData.app)
                    }
                }
            }
        }
    }

    component HudIconButton: Rectangle {
        property string symbol: ""
        signal clicked()
        implicitWidth: 28; implicitHeight: 28
        radius: 14
        color: ibMouse.containsMouse && enabled
            ? Appearance.colors.colLayer2 : "transparent"
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        opacity: enabled ? 1 : 0.35
        MaterialSymbol {
            anchors.centerIn: parent
            text: parent.symbol
            iconSize: 17
            color: Appearance.colors.colOnLayer0
        }
        MouseArea {
            id: ibMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (parent.enabled) parent.clicked()
        }
    }
}
