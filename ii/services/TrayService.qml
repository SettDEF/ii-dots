pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

Singleton {
    id: root

    property bool smartTray: Config.options.tray.filterPassive
    // Discord's tray icon turns into a crossed mic while you are muted in a
    // call; the bar's red mic icon says that already (with a Discord badge)
    readonly property bool discordMuteShown: DiscordVoice.inVoice && !!DiscordVoice.settings?.mute
    function shown(i) {
        return (!smartTray || i.status !== Status.Passive)
            && !(discordMuteShown && i.id.startsWith("discord_status_icon"))
    }
    property list<var> itemsInUserList: SystemTray.items.values.filter(i => Config.options.tray.pinnedItems.includes(i.id) && shown(i))
    property list<var> itemsNotInUserList: SystemTray.items.values.filter(i => !Config.options.tray.pinnedItems.includes(i.id) && shown(i))

    property bool invertPins: Config.options.tray.invertPinnedItems
    property list<var> pinnedItems: invertPins ? itemsNotInUserList : itemsInUserList
    property list<var> unpinnedItems: invertPins ? itemsInUserList : itemsNotInUserList

    function getTooltipForItem(item) {
        var result = item.tooltipTitle.length > 0 ? item.tooltipTitle
                : (item.title.length > 0 ? item.title : item.id);
        if (item.tooltipDescription.length > 0) result += " • " + item.tooltipDescription;
        if (Config.options.tray.showItemId) result += "\n[" + item.id + "]";
        return result;
    }

    // Pinning
    function pin(itemId) {
        var pins = Config.options.tray.pinnedItems;
        if (pins.includes(itemId)) return;
        Config.options.tray.pinnedItems.push(itemId);
    }
    function unpin(itemId) {
        Config.options.tray.pinnedItems = Config.options.tray.pinnedItems.filter(id => id !== itemId);
    }
    function togglePin(itemId) {
        var pins = Config.options.tray.pinnedItems;
        if (pins.includes(itemId)) {
            unpin(itemId)
        } else {
            pin(itemId)
        }
    }

}
