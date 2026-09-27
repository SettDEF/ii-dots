pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Which optional tools are installed, and what each one turns on.
 *
 * Features whose tool is missing hide themselves rather than erroring, which is
 * good behaviour and a terrible explanation: on a fresh install half the shell
 * is simply absent with nothing saying why. This is the list that says why.
 */
Singleton {
    id: root

    /// command -> { package, label, group }. The command is what gets probed;
    /// the package is what to install, and the two differ often enough
    /// (wl-copy/wl-clipboard, nmcli/networkmanager) to be worth spelling out.
    readonly property var requirements: [
        { cmd: "hyprctl",     pkg: "hyprland",          group: "core",     label: qsTr("The compositor itself") },
        { cmd: "qs",          pkg: "quickshell",        group: "core",     label: qsTr("This shell") },
        { cmd: "notify-send", pkg: "libnotify",         group: "core",     label: qsTr("Notifications") },

        { cmd: "wl-copy",     pkg: "wl-clipboard",      group: "everyday", label: qsTr("Copy and paste") },
        { cmd: "cliphist",    pkg: "cliphist",          group: "everyday", label: qsTr("Clipboard history") },
        { cmd: "grim",        pkg: "grim",              group: "everyday", label: qsTr("Screenshots") },
        { cmd: "slurp",       pkg: "slurp",             group: "everyday", label: qsTr("Region select and screen snips") },
        { cmd: "hyprpicker",  pkg: "hyprpicker",        group: "everyday", label: qsTr("Colour picker") },
        { cmd: "nmcli",       pkg: "networkmanager",    group: "everyday", label: qsTr("Network panel and Wi-Fi") },
        { cmd: "wpctl",       pkg: "wireplumber",       group: "everyday", label: qsTr("Volume, devices, per-app audio") },
        { cmd: "brightnessctl", pkg: "brightnessctl",   group: "everyday", label: qsTr("Screen brightness") },
        { cmd: "xdg-open",    pkg: "xdg-utils",         group: "everyday", label: qsTr("Opening links and files") },

        { cmd: "matugen",     pkg: "matugen",           group: "extras",   label: qsTr("Colours that follow the wallpaper") },
        { cmd: "ddcutil",     pkg: "ddcutil",           group: "extras",   label: qsTr("Brightness on an external monitor") },
        { cmd: "ffmpeg",      pkg: "ffmpeg",            group: "extras",   label: qsTr("Screen recording") },
        { cmd: "udisksctl",   pkg: "udisks2",           group: "extras",   label: qsTr("Removable drives") },
        { cmd: "trans",       pkg: "translate-shell",   group: "extras",   label: qsTr("Translation") },
        { cmd: "timew",       pkg: "timew",             group: "extras",   label: qsTr("Time tracking") },
        { cmd: "zenity", pkg: "zenity",        group: "extras",   label: qsTr("System file dialogs") },

        { cmd: "asusctl",     pkg: "asusctl",           group: "rog",      label: qsTr("Fan curves and power profiles") },
        { cmd: "supergfxctl", pkg: "supergfxctl",       group: "rog",      label: qsTr("Graphics mode switching") }
    ]

    /// cmd -> bool. Empty until the first check finishes.
    property var present: ({})
    property bool checked: false
    /// ASUS laptop, so the ROG tools are worth offering.
    property bool isAsus: false

    readonly property var missing: root.requirements.filter(r => root.present[r.cmd] === false)
    /// The ROG tools are missing on every machine that is not an ASUS laptop,
    /// where that is not a problem but an answer.
    readonly property var missingRelevant:
        root.missing.filter(r => r.group !== "rog" || root.isAsus)

    function has(cmd) { return root.present[cmd] === true; }

    /// Ready to paste into a terminal, for whichever helper they have.
    function installCommand(list) {
        const pkgs = (list ?? root.missingRelevant).map(r => r.pkg).join(" ");
        return pkgs.length > 0 ? `paru -S --needed ${pkgs}` : "";
    }

    function refresh() { checkProc.running = true; }
    Component.onCompleted: root.refresh()

    Process {
        id: checkProc
        command: ["bash", "-c",
            "for c in " + root.requirements.map(r => r.cmd).join(" ") + "; do "
            + "command -v \"$c\" >/dev/null 2>&1 && echo \"$c=1\" || echo \"$c=0\"; done; "
            + "grep -qi asus /sys/class/dmi/id/sys_vendor 2>/dev/null "
            + "&& echo '@asus=1' || echo '@asus=0'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = {};
                for (const line of String(text).trim().split("\n")) {
                    const [cmd, ok] = line.split("=");
                    if (cmd === "@asus") root.isAsus = ok === "1";
                    else if (cmd) found[cmd] = ok === "1";
                }
                root.present = found;
                root.checked = true;
            }
        }
    }
}
