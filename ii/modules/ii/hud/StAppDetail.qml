import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Screen Time · per-app detail (reference image 132) — stat cards,
 * weekly bar chart, month heatmap and a 24-hour daily-usage chart,
 * all scoped to one app. `appId` set by the caller; `closed()` goes
 * back to the list.
 */
Item {
    id: root
    property string appId: ""
    signal closed()
    implicitHeight: col.implicitHeight + 28

    property int dayOffset: 0
    readonly property var viewDate: {
        const d = new Date()
        d.setDate(d.getDate() + dayOffset)
        return d
    }
    readonly property string dateKey: Qt.formatDate(viewDate, "yyyy-MM-dd")
    readonly property color accent: Appearance.m3colors.m3primary

    function appSecs(dateStr) {
        AppUsage.revision
        return AppUsage.dayData(dateStr).apps[root.appId] || 0
    }
    readonly property int daySecs: appSecs(dateKey)
    readonly property int yesterdaySecs: {
        const d = new Date(viewDate)
        d.setDate(d.getDate() - 1)
        return appSecs(Qt.formatDate(d, "yyyy-MM-dd"))
    }
    readonly property int deltaSecs: daySecs - yesterdaySecs
    readonly property int avgSecs: {
        AppUsage.revision
        let s = 0
        for (let i = 0; i < 7; i++) {
            const d = new Date()
            d.setDate(d.getDate() - i)
            s += appSecs(Qt.formatDate(d, "yyyy-MM-dd"))
        }
        return Math.round(s / 7)
    }
    readonly property var hours24: {
        AppUsage.revision
        return AppUsage.dayData(dateKey).appHours[root.appId] || new Array(24).fill(0)
    }

    component Card: Rectangle {
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
    }
    component StatCard: Card {
        property string topLabel: ""
        property string bigText: ""
        property string subLabel: ""
        property color bigColor: Appearance.colors.colOnLayer0
        implicitHeight: 78
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 1
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: text.length > 0; text: parent.parent.topLabel
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: parent.parent.bigText
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.Bold
                color: parent.parent.bigColor
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: text.length > 0; text: parent.parent.subLabel
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 12

        // ── Header ────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            HudIconButton { symbol: "arrow_back"; onClicked: root.closed() }
            HudIconButton { symbol: "chevron_left"; onClicked: root.dayOffset-- }
            Item { Layout.fillWidth: true
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    Image {
                        width: 22; height: 22
                        sourceSize.width: 44; sourceSize.height: 44
                        smooth: true
                        source: Quickshell.iconPath(root.appId, "application-x-executable")
                    }
                    StyledText {
                        text: root.appId + "  ·  "
                            + (root.dayOffset === 0 ? "Today"
                               : Qt.formatDate(root.viewDate, "MMM d"))
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }
            HudIconButton {
                symbol: "chevron_right"
                enabled: root.dayOffset < 0
                onClicked: if (root.dayOffset < 0) root.dayOffset++
            }
        }

        // ── Stat cards ────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            StatCard {
                Layout.fillWidth: true
                topLabel: "Daily average"
                bigText: AppUsage.pretty(root.avgSecs)
                subLabel: "last 7 days"
            }
            StatCard {
                Layout.fillWidth: true
                Layout.preferredWidth: 2
                bigText: AppUsage.pretty(root.daySecs)
                bigColor: root.accent
            }
            StatCard {
                Layout.fillWidth: true
                bigText: (root.deltaSecs >= 0 ? "↑ " : "↓ ")
                    + AppUsage.pretty(Math.abs(root.deltaSecs))
                bigColor: root.deltaSecs > 0
                    ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                subLabel: "vs yesterday"
            }
        }

        // ── Weekly bars + month heatmap ───────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Card {
                Layout.fillWidth: true
                implicitHeight: 150
                ColumnLayout {
                    anchors { fill: parent; margins: 12 }
                    spacing: 6
                    StyledText {
                        text: "This week"
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    UsageBarChart {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        accent: root.accent
                        bars: {
                            AppUsage.revision
                            return AppUsage.last7Days().map(e => ({
                                label: e.label,
                                value: root.appSecs(e.date),
                                highlight: e.date === root.dateKey,
                            }))
                        }
                    }
                }
            }
            Card {
                implicitWidth: detHeat.implicitWidth + 24
                implicitHeight: 150
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Qt.formatDate(root.viewDate, "MMMM")
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    UsageHeatmap {
                        id: detHeat
                        accent: root.accent
                        days: {
                            AppUsage.revision
                            return AppUsage.monthDays(root.viewDate.getFullYear(),
                                                      root.viewDate.getMonth())
                                .map(e => ({ date: e.date, day: e.day,
                                             total: root.appSecs(e.date) }))
                        }
                        firstWeekday: {
                            const d = new Date(root.viewDate.getFullYear(),
                                               root.viewDate.getMonth(), 1)
                            return (d.getDay() + 6) % 7
                        }
                    }
                }
            }
        }

        // ── 24-hour daily usage ───────────────────────────────────
        Card {
            Layout.fillWidth: true
            implicitHeight: 160
            ColumnLayout {
                anchors { fill: parent; margins: 12 }
                spacing: 6
                StyledText {
                    text: "Daily usage"
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                UsageBarChart {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    accent: root.accent
                    bars: {
                        const out = []
                        for (let h = 0; h < 24; h++) {
                            const tick = (h % 6 === 0) || h === 23
                            out.push({
                                label: tick ? (h < 10 ? "0" + h : "" + h) + ":00" : "",
                                value: root.hours24[h],
                                highlight: false,
                            })
                        }
                        return out
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
