pragma Singleton
import QtQuick
import Quickshell

/**
 * Staged startup. Building every panel in one go kept the whole shell blank
 * until the last settings panel was done. Panels now say when they are
 * needed (PanelLoader { stage: N }):
 *   0  on screen at once: bar, wallpaper, dock, notifications, lock
 *   1  a frame later: popups people hit in the first seconds (OSD, overview…)
 *   2  the rest: settings panels, editors, rarely opened tools
 * Each stage starts only after the previous one has rendered a frame.
 *
 * Timings go to the log: `qs log -c ii | grep Startup`.
 */
Singleton {
    id: root
    readonly property double t0: Date.now()
    property int stage: 0
    readonly property int lastStage: 2

    function ms() { return Date.now() - root.t0; }
    function mark(what) { console.info(`[Startup] ${root.ms()} ms  ${what}`); }
    // one panel built: kept for the summary line
    property var costs: []
    function cost(name, ms, stage) {
        root.costs.push({ name, ms, stage });
        if (ms >= 40) console.info(`[Startup] ${ms} ms  ${name} (stage ${stage})`);
    }

    Connections {
        target: Config
        function onReadyChanged() { if (Config.ready) root.mark("config ready"); }
    }
    function summary() {
        const by = [0, 0, 0];
        for (const c of root.costs) by[c.stage] += c.ms;
        root.mark(`panels built: stage 0 ${by[0]} ms, stage 1 ${by[1]} ms, stage 2 ${by[2]} ms (${root.costs.length} panels)`);
    }

    // one stage per timer tick; the timer only fires once the event loop is
    // free again, i.e. after the previous stage was built and painted
    Timer {
        interval: 16
        running: root.stage < root.lastStage
        repeat: true
        onTriggered: {
            root.mark(`stage ${root.stage} done`);
            root.stage++;
            if (root.stage === root.lastStage) Qt.callLater(() => { root.mark("all stages started"); root.summary(); });
        }
    }
}
