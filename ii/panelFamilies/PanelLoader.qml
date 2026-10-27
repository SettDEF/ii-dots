import QtQuick
import Quickshell

import qs.modules.common

// stage: when to build it (see Startup.qml) — 0 at once, 1 next frame, 2 after that
LazyLoader {
    id: pl
    property bool extraCondition: true
    property int stage: 2
    readonly property bool wanted: Config.ready && extraCondition && Startup.stage >= stage
    active: false
    // set by hand, not bound, so the build can be timed (it happens inside the setter)
    function apply() {
        if (pl.active === pl.wanted) return;
        const t = Date.now();
        pl.active = pl.wanted;
        if (pl.wanted && pl.item) Startup.cost(`${pl.item}`.split("(")[0].replace(/_QMLTYPE_\d+/, ""), Date.now() - t, pl.stage);
    }
    onWantedChanged: pl.apply()
    Component.onCompleted: pl.apply()
}
