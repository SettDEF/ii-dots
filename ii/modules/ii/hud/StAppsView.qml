import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Screen Time · Apps — every tracked app over the last 7 days, sorted
 * by time. Tapping a row opens its per-app detail.
 */
Item {
    id: root
    signal appSelected(string id)
    implicitHeight: col.implicitHeight + 28

    readonly property var apps: {
        AppUsage.revision
        const agg = ({})
        for (let i = 0; i < 7; i++) {
            const d = new Date()
            d.setDate(d.getDate() - i)
            const a = AppUsage.dayData(Qt.formatDate(d, "yyyy-MM-dd")).apps
            for (const k in a) agg[k] = (agg[k] || 0) + a[k]
        }
        return Object.keys(agg).map(k => ({ app: k, seconds: agg[k] }))
            .sort((x, y) => y.seconds - x.seconds)
    }
    readonly property int maxApp: apps.length > 0 ? apps[0].seconds : 1
    readonly property color accent: Appearance.m3colors.m3primary

    // 7-day total across every app.
    readonly property int total: {
        let s = 0
        for (const a of root.apps) s += a.seconds
        return s
    }

    // ── A labelled stat card ──────────────────────────────────────
    component StatCard: Rectangle {
        id: sc
        property string topLabel: ""
        property string bigText: ""
        implicitHeight: 74
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 1
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: sc.topLabel
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: sc.bigText
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer0
            }
        }
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 10

        StyledText {
            text: "All apps · last 7 days"
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.large
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer0
        }

        // ── Summary stats ─────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            StatCard {
                Layout.fillWidth: true
                topLabel: "Total"
                bigText: AppUsage.pretty(root.total)
            }
            StatCard {
                Layout.fillWidth: true
                topLabel: "Daily average"
                bigText: AppUsage.pretty(AppUsage.weekAverage)
            }
            StatCard {
                Layout.fillWidth: true
                topLabel: "Apps"
                bigText: root.apps.length + ""
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: appCol.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            ColumnLayout {
                id: appCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 4

                StyledText {
                    visible: root.apps.length === 0
                    text: "No usage tracked yet — give it a while."
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.small
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
}
