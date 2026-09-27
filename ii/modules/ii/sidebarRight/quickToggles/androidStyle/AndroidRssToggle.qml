// RSS feed tile — expanded view shows the top unread items from
// newsboat's cache.  Tap a row → opens the article in the default
// browser (and marks it read in newsboat's database).
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

AndroidQuickToggleButton {
    id: root
    toggleModel: RssToggle {}
    signal requestRssDialog()

    function _fmtAge(ts) {
        if (!ts) return ""
        const dt = Math.floor(Date.now() / 1000) - ts
        if (dt < 60)        return Translation.tr("just now")
        if (dt < 3600)      return Translation.tr("%1m").arg(Math.floor(dt / 60))
        if (dt < 86400)     return Translation.tr("%1h").arg(Math.floor(dt / 3600))
        if (dt < 86400 * 7) return Translation.tr("%1d").arg(Math.floor(dt / 86400))
        return Translation.tr("%1w").arg(Math.floor(dt / 604800))
    }

    expandedDelegate: Component {
        ColumnLayout {
            spacing: 6

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol {
                    text: "rss_feed"; iconSize: 22
                    color: Appearance.m3colors.m3onSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Rss.unreadCount > 0
                        ? Translation.tr("RSS · %1 unread").arg(Rss.unreadCount)
                        : Translation.tr("RSS · Caught up")
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSurface
                    elide: Text.ElideRight
                }
                Rectangle {
                    Layout.preferredWidth: 24; Layout.preferredHeight: 24
                    radius: 12
                    color: relHov.hovered ? Appearance.colors.colLayer2Hover : ColorUtils.transparentize(Appearance.colors.colLayer2Hover)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    HoverHandler { id: relHov }
                    TapHandler { onTapped: Rss.reload() }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "refresh"; iconSize: 16
                        color: Appearance.m3colors.m3onSurface
                    }
                }
                // Pop out → opens the full-window RSS dialog with more entries.
                Rectangle {
                    Layout.preferredWidth: 26; Layout.preferredHeight: 26
                    radius: 13
                    color: popHov.hovered
                        ? Qt.alpha(Appearance.colors.colPrimary, 0.32)
                        : Qt.alpha(Appearance.colors.colPrimary, 0.14)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    HoverHandler { id: popHov }
                    TapHandler { onTapped: root.requestRssDialog() }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "open_in_new"; iconSize: 14
                        color: Appearance.colors.colPrimary
                    }
                }
            }

            // List
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
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
                                : ColorUtils.transparentize(Qt.alpha(Appearance.colors.colPrimary, 0.06)))
                        Behavior on color { ColorAnimation { duration: 120 } }
                        implicitHeight: rowCol.implicitHeight + 8
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
                                leftMargin: 8; rightMargin: 8
                            }
                            spacing: 0
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Rectangle {
                                    visible: row.modelData.unread
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.preferredWidth: 6; Layout.preferredHeight: 6
                                    radius: 3
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: row.modelData.title || row.modelData.url
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    font.weight: row.modelData.unread ? Font.DemiBold : Font.Normal
                                    color: Appearance.m3colors.m3onSurface
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    text: root._fmtAge(row.modelData.pubDate)
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: row.modelData.author !== ""
                                text: row.modelData.author
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                                opacity: 0.85
                            }
                        }
                    }

                    // Empty state
                    StyledText {
                        anchors.centerIn: parent
                        visible: Rss.items.length === 0
                        text: Translation.tr("No items yet — set up newsboat first.")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        opacity: 0.6
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        width: parent.width - 16
                    }
                }
            }
        }
    }
}
