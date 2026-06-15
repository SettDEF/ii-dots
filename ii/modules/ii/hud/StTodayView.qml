import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Screen Time · Today — stat cards, weekly bar chart, month heatmap,
 * and the per-app usage list (reference image 133). Day-nav arrows
 * step `dayOffset`. Tapping an app row emits appSelected(id).
 */
Item {
    id: root
    signal appSelected(string id)
    implicitHeight: col.implicitHeight + 28

    property int dayOffset: 0
    readonly property var viewDate: {
        const d = new Date()
        d.setDate(d.getDate() + dayOffset)
        return d
    }
    readonly property string dateKey: Qt.formatDate(viewDate, "yyyy-MM-dd")
    readonly property var dayInfo: { AppUsage.revision; return AppUsage.dayData(dateKey) }
    readonly property var apps: { AppUsage.revision; return AppUsage.appsForDay(dateKey) }
    readonly property int maxApp: apps.length > 0 ? apps[0].seconds : 1
    readonly property int yesterdaySecs: {
        AppUsage.revision
        const d = new Date(viewDate)
        d.setDate(d.getDate() - 1)
        return AppUsage.dayData(Qt.formatDate(d, "yyyy-MM-dd")).total
    }
    readonly property int deltaSecs: dayInfo.total - yesterdaySecs

    readonly property color accent: Appearance.m3colors.m3primary

    // ── A plain card surface ──────────────────────────────────────
    component Card: Rectangle {
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
    }

    // ── A labelled stat card ──────────────────────────────────────
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
                visible: text.length > 0
                text: parent.parent.topLabel
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
                visible: text.length > 0
                text: parent.parent.subLabel
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
            HudIconButton { symbol: "chevron_left"; onClicked: root.dayOffset-- }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.dayOffset === 0 ? "Today"
                    : Qt.formatDate(root.viewDate, "dddd, MMM d")
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer0
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
                bigText: AppUsage.pretty(AppUsage.weekAverage)
                subLabel: "last 7 days"
            }
            StatCard {
                Layout.fillWidth: true
                Layout.preferredWidth: 2
                bigText: AppUsage.pretty(root.dayInfo.total)
                bigColor: root.accent
            }
            StatCard {
                Layout.fillWidth: true
                bigText: (root.deltaSecs >= 0 ? "↑ " : "↓ ")
                    + AppUsage.pretty(Math.abs(root.deltaSecs))
                bigColor: root.deltaSecs > 0
                    ? Appearance.m3colors.m3error
                    : Appearance.colors.colSubtext
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
                                value: e.total,
                                highlight: e.date === root.dateKey,
                            }))
                        }
                    }
                }
            }

            Card {
                implicitWidth: monthHeat.implicitWidth + 24
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
                        id: monthHeat
                        accent: root.accent
                        days: {
                            AppUsage.revision
                            return AppUsage.monthDays(root.viewDate.getFullYear(),
                                                      root.viewDate.getMonth())
                        }
                        firstWeekday: {
                            const d = new Date(root.viewDate.getFullYear(),
                                               root.viewDate.getMonth(), 1)
                            return (d.getDay() + 6) % 7   // Mon = 0
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
                    text: root.apps.length > 0 ? "Apps" : "No usage tracked yet"
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                Repeater {
                    model: root.apps
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

    // Small round nav button.
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
