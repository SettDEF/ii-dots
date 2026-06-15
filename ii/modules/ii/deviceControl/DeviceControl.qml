pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: service

    property string currentProfile: "Balanced"
    property string gpuMode: "Integrated"
    property bool fanCurveActive: false
    property var profiles: ["Quiet", "Balanced", "Performance"]

    Process {
        id: profileGetter
        running: true
        onExited: (code, status) => {
            if (stdout.includes("Performance")) service.currentProfile = "Performance";
            else if (stdout.includes("Quiet")) service.currentProfile = "Quiet";
            else service.currentProfile = "Balanced";
        }
    }

    Process { id: gpuGetter; running: true; onExited: (c, s) => service.gpuMode = stdout.trim() }
    Process { id: executor }

    // ── Mouse scroll-speed control via Hyprland ──────────────────────
    // mice: [{ name, address, scrollFactor }]
    property var mice: []

    function refreshMice() {
        miceProc.exec({ command: ["bash", "-c", "hyprctl devices -j 2>/dev/null"] })
    }

    function setScrollFactor(mouseName, value) {
        // `device:<name>:<key>` syntax — quote the whole arg so spaces
        // in the device name survive the bash hop.
        executor.exec({ command: ["bash", "-c",
            `hyprctl keyword 'device:${mouseName}:scroll_factor' ${value}`] })
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

    Component.onCompleted: {
        profileGetter.command = ["asusctl", "profile", "-p"]; profileGetter.running = true;
        gpuGetter.command = ["supergfxctl", "-g"]; gpuGetter.running = true;
        refreshMice();
    }

    function cycleProfile() {
        var idx = profiles.indexOf(currentProfile);
        setProfile(profiles[(idx + 1) % profiles.length]);
    }

    function setProfile(name) {
        currentProfile = name;
        executor.command = ["asusctl", "profile", "-P", name];
        executor.running = true;
    }

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
