pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    required property real popupRounding

    implicitHeight: col.implicitHeight + 24
    radius: popupRounding
    color: Appearance.colors.colLayer0
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 12

        // ── Header ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: "keyboard"
                iconSize: Appearance.font.pixelSize.larger
                color: KeyTracker.lastKey !== ""
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colSubtext
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }
            StyledText {
                text: "Keys"
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            Item { Layout.fillWidth: true }

            // Level badge
            Rectangle {
                implicitWidth: lvlLabel.implicitWidth + 14
                implicitHeight: lvlLabel.implicitHeight + 6
                radius: height / 2
                color: Appearance.colors.colSecondaryContainer
                StyledText {
                    id: lvlLabel
                    anchors.centerIn: parent
                    text: qsTr("LVL %1").arg(KeyTracker.xpLevel)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }
        }

        // ── Big key display ───────────────────────────────────────────────
        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: keyBox.implicitWidth
            implicitHeight: keyBox.implicitHeight

            Rectangle {
                id: keyBox
                implicitWidth: Math.max(130, keyLbl.implicitWidth + 48)
                implicitHeight: 76
                radius: Appearance.rounding.large
                color: KeyTracker.lastKey !== ""
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colLayer2
                border.width: 1
                border.color: KeyTracker.lastKey !== ""
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colLayer0Border
                Behavior on color        { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                Behavior on implicitWidth { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                StyledText {
                    id: keyLbl
                    anchors.centerIn: parent
                    text: KeyTracker.lastKey !== "" ? KeyTracker.lastKey : "—"
                    font.pixelSize: Appearance.font.pixelSize.larger * 1.5
                    font.weight: Font.Bold
                    color: KeyTracker.lastKey !== ""
                        ? Appearance.m3colors.m3onPrimary
                        : Appearance.colors.colOnLayer0
                    opacity: KeyTracker.lastKey !== "" ? 1 : 0.22
                    Behavior on color   { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
            }
        }

        // ── XP progress ───────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 5

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    text: qsTr("Level %1").arg(KeyTracker.xpLevel)
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    text: qsTr("%1 / 1000 XP").arg(Math.round(KeyTracker.xpTotal % 1000))
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.4
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 8
                radius: 4
                color: Appearance.colors.colLayer2

                Rectangle {
                    width: parent.width * ((KeyTracker.xpTotal % 1000) / 1000)
                    height: parent.height
                    radius: parent.radius
                    color: Appearance.colors.colPrimary
                    Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                }
            }
        }

        // ── Hint ──────────────────────────────────────────────────────────
        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Pipe key names to ~/.local/share/qs-hud-lastkey")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer0
            opacity: 0.25
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }
}
