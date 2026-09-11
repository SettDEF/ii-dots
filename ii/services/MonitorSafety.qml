pragma Singleton
pragma ComponentBehavior: Bound

// Guard rails around turning a display off.
//
// Disabling a monitor is the one setting in this shell that can hide its own
// undo: switch off the panel you are looking at and the button that would put
// it back went dark with it. Two rules make that unreachable.
//
//   1. HARD REFUSAL — anything that would leave zero active outputs is
//      rejected before it runs. MonitorManager.disable() already had this
//      check, but it only console.warn()s, so a click did nothing and the UI
//      had no way to say why. canDisable()/blockReason() expose the same rule
//      as something a button can grey itself out with.
//
//   2. EVERYTHING ELSE IS PROVISIONAL — a disable starts a countdown. Unless
//      it is confirmed on a screen that is still lit, the monitor comes back
//      by itself. That covers the case rule 1 cannot: several displays on and
//      you turn off the wrong one, so output technically survives but YOUR
//      output does not.
//
// Rule 2 is the load-bearing one. Rule 1 only knows how many outputs are
// alive; it cannot know which one your eyes are pointed at.

import qs.modules.common
import QtQuick
import Quickshell

Singleton {
    id: root

    // How long you get to confirm before it undoes itself. Long enough to
    // find the dialog on another screen, short enough that you are not
    // stranded staring at a black panel wondering if it is coming back.
    property int revertSeconds: 15

    // The monitor awaiting confirmation; "" when nothing is pending.
    property string pendingName: ""
    property int secondsLeft: 0
    readonly property bool confirmPending: root.pendingName.length > 0

    // Set when a countdown ran out instead of being answered, so the UI can
    // explain why a display came back on its own rather than looking buggy.
    property string lastAutoReverted: ""

    // Why the last request was turned down. Read by the panel to show the
    // reason next to the control rather than swallowing it into the log.
    property string lastRefusal: ""

    // ── Rules ───────────────────────────────────────────────────────────

    readonly property int activeCount:
        (MonitorManager.friendly ?? []).filter(m => !m.disabled).length

    // "" means allowed. Anything else is the sentence to show the user.
    function blockReason(name) {
        const list = MonitorManager.friendly ?? [];
        const m = list.find(x => x.name === name);
        if (!m)
            return Translation.tr("That display is not connected any more.");
        if (m.disabled)
            return "";   // already off — turning it back ON is always safe
        if (list.filter(x => x.name !== name && !x.disabled).length === 0)
            return Translation.tr("This is your only active display. Turning it off would leave no screen to turn it back on from.");
        if (root.confirmPending && root.pendingName !== name)
            return Translation.tr("Finish deciding about %1 first.").arg(root.pendingName);
        return "";
    }

    function canDisable(name) {
        return root.blockReason(name).length === 0;
    }

    // ── Actions ─────────────────────────────────────────────────────────

    /** Disable `name` provisionally. Returns false (with lastRefusal set)
     *  if the rules say no — callers can rely on nothing having happened. */
    function requestDisable(name) {
        const why = root.blockReason(name);
        if (why.length > 0) {
            root.lastRefusal = why;
            return false;
        }
        root.lastRefusal = "";
        root.lastAutoReverted = "";
        root.pendingName = name;
        root.secondsLeft = root.revertSeconds;
        MonitorManager.disable(name);
        tick.restart();
        return true;
    }

    /** Accept the pending change — the display stays off. */
    function keep() {
        tick.stop();
        root.pendingName = "";
        root.secondsLeft = 0;
    }

    /** Put the pending display back and clear the countdown. */
    function undo() {
        const n = root.pendingName;
        tick.stop();
        root.pendingName = "";
        root.secondsLeft = 0;
        if (n.length > 0)
            MonitorManager.enable(n);
        return n;
    }

    /** Enable-and-clear, for the "turn it back on" direction. Enabling is
     *  never gated — there is no way to make things worse by adding output. */
    function enable(name) {
        root.lastRefusal = "";
        if (root.pendingName === name)
            root.undo();
        else
            MonitorManager.enable(name);
    }

    /** One entry point for a UI switch, so callers don't re-implement the
     *  asymmetry (disabling is guarded, enabling is not). */
    function toggle(name) {
        const m = (MonitorManager.friendly ?? []).find(x => x.name === name);
        if (!m) return false;
        if (m.disabled) { root.enable(name); return true; }
        return root.requestDisable(name);
    }

    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            root.secondsLeft -= 1;
            if (root.secondsLeft <= 0) {
                root.lastAutoReverted = root.pendingName;
                root.undo();
            }
        }
    }

    // If the pending display is somehow already back (the user re-enabled it
    // from elsewhere, or it was unplugged and replugged), there is nothing
    // left to confirm.
    Connections {
        target: MonitorManager
        function onMonitorsChanged() {
            if (!root.confirmPending) return;
            const m = (MonitorManager.friendly ?? []).find(x => x.name === root.pendingName);
            if (!m || !m.disabled) root.keep();
        }
    }
}
