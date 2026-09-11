import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// Overview — what you have, what is safe to spend, and where it went.
StyledFlickable {
    id: root
    contentHeight: col.implicitHeight
    clip: true

    ColumnLayout {
        id: col
        width: root.width
        spacing: 10

        // ── Balance ──────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: balCol.implicitHeight + 24
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2

            ColumnLayout {
                id: balCol
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 16 }
                spacing: 2

                StyledText {
                    text: qsTr("Total balance")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    text: Finance.money(Finance.totalBalance)
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.family: Appearance.font.family.numbers
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 6
                    Repeater {
                        model: Finance.accounts
                        delegate: Rectangle {
                            required property var modelData
                            implicitHeight: 24
                            implicitWidth: acctRow.implicitWidth + 16
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colLayer1
                            RowLayout {
                                id: acctRow
                                anchors.centerIn: parent
                                spacing: 6
                                StyledText {
                                    text: `${modelData.name} ·${modelData.iban_tail}`
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    text: modelData.balance.toFixed(2)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.family: Appearance.font.family.numbers
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Safe to spend ────────────────────────────────────────────────
        // The number people actually want. A balance is misleading while rent
        // is still sitting in it, so this is balance minus everything already
        // committed in the next 30 days.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: safeCol.implicitHeight + 22
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2

            ColumnLayout {
                id: safeCol
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 16 }
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialSymbol {
                        text: "savings"
                        iconSize: 17
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: qsTr("Safe to spend")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                        Layout.fillWidth: true
                    }
                    StyledText {
                        text: Finance.money(Finance.safeToSpend)
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.numbers
                        font.weight: Font.DemiBold
                        color: Finance.safeToSpend >= 0
                            ? Appearance.colors.colOnLayer1 : Appearance.m3colors.m3error
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    text: qsTr("after %1 committed in the next 30 days")
                        .arg(Finance.money(Finance.committedSoon))
                }

                // Proportion of the balance already spoken for.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    implicitHeight: 6
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer1
                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: parent.width * Math.max(0, Math.min(1, Finance.committedFraction))
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimary
                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }

        // ── Month tiles ──────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: [
                    { k: qsTr("Spent"),  v: Finance.spentThisMonth,  kind: "down" },
                    { k: qsTr("Income"), v: Finance.incomeThisMonth, kind: "up" },
                    { k: qsTr("Net"),    v: Finance.incomeThisMonth - Finance.spentThisMonth, kind: "net" },
                ]
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 58
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.k
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Math.abs(modelData.v).toFixed(0)
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.family: Appearance.font.family.numbers
                            font.weight: Font.DemiBold
                            color: modelData.kind === "down" ? Appearance.m3colors.m3error
                                : modelData.kind === "up" ? Appearance.colors.colPrimary
                                : (modelData.v >= 0 ? Appearance.colors.colPrimary : Appearance.m3colors.m3error)
                        }
                    }
                }
            }
        }

        // ── vs last month ────────────────────────────────────────────────
        // Only shown once there IS a previous month to compare against —
        // "+100% vs last month" on a fresh link is noise, not insight.
        RowLayout {
            Layout.fillWidth: true
            visible: Finance.prevMonthSpent > 0
            spacing: 6
            MaterialSymbol {
                text: Finance.spendDelta > 0 ? "trending_up" : "trending_down"
                iconSize: 16
                color: Finance.spendDelta > 0 ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
            }
            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Finance.spendDelta > 0
                    ? qsTr("%1% more than last month").arg(Math.abs(Finance.spendDelta).toFixed(0))
                    : qsTr("%1% less than last month").arg(Math.abs(Finance.spendDelta).toFixed(0))
            }
            StyledText {
                text: Finance.prevMonthSpent.toFixed(0)
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: Appearance.font.family.numbers
                color: Appearance.colors.colSubtext
            }
        }

        // ── Categories ───────────────────────────────────────────────────
        StyledText {
            Layout.topMargin: 4
            text: qsTr("This month by category")
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Bold
            font.letterSpacing: 1.2
            color: Appearance.colors.colPrimary
            visible: catRepeater.count > 0
        }
        Repeater {
            id: catRepeater
            model: Finance.categoriesSorted
            delegate: Item {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 30
                readonly property real frac: Finance.spentThisMonth > 0
                    ? modelData.value / Finance.spentThisMonth : 0

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                }
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: Math.max(parent.width * parent.parent.frac, 3)
                    radius: Appearance.rounding.small
                    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.72)
                    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                }
                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    spacing: 8
                    MaterialSymbol {
                        text: MerchantIcons.categorySymbols[modelData.name] ?? "receipt"
                        iconSize: 15
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: modelData.name
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                        Layout.fillWidth: true
                    }
                    StyledText {
                        text: modelData.value.toFixed(2)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.numbers
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }
}
