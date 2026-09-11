import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Upcoming — what leaves the account next, and the standing orders behind it.
StyledFlickable {
    id: root
    contentHeight: col.implicitHeight
    clip: true

    ColumnLayout {
        id: col
        width: root.width
        spacing: 10

        StyledText {
            Layout.fillWidth: true
            visible: Finance.upcoming.length === 0
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            topPadding: 24
            text: qsTr("Nothing scheduled.\nRecurring payments appear here once they repeat three times.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        // ── Next 30 days ─────────────────────────────────────────────────
        StyledText {
            text: qsTr("Next 30 days · %1").arg(Finance.money(-Finance.committedSoon))
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Bold
            font.letterSpacing: 1.2
            color: Appearance.colors.colPrimary
            visible: Finance.upcoming.length > 0
        }

        Repeater {
            model: Finance.upcoming
            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 48
                radius: Appearance.rounding.small
                // Anything inside a week gets the warmer surface — it is the
                // difference between "coming up" and "about to happen".
                color: modelData.days_until <= 7
                    ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2

                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    spacing: 10

                    BrandIcon {
                        names: MerchantIcons.iconNamesFor(modelData.counterparty)
                        symbol: MerchantIcons.symbolFor(modelData.counterparty, modelData.category)
                        size: 22
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: modelData.counterparty
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            text: {
                                if (modelData.days_until <= 0) return qsTr("due today · %1").arg(modelData.category)
                                if (modelData.days_until === 1) return qsTr("tomorrow · %1").arg(modelData.category)
                                return qsTr("in %1 days · %2").arg(modelData.days_until).arg(modelData.category)
                            }
                        }
                    }

                    StyledText {
                        text: Math.abs(modelData.amount).toFixed(2)
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.numbers
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        // ── The standing orders themselves ───────────────────────────────
        StyledText {
            Layout.topMargin: 6
            text: qsTr("Recurring · %1/month").arg(Finance.recurringMonthly.toFixed(2))
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Bold
            font.letterSpacing: 1.2
            color: Appearance.colors.colPrimary
            visible: Finance.recurring.length > 0
        }
        Repeater {
            model: Finance.recurring
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                BrandIcon {
                    names: MerchantIcons.iconNamesFor(modelData.counterparty)
                    symbol: MerchantIcons.symbolFor(modelData.counterparty, modelData.category)
                    size: 20
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: modelData.counterparty
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    StyledText {
                        text: qsTr("every ~%1 days · seen %2×").arg(modelData.every_days).arg(modelData.occurrences)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
                StyledText {
                    text: Math.abs(modelData.amount).toFixed(2)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.numbers
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
    }
}
