import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("RSS")
    icon: "rss_feed"
    statusText: Rss.unreadCount > 0
        ? Translation.tr("%1 unread").arg(Rss.unreadCount)
        : Translation.tr("Caught up")
    tooltipText: Translation.tr("Newsboat unread feed")
    toggled: Rss.unreadCount > 0
    available: true

    mainAction: () => Rss.refresh()
    altAction:  () => Rss.reload()
}
