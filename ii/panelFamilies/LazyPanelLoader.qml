// LazyPanelLoader — like PanelLoader, but auto-unloads after the panel has
// been closed for `idleMs`. The next open re-instantiates it (~100-300 ms
// construction cost). All features stay; only RAM is reclaimed.
//
// Usage:
//   LazyPanelLoader {
//       isOpen: GlobalStates.wallTuneOpen
//       idleMs: 5 * 60 * 1000   // 5 min default
//       component: WallTune {}
//   }
//
// Why Scope (not QtObject) and not LazyLoader directly:
//   - Quickshell discovers panel windows by walking children of Scope/ShellRoot.
//     A LazyLoader buried inside a QtObject property is NOT walked, so its
//     loaded PanelWindow never becomes a Wayland surface.
//   - Scope is Quickshell's own non-visual container: it accepts arbitrary
//     QObject children (like our Timer) and forwards window discovery into
//     its inner LazyLoader.
import QtQuick
import Quickshell

import qs.modules.common

Scope {
    id: root
    property Component component
    property bool isOpen: false
    property int  idleMs: 5 * 60 * 1000
    property bool extraCondition: true

    Timer {
        id: idleTimer
        interval: root.idleMs
        repeat: false
    }

    LazyLoader {
        id: loader
        active: Config.ready && root.extraCondition && (root.isOpen || idleTimer.running)
        component: root.component
    }

    onIsOpenChanged: {
        if (isOpen) idleTimer.stop()
        else        idleTimer.restart()
    }
}
