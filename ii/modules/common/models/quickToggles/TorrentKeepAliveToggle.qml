import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Keeps the system from suspending while torrents are running — DPMS (screen
// blanking) still works. Implemented via systemd-inhibit with `--what=sleep`,
// so logind refuses sleep / hybrid-sleep / hibernate as long as the toggle is
// on. The screen still turns off normally because we don't block `idle`.
//
// Smart auto-off: when no torrents are active (downloading / seeding / etc.),
// the inhibitor process is stopped on its own and the tile shows "Idle —
// nothing to keep alive for". Re-enables itself when an active torrent
// appears, IF the user originally turned it on.
QuickToggleModel {
    id: root

    name: Translation.tr("Torrent keep-alive")
    icon: enabled_ ? "download_for_offline" : "downloading"
    tooltipText: Translation.tr("Block system sleep while torrents are active (screen can still turn off)")

    // User intent (latched). The inhibitor process is only running when this
    // is true AND there's at least one active torrent.
    property bool enabled_: false
    readonly property bool hasActiveTorrents: (Qbt.activeCount ?? 0) > 0
    readonly property bool actuallyInhibiting: inhibitor.running

    toggled: enabled_
    statusText: !enabled_
        ? Translation.tr("Off")
        : (hasActiveTorrents
            ? `${Qbt.activeCount} ${Qbt.activeCount === 1 ? Translation.tr("active") : Translation.tr("active")}`
            : Translation.tr("Idle"))

    mainAction: () => {
        enabled_ = !enabled_
    }

    Process {
        id: inhibitor
        // sleep infinity holds the inhibitor lock as long as the process lives.
        // --what=sleep blocks suspend/hibernate ONLY (not idle/DPMS).
        command: ["systemd-inhibit",
                  "--what=sleep",
                  "--who=quickshell-torrent",
                  "--why=qBittorrent has active torrents",
                  "--mode=block",
                  "sleep", "infinity"]
        running: false
    }

    // Drive the process from intent + activity.
    onEnabled_Changed: _sync()
    onHasActiveTorrentsChanged: _sync()
    Component.onCompleted: _sync()
    Component.onDestruction: inhibitor.running = false

    function _sync() {
        const want = enabled_ && hasActiveTorrents
        if (want !== inhibitor.running) inhibitor.running = want
    }
}
