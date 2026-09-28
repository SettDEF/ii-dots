pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.panels.lock
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

LockScreen {
    id: root

    // ── Suspend popup + chain (Super+Shift+L → loading popup → lock + suspend) ──
    GlobalShortcut {
        name: "suspendStart"
        description: "Show suspending popup, then lock + suspend"
        onPressed: {
            GlobalStates.suspendingOpen = true
            suspendChainTimer.restart()
        }
    }
    Timer {
        id: suspendChainTimer
        interval: 600
        onTriggered: {
            // Lock first so the lock surface is composited and DPMS-off
            // happens with the lock already drawn — avoids the "screen
            // black, then lock pops in after resume" flash.
            root.lock()
            // ASUS-Z13 specific quietening:
            //   1. Drop fan profile to Quiet so the EC doesn't keep
            //      ramping during the suspend transition (common cause
            //      of the loud fan blast right after Super+Shift+L on
            //      Flow Z13 / Strix laptops under load).
            //   2. Push CPU governor to powersave so frequencies fall
            //      before the kernel freezes — quieter, faster sleep.
            //   3. `sync` so dirty IO is flushed before the kernel
            //      hands off to s2idle (no half-written pages on resume).
            //   4. Tiny `sleep` so the lock surface paints before the
            //      kernel freezes, otherwise the first frame after
            //      resume is sometimes the previous wallpaper.
            // Each command is best-effort — failures are swallowed so
            // a missing tool (asusctl on non-ASUS) never blocks suspend.
            Quickshell.execDetached(["bash", "-c", `
                command -v asusctl >/dev/null && asusctl profile -P Quiet >/dev/null 2>&1 || true
                command -v cpupower >/dev/null && sudo -n cpupower frequency-set -g powersave >/dev/null 2>&1 || true
                sync
                sleep 0.25
                systemctl suspend || loginctl suspend
            `])
        }
    }
    // Auto-clear the popup state shortly after — keeps things idempotent.
    Timer {
        interval: 1500
        running: GlobalStates.suspendingOpen
        repeat: false
        onTriggered: GlobalStates.suspendingOpen = false
    }

    // The visual indicator is drawn around the existing wallpaper clock
    // (see CookieClock.qml — gated on GlobalStates.suspendingOpen). No extra
    // overlay window is created here.

    lockSurface: LockSurface {
        context: root.context
    }

    // Push everything down
    Variants {
        model: Quickshell.screens
        delegate: Scope {
            required property ShellScreen modelData
            property bool shouldPush: GlobalStates.screenLocked
            // Null-guarded: Variants re-models when a monitor is plugged,
            // unplugged, or comes back from suspend, and the delegate
            // outlives its ShellScreen for a frame. Unguarded, all three
            // threw on every such event — and this is the LOCK SCREEN, the
            // one surface where a binding error is not merely cosmetic.
            property string targetMonitorName: modelData?.name ?? ""
            property int verticalMovementDistance: modelData?.height ?? 0
            property int horizontalSqueeze: (modelData?.width ?? 0) * 0.2
            property int lastWorkspaceId
            // Persist per-monitor across quickshell restarts and
            // suspend/resume cycles. Without this, if the delegate
            // remounts (suspend, reload) the in-memory `lastWorkspaceId`
            // resets to 0 → unlock dispatches `workspace 0` (invalid)
            // → user stays stranded on the 2.1-billion lock workspace.
            readonly property string saveFile: `/tmp/qs-lock-ws-${targetMonitorName}.txt`

            onShouldPushChanged: {
                if (shouldPush) {
                    print(targetMonitorName)
                    const m = HyprlandData.monitors.find(m => m.name == targetMonitorName)
                    if (m && m.activeWorkspace) {
                        lastWorkspaceId = m.activeWorkspace.id
                        // Persist to disk before dispatching the jump.
                        Quickshell.execDetached(["bash", "-c",
                            `printf '%s' '${lastWorkspaceId}' > '${saveFile}'`])
                    }
                    // Sliding-up effect: jump to a far-away workspace.
                    //
                    // Two calls, not one --batch. `keyword` is an unknown
                    // request under a Lua config AND a failed request aborts
                    // the rest of the batch, so the dispatch never ran either
                    // and this effect did nothing at all.
                    Quickshell.execDetached(["hyprctl", "eval",
                        'hl.animation({ leaf = "workspaces", enabled = true, speed = 7, bezier = "menu_decel", style = "slidevert" })']);
                    HyprDispatch.run(`workspace ${2147483647 - lastWorkspaceId}`);
                } else {
                    // Restore. Fall back to the persisted file if the
                    // in-memory value was lost, then to workspace 1.
                    Quickshell.execDetached(["bash", "-c",
                        `id='${lastWorkspaceId}'; ` +
                        `if [ -z "$id" ] || [ "$id" = "0" ]; then ` +
                        `  id=$(cat '${saveFile}' 2>/dev/null); ` +
                        `fi; ` +
                        `[ -z "$id" ] && id=1; ` +
                        `hyprctl --batch "dispatch workspace $id; reload" >/dev/null; ` +
                        `rm -f '${saveFile}'`])
                }
            }
        }
    }

    // Startup recovery: if the previous quickshell session crashed or
    // the user resumed into a lost lock state, the active workspace can
    // still be the 2.14-billion lock workspace. Detect this on startup
    // and bail out to whatever workspace we last persisted, or 1.
    Component.onCompleted: {
        Quickshell.execDetached(["bash", "-c", `
            for m in $(hyprctl monitors -j | jq -r '.[].name'); do
                cur=$(hyprctl monitors -j | jq -r ".[] | select(.name==\\"$m\\") | .activeWorkspace.id")
                if [ -n "$cur" ] && [ "$cur" -gt 1000000000 ] 2>/dev/null; then
                    saved=$(cat /tmp/qs-lock-ws-$m.txt 2>/dev/null)
                    [ -z "$saved" ] && saved=1
                    hyprctl dispatch "hl.dsp.focus({ monitor = \"$m\" })" >/dev/null
                    hyprctl dispatch "hl.dsp.focus({ workspace = \"$saved\" })" >/dev/null
                    rm -f /tmp/qs-lock-ws-$m.txt
                fi
            done
        `])
    }
}
