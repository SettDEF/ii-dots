pragma Singleton
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: service

    property string currentProfile: "Balanced"
    property string gpuMode: "Integrated"
    property bool fanCurveActive: false
    property var profiles: ["Quiet", "Balanced", "Performance"]

    // NOTE: `asusctl profile` takes SUBCOMMANDS (get/set/next/list), not the
    // -p/-P flags this used to pass — those are rejected outright
    // ("Unrecognized argument: -p"), so the getter never returned anything and
    // the setter never applied anything. And a Process's `stdout` is a
    // StdioCollector, never a string, so `stdout.includes(...)` could not work
    // either: the getter always fell through to the "Balanced" branch and the
    // widget displayed Balanced permanently, whatever the real profile was.
    Process {
        id: profileGetter
        running: true
        command: ["asusctl", "profile", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                // "Active profile: Quiet"
                const t = text.trim();
                for (const p of service.profiles) {
                    if (t.indexOf(p) >= 0) { service.currentProfile = p; return }
                }
                // Leave the previous value alone rather than inventing one.
            }
        }
    }
    function refreshProfile() { profileGetter.running = true }

    Process {
        id: gpuGetter
        running: true
        command: ["supergfxctl", "-g"]
        stdout: StdioCollector {
            onStreamFinished: { const t = text.trim(); if (t.length) service.gpuMode = t }
        }
    }
    Process { id: executor }

    // ── Mouse scroll-speed control via Hyprland ──────────────────────
    // mice: [{ name, address, scrollFactor }]
    property var mice: []

    function refreshMice() {
        miceProc.exec({ command: ["bash", "-c", "hyprctl devices -j 2>/dev/null"] })
    }

    function setScrollFactor(mouseName, value) {
        // `device:<name>:<key>` syntax, via the Lua config API. The old
        // `hyprctl keyword` shell-out returned "unknown request" on this
        // Hyprland and exited 0, so scroll factor never actually changed.
        HyprDispatch.config(`device:${mouseName}:scroll_factor`, value)
        const updated = service.mice.slice()
        for (let i = 0; i < updated.length; i++) {
            if (updated[i].name === mouseName) updated[i].scrollFactor = value
        }
        service.mice = updated
    }

    Process {
        id: miceProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    const out = []
                    for (const m of (data.mice ?? [])) {
                        out.push({
                            name: m.name,
                            address: m.address,
                            // Hyprland's IPC doesn't echo back the current scroll_factor,
                            // so we track it from the user's slider input. Default 1.0.
                            scrollFactor: 1.0
                        })
                    }
                    service.mice = out
                } catch (e) {
                    console.error("[DeviceControl] mice parse:", e)
                }
            }
        }
    }

    Timer { interval: 30000; running: true; repeat: true; onTriggered: service.refreshMice() }

    // Commands are declared on the Processes themselves now — reassigning them
    // here is what kept the broken `-p` flag alive even after it was fixed.
    Component.onCompleted: refreshMice()

    // asusd switches the profile by itself on AC/battery transitions, so a
    // widget that only reads once will drift out of sync with reality.
    Timer { interval: 10000; running: true; repeat: true; onTriggered: service.refreshProfile() }

    function cycleProfile() {
        var idx = profiles.indexOf(currentProfile);
        setProfile(profiles[(idx + 1) % profiles.length]);
    }

    function setProfile(name) {
        // Optimistic so the label moves immediately, then re-read: asusd can
        // refuse or override the choice (it re-applies its own profile on
        // AC/battery transitions), and the widget must show what IS, not what
        // was asked for.
        currentProfile = name;
        profileSetter.exec({ command: ["asusctl", "profile", "set", name] });
    }
    Process { id: profileSetter; onExited: service.refreshProfile() }

    function setGpuMode(mode) {
        gpuMode = mode;
        executor.command = ["supergfxctl", "-m", mode];
        executor.running = true;
    }

    function setFanCurve(enabled) {
        fanCurveActive = enabled;
        executor.command = [
            "pkexec", "asusctl", "fan-curve", 
            "--mod-profile", currentProfile.toLowerCase(), 
            "--enable-fan-curves", enabled ? "true" : "false"
        ];
        executor.running = true;
    }
}
