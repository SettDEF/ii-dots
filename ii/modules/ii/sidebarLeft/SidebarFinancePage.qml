import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarLeft.finance
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

// Finance page shell — empty state, sub-tabs, and the footer that reports how
// fresh the data is.
//
// The tabs use SecondaryTabBar + SwipeView, the same pairing the pomodoro
// widget uses for its Pomodoro/Stopwatch split, so nested tabs look the same
// wherever they appear.
//
// Everything shown is pre-computed by scripts/finance/. This file arranges;
// it does not derive.
Item {
    id: root
    anchors.fill: parent

    readonly property real pad: 12

    property bool setupOpen: false

    readonly property var tabButtonList: [
        { name: qsTr("Overview"), icon: "account_balance" },
        { name: qsTr("Upcoming"), icon: "event_upcoming" },
        { name: qsTr("Activity"), icon: "receipt_long" },
    ]

    // ── Empty state ──────────────────────────────────────────────────────
    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - root.pad * 4
        spacing: 8
        visible: !Finance.loaded || Finance.accounts.length === 0

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: "account_balance"
            iconSize: 48
            color: Appearance.colors.colSubtext
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("No bank linked yet")
            font.pixelSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            text: Finance.error.length > 0 ? Finance.error
                : qsTr("Link a bank to see balances, upcoming payments and activity.")
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8
            PrimaryActionButton {
                buttonText: qsTr("Set up")
                onClicked: root.setupOpen = true
            }
            RippleButtonWithIcon {
                materialIcon: "science"
                buttonText: qsTr("Preview")
                // Sample data in the real schema, so the page can be judged
                // before a bank is involved.
                onClicked: Quickshell.execDetached(
                    [`${Directories.scriptPath}/finance/finance-sync`, "demo"])
                StyledToolTip { text: qsTr("Fill with sample data") }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: 10
        visible: Finance.loaded && Finance.accounts.length > 0

        SecondaryTabBar {
            id: tabBar
            Layout.fillWidth: true
            currentIndex: swipeView.currentIndex

            Repeater {
                model: root.tabButtonList
                delegate: SecondaryTabButton {
                    required property var modelData
                    buttonText: modelData.name
                    buttonIcon: modelData.icon
                }
            }
        }

        SwipeView {
            id: swipeView
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex
            clip: true

            FinanceOverview {}
            FinanceUpcoming {}
            FinanceActivity {}
        }

        // ── Footer: freshness, consent, manual refresh ───────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                // Consent expiry is what silently kills this, so it gets the
                // loud colour well before it happens.
                text: Finance.error.length > 0 ? "error"
                    : Finance.consentExpiringSoon ? "warning" : "schedule"
                iconSize: 15
                color: Finance.error.length > 0 || Finance.consentExpiringSoon
                    ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Finance.error.length > 0 || Finance.consentExpiringSoon
                    ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                text: {
                    if (Finance.error.length > 0) return Finance.error
                    if (Finance.consentExpiringSoon)
                        return qsTr("Bank consent expires in %1 days — re-link soon").arg(Finance.consentDaysLeft)
                    if (Finance.generatedAt.length === 0) return ""
                    const d = new Date(Finance.generatedAt)
                    return isNaN(d.getTime()) ? "" : qsTr("Updated %1").arg(d.toLocaleString(Qt.locale(), Locale.ShortFormat))
                }
            }
            RippleButton {
                implicitHeight: 26
                buttonRadius: Appearance.rounding.full
                enabled: !Finance.syncing
                onClicked: Finance.refresh()
                contentItem: RowLayout {
                    spacing: 4
                    MaterialSymbol {
                        text: "refresh"
                        iconSize: 14
                        color: Appearance.colors.colOnLayer1
                        RotationAnimator on rotation {
                            running: Finance.syncing
                            loops: Animation.Infinite
                            from: 0; to: 360; duration: 900
                        }
                    }
                    StyledText {
                        text: Finance.syncing ? qsTr("Syncing") : qsTr("Refresh")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }

            // Setup is reachable with data on screen, not only from the empty
            // state: PSD2 consent expires every 90 days, so re-linking is a
            // recurring errand, not a one-off.
            RippleButton {
                implicitHeight: 26
                onClicked: root.setupOpen = true
                contentItem: RowLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol {
                        text: "link"
                        iconSize: 14
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: Finance.accounts.length > 0 ? qsTr("Re-link") : qsTr("Link")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                    }
                }
                StyledToolTip { text: qsTr("Link a bank, or renew expiring consent") }
            }
        }
    }

    // ── Setup wizard ─────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        visible: root.setupOpen
        color: Appearance.colors.colLayer0
        // Swallows clicks so the page behind cannot be interacted with while
        // the wizard is up.
        MouseArea { anchors.fill: parent }

        StyledFlickable {
            anchors { fill: parent; margins: root.pad }
            contentHeight: wizard.implicitHeight
            clip: true

            ColumnLayout {
                id: wizard
                width: parent.width
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Link a bank")
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer0
                    }
                    RippleButton {
                        implicitWidth: 30
                        implicitHeight: 30
                        onClicked: root.setupOpen = false
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 18
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                }

                FinanceSetup {
                    Layout.fillWidth: true
                    onFinished: root.setupOpen = false
                }
            }
        }
    }
}
