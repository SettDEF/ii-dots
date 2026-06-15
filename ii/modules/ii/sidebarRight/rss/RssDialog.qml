// Full-window RSS list — opened from the RSS quickToggle's popup
// button.  Shows the same items as the tile but in a much larger,
// scrollable layout with feed name + author + age columns.
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    backgroundHeight: 600

    function _fmtAge(ts) {
        if (!ts) return ""
        const dt = Math.floor(Date.now() / 1000) - ts
        if (dt < 60)        return Translation.tr("just now")
        if (dt < 3600)      return Translation.tr("%1 m").arg(Math.floor(dt / 60))
        if (dt < 86400)     return Translation.tr("%1 h").arg(Math.floor(dt / 3600))
        if (dt < 86400 * 7) return Translation.tr("%1 d").arg(Math.floor(dt / 86400))
        return Translation.tr("%1 w").arg(Math.floor(dt / 604800))
    }
    function _feedHost(url) {
        const m = (url || "").match(/^https?:\/\/(?:www\.)?([^\/]+)/)
        return m ? m[1] : (url || "")
    }

    WindowDialogTitle {
        text: Translation.tr("RSS — %1 unread")
            .arg(Rss.unreadCount)
    }
    WindowDialogSeparator {}

    // Toolbar — refresh + reload
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Rectangle {
            Layout.preferredHeight: 32
            implicitWidth: relRow.implicitWidth + 18
            radius: height / 2
            color: relHov.hovered
                ? Qt.alpha(Appearance.colors.colPrimary, 0.18)
                : Appearance.colors.colLayer2
            Behavior on color { ColorAnimation { duration: 120 } }
            HoverHandler { id: relHov }
            TapHandler { onTapped: Rss.reload() }
            RowLayout {
                id: relRow
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    text: "cloud_download"; iconSize: 16
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    text: Translation.tr("Reload feeds")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
        Rectangle {
            Layout.preferredHeight: 32
            implicitWidth: refRow.implicitWidth + 18
            radius: height / 2
            color: refHov.hovered
                ? Appearance.colors.colLayer2Hover
                : Appearance.colors.colLayer2
            HoverHandler { id: refHov }
            TapHandler { onTapped: Rss.refresh() }
            RowLayout {
                id: refRow
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    text: "refresh"; iconSize: 16
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    text: Translation.tr("Refresh")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
        Item { Layout.fillWidth: true }
    }

    // List
    ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.topMargin: 8
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        clip: true

        ListView {
            spacing: 4
            model: Rss.items
            delegate: Rectangle {
                id: row
                required property var modelData
                width: ListView.view.width
                radius: Appearance.rounding.normal
                color: rowHov.hovered
                    ? Qt.alpha(Appearance.colors.colOnLayer0, 0.06)
                    : (modelData.unread
                        ? Qt.alpha(Appearance.colors.colPrimary, 0.06)
                        : "transparent")
                Behavior on color { ColorAnimation { duration: 120 } }
                implicitHeight: rowCol.implicitHeight + 14
                HoverHandler { id: rowHov }
                TapHandler {
                    onTapped: {
                        if (row.modelData.url)
                            Quickshell.execDetached(["xdg-open", row.modelData.url])
                        Rss.markRead(row.modelData.url)
                    }
                }

                ColumnLayout {
                    id: rowCol
                    anchors {
                        left: parent.left; right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 12; rightMargin: 12
                    }
                    spacing: 1

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle {
                            visible: row.modelData.unread
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 8; Layout.preferredHeight: 8
                            radius: 4
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.title || row.modelData.url
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: row.modelData.unread ? Font.DemiBold : Font.Normal
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                        StyledText {
                            text: root._fmtAge(row.modelData.pubDate)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: row.modelData.unread ? 16 : 0
                        spacing: 8
                        StyledText {
                            text: root._feedHost(row.modelData.feed)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            visible: row.modelData.author !== ""
                            text: "·  " + row.modelData.author
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            // Empty state
            ColumnLayout {
                anchors.centerIn: parent
                visible: Rss.items.length === 0
                spacing: 8
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "rss_feed"; iconSize: 48
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No items yet")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Hit Reload to fetch your feeds.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    opacity: 0.7
                }
            }
        }
    }
}
