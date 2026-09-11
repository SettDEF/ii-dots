import QtQuick
import qs
import qs.services
import qs.modules.common
import Quickshell

/**
 * VPN quick toggle.
 *
 * All state and control lives in the Vpn service, which already handles both
 * backends (NetworkManager profiles, and the NordVPN CLI when installed) — this
 * is only the toggle's view model.
 *
 * Tapping connects to the most recently used profile rather than asking which
 * one, because a quick toggle that opens a chooser is not quick. The expand
 * action opens the full panel for picking a specific server.
 */
QuickToggleModel {
    id: root
    name: Translation.tr("VPN")

    icon: Vpn.connected ? "vpn_lock" : "vpn_key_off"
    toggled: Vpn.connected
    // Always shown. It would be tidier to hide this when nothing is set up,
    // but then the tile silently vanishes for anyone who has not configured a
    // VPN yet — including right after adding it. With nothing configured it
    // stays off and its tap opens the panel, which explains what to do.
    available: true
    readonly property bool _configured: Vpn.nordAvailable || Vpn.profiles.length > 0

    statusText: Vpn.busy ? Translation.tr("…")
        : Vpn.connected ? (Vpn.activeCountry || Vpn.activeName || Translation.tr("On"))
        : root._configured ? Translation.tr("Off")
        : Translation.tr("Not set up")

    tooltipText: Vpn.connected
        ? Translation.tr("Connected: %1").arg(Vpn.activeName || Translation.tr("VPN"))
        : root._configured ? Translation.tr("Not connected")
        : Translation.tr("No VPN configured — tap to set one up")

    // Remembered across toggles so "on" returns you where you were.
    property var _lastProfile: null

    mainAction: () => {
        // Nothing to toggle yet: send them somewhere that explains why.
        if (!root._configured) { GlobalStates.connectivityVpnOpen = true; return; }
        if (Vpn.connected) {
            root._lastProfile = Vpn.profiles.find(p => p.active) ?? root._lastProfile;
            Vpn.disconnect();
            return;
        }
        const target = root._lastProfile ?? Vpn.profiles[0] ?? null;
        if (target) Vpn.connectTo(target);
        else if (Vpn.nordAvailable) Vpn.connectTo({ country: "" });  // nearest server
    }

    // Long-press / expand: the VPN half of the connectivity popup, where
    // Wi-Fi and Bluetooth also live.
    hasMenu: true
    altAction: () => { GlobalStates.connectivityVpnOpen = true }

    Component.onCompleted: Vpn.refresh()
}
