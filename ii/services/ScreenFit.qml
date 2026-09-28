pragma Singleton
pragma ComponentBehavior: Bound

// The one place that knows how tall a panel is allowed to be.
//
// This exists because the calculation was copy-pasted into every panel and the
// copies drifted. Two things are easy to get wrong and were both got wrong:
//
//   1. `screen.height` is PHYSICAL pixels. On a scaled display it reads far
//      larger than the usable logical height (2560x1600 at scale 1.6 is
//      1600x1000 logical), so a cap written against it never triggers.
//
//   2. A panel does NOT start at `margins.top`. The compositor places it after
//      any reserved strip (MiniMeters reserves 68px here, the bar 40), and the
//      margin is applied from there — so the two ADD. Using max() instead of a
//      sum under-counted and ran the panel 24px off the bottom of the screen.
//
// Panels call maxHeight(win) and cannot get either wrong.

import qs.services
import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root

    // Never let a panel shrink below this, even on a tiny or mis-reported
    // screen — a 3px panel is a worse failure than a slightly tall one.
    readonly property int minHeight: 160
    // Breathing room under a panel. Kept small deliberately: this is the only
    // thing standing between the panels and the bottom of the screen, and at 16
    // it was throwing away usable height on every one of them at once.
    readonly property int defaultBottomGap: 6

    // Shared width for the stacked settings panels. Side by side, three
    // different widths (360/390/400) read as a mistake rather than as
    // deliberate — and the widest is used so nothing gets cramped.
    readonly property int panelWidth: 400

    function monitorFor(win) {
        const ms = HyprlandData.monitors ?? [];
        if (ms.length === 0) return null;
        const name = win && win.screen ? win.screen.name : "";
        return ms.find(m => m.name === name) ?? ms[0];
    }


    // Usable logical width of the screen the panel is on.
    function logicalWidth(win) {
        const m = root.monitorFor(win);
        if (m) return m.width / (m.scale || 1);
        return (win && win.screen) ? win.screen.width : 1920;
    }
    // Usable logical height of the screen the panel is on.
    function logicalHeight(win) {
        const m = root.monitorFor(win);
        if (m) return m.height / (m.scale || 1);
        return (win && win.screen) ? win.screen.height : 1000;
    }

    // What the compositor has reserved at the top (bars, docks, anything with
    // an exclusive zone — including surfaces this config did not create).
    function reservedTop(win) {
        const m = root.monitorFor(win);
        return (m && m.reserved && m.reserved.length > 1) ? Math.round(m.reserved[1]) : 0;
    }

    function reservedBottom(win) {
        const m = root.monitorFor(win);
        return (m && m.reserved && m.reserved.length > 3) ? Math.round(m.reserved[3]) : 0;
    }

    // Tallest a top-anchored panel may be without running off screen.
    function maxHeight(win, bottomGap) {
        if (!win) return 1000;
        const gap = bottomGap === undefined ? root.defaultBottomGap : bottomGap;
        // A panel with ExclusionMode.Ignore is placed at margins.top exactly;
        // one without is placed AFTER the reserved strip and the margin adds
        // to it. Subtracting the strip for both under-counted by 40px on the
        // ones that ignore it.
        const ignores = win.exclusionMode === ExclusionMode.Ignore;
        const top = (ignores ? 0 : root.reservedTop(win))
                  + (win.margins ? win.margins.top : 0);
        return Math.max(root.minHeight,
                        root.logicalHeight(win) - top - root.reservedBottom(win) - gap);
    }

    // Convenience for the usual shape: content height, capped.
    function fit(win, contentHeight, padding, bottomGap) {
        return Math.min(contentHeight + (padding ?? 0), root.maxHeight(win, bottomGap));
    }
}



