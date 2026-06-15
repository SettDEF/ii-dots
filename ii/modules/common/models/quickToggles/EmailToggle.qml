import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    id: root
    name: Email.unread > 0
        ? Translation.tr("%1 new").arg(Email.unread)
        : Translation.tr("Inbox")
    icon: Email.unread > 0 ? "mark_email_unread" : "mail"
    statusText: Email.unread > 0
        ? Translation.tr("Unread mail")
        : (Email.loading ? Translation.tr("Checking…")
                         : Translation.tr("All read"))
    tooltipText: Translation.tr("Open inbox")
    toggled: Email.unread > 0
    available: true

    mainAction: () => Email.open()
    altAction:  () => Email.refresh()
}
