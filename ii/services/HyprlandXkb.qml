pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common

/**
 * Exposes the active Hyprland Xkb keyboard layout name and code for indicators.
 */
Singleton {
    id: root
    // You can read these
    property list<string> layoutCodes: []
    property var cachedLayoutCodes: ({})
    property string currentLayoutName: ""
    property string currentLayoutCode: ""
    /**
     * Name of the keyboard that most recently produced a layout event.
     *
     * With several keyboards attached (laptop, external, Bluetooth) each holds
     * its OWN active layout, so "the current layout" is only meaningful per
     * device. Hyprland's `activelayout` event carries "KEYBOARD_NAME,LAYOUT",
     * and the old code discarded the keyboard half and always fell back to
     * whichever device is flagged `main` — so the reported layout could belong
     * to a keyboard you were not typing on.
     *
     * Caveat: Hyprland emits no per-keystroke device event, so this tracks the
     * last keyboard to CHANGE layout, not literally the last key pressed. That
     * is still input-driven (a layout switch is a keypress on that device), but
     * typing on a second keyboard without switching layout cannot be observed.
     */
    property string lastKeyboardName: ""
    // For the service
    property var baseLayoutFilePath: "/usr/share/X11/xkb/rules/base.lst"
    property bool needsLayoutRefresh: false

    // Update the layout code according to the layout name (Hyprland gives the name not the code)
    onCurrentLayoutNameChanged: root.updateLayoutCode()
    function updateLayoutCode() {
        if (cachedLayoutCodes.hasOwnProperty(currentLayoutName)) {
            root.currentLayoutCode = cachedLayoutCodes[currentLayoutName];
        } else {
            getLayoutProc.running = true;
        }
    }

    // Get the layout code from the base.lst file by grabbing the line with the current layout name
    Process {
        id: getLayoutProc
        command: ["cat", root.baseLayoutFilePath]

        stdout: StdioCollector {
            id: layoutCollector

            onStreamFinished: {
                const lines = layoutCollector.text.split("\n");
                const targetDescription = root.currentLayoutName;
                const foundLine = lines.find(line => {
                    // Skip comment lines and empty lines
                    if (!line.trim() || line.trim().startsWith('!'))
                        return false;

                    // Match layout: (whitespace + ) key + whitespace + description
                    const matchLayout = line.match(/^\s*(\S+)\s+(.+)$/);
                    if (matchLayout && matchLayout[2] === targetDescription) {
                        root.cachedLayoutCodes[matchLayout[2]] = matchLayout[1];
                        root.currentLayoutCode = matchLayout[1];
                        return true;
                    }

                    // Match variant: (whitespace + ) variant + whitespace + key + whitespace + description
                    const matchVariant = line.match(/^\s*(\S+)\s+(\S+)\s+(.+)$/);
                    if (matchVariant && matchVariant[3] === targetDescription) {
                        const complexLayout = matchVariant[2] + matchVariant[1];
                        root.cachedLayoutCodes[matchVariant[3]] = complexLayout;
                        root.currentLayoutCode = complexLayout;
                        return true;
                    }
                    
                    return false;
                });
                // console.log("[HyprlandXkb] Found line:", foundLine);
                // console.log("[HyprlandXkb] Layout:", root.currentLayoutName, "| Code:", root.currentLayoutCode);
                // console.log("[HyprlandXkb] Cached layout codes:", JSON.stringify(root.cachedLayoutCodes, null, 2));
            }
        }
    }

    // Find out available layouts and current active layout. Should only be necessary on init
    Process {
        id: fetchLayoutsProc
        running: true
        command: ["hyprctl", "-j", "devices"]

        stdout: StdioCollector {
            id: devicesCollector
            onStreamFinished: {
                let parsedOutput;
                try { parsedOutput = JSON.parse(devicesCollector.text); }
                catch (e) { return; }
                const keyboards = parsedOutput["keyboards"] ?? [];
                if (keyboards.length === 0) return;
                // Prefer the keyboard actually being used over the `main` flag;
                // fall back to `main`, then to whatever exists.
                const hyprlandKeyboard =
                    (root.lastKeyboardName
                        ? keyboards.find(kb => kb.name === root.lastKeyboardName) : null)
                    ?? keyboards.find(kb => kb.main === true)
                    ?? keyboards[0];
                if (!hyprlandKeyboard) return;
                root.layoutCodes = (hyprlandKeyboard["layout"] ?? "us").split(",");
                root.currentLayoutName = hyprlandKeyboard["active_keymap"] ?? "";
                // console.log("[HyprlandXkb] Fetched | Layouts (multiple: " + (root.layoutCodes.length > 1) + "): "
                //     + root.layoutCodes.join(", ") + " | Active: " + root.currentLayoutName);
            }
        }
    }

    // Update the layout name when it changes
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") {
                // "KEYBOARD_NAME,LAYOUT_NAME" — both halves matter: the layout
                // is per-device, so we record which device this one belongs to.
                const dataString = event.data ?? "";
                const sep = dataString.indexOf(",");
                if (sep >= 0) {
                    root.lastKeyboardName = dataString.substring(0, sep);
                    root.currentLayoutName = dataString.substring(sep + 1);
                }

                if (root.needsLayoutRefresh) {
                    root.needsLayoutRefresh = false;
                    fetchLayoutsProc.running = true;
                }

                // NOTE: there used to be an early `return` here when only one
                // layout was configured, on the assumption that the layout then
                // never changes. But this handler is also what tells the OSK
                // which keymap to DRAW, and that still has to be resolved on a
                // single-layout setup — so bailing out left the on-screen keys
                // stuck on the default forever.
                //
                // The OSK layout is no longer written into Config from here
                // either. Deriving a value and persisting it into the user's
                // config meant a bad derivation (see below) got saved to disk:
                // `currentLayoutName.split(" (")[0]` turned "English (US)" into
                // "English", which is not a valid drawn-layout key. OskContent
                // now resolves this live instead.
            } else if (event.name == "configreloaded") {
                // Mark layout code list to be updated when config is reloaded
                root.needsLayoutRefresh = true;
            }
        }
    }
}
