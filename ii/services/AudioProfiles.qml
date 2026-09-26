pragma Singleton
pragma ComponentBehavior: Bound

// Card PROFILES — which set of inputs and outputs a sound card exposes.
//
// A PipeWire node is one endpoint; the card behind it decides which endpoints
// exist at all. That distinction is invisible in the mixer and it is exactly
// what bit this machine: a USB headset's microphone and its high-quality
// playback are mutually exclusive in firmware, so the profile that turns the
// mic on is the profile that makes music sound bad. Nothing in the audio panel
// could say so, because nothing in the config read profiles.
//
// So this answers two questions the panel needs:
//   - does this output ALSO carry a microphone right now?
//   - is there a counterpart profile that differs only by that microphone?
//
// The second is what makes a toggle honest. Turning the mic off is not a mute:
// it removes the capture endpoint from the graph, so no application can open it
// at all, and the card is free to use its good playback mode.
//
// Import with `qs.services`.

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root

    /// deviceId -> { id, name, description, current, profiles: [...] }
    property var devices: ({})
    property bool loaded: false
    property bool busy: false

    /// Bumped on every successful read. Bindings that want to recompute when
    /// profiles change depend on this rather than on `devices`, whose identity
    /// changes are easy to miss when only a nested field moved.
    property int revision: 0

    // ── reading ─────────────────────────────────────────────────────────
    function refresh() {
        if (root.busy) return
        root.busy = true
        dump.running = true
    }

    Process {
        id: dump
        command: ["pw-dump"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false
                let parsed
                try {
                    parsed = JSON.parse(text)
                } catch (e) {
                    // A truncated or empty dump is a transient failure, not a
                    // reason to throw away the profiles we already know.
                    console.log("[AudioProfiles] could not parse pw-dump:", e)
                    return
                }
                const next = ({})
                for (const o of parsed) {
                    if (o?.type !== "PipeWire:Interface:Device") continue
                    const props = o?.info?.props ?? ({})
                    const enumerated = o?.info?.params?.EnumProfile
                    if (!Array.isArray(enumerated)) continue

                    const profiles = enumerated.map(p => {
                        // `classes` is a SPA struct, not a plain list: the first
                        // element is a count and each entry after it starts with
                        // the media class it describes. Scanning for the string
                        // is what survives that shape without decoding it.
                        const flat = JSON.stringify(p?.classes ?? [])
                        return {
                            index: p?.index ?? -1,
                            name: String(p?.name ?? ""),
                            description: String(p?.description ?? ""),
                            // "unknown" means the card did not say, which is the
                            // normal answer for USB — only "no" is a refusal.
                            available: String(p?.available ?? "unknown") !== "no",
                            hasSource: flat.includes("Audio/Source"),
                            hasSink: flat.includes("Audio/Sink"),
                        }
                    }).filter(p => p.index >= 0 && p.name.length > 0)

                    const cur = o?.info?.params?.Profile?.[0] ?? null
                    next[String(o.id)] = {
                        id: o.id,
                        // `device.name` survives a replug and a card
                        // renumbering; `alsa.card` does not, which is exactly
                        // why anything addressing ALSA has to read it fresh
                        // rather than remember it.
                        name: String(props["device.name"] ?? ""),
                        alsaCard: props["alsa.card"] ?? null,
                        description: String(props["device.description"] ?? ""),
                        current: cur ? { index: cur.index ?? -1, name: String(cur.name ?? "") } : null,
                        profiles: profiles,
                        // What this card is PHYSICALLY capable of, across all
                        // its profiles — not what the current one happens to
                        // expose. A microphone has no output in any profile, so
                        // offering it an output setting is just a dead control.
                        canOutput: profiles.some(p => p.hasSink),
                        canInput: profiles.some(p => p.hasSource),
                    }
                }
                root.devices = next
                root.loaded = true
                root.revision = root.revision + 1
            }
        }
    }

    // ── finding the card behind a node ──────────────────────────────────
    /// `device.id` is the authoritative link, but node properties are empty
    /// until something tracks the node, so fall back to the description: a
    /// card called "HDB 630" backs the node called "HDB 630 Analog Stereo".
    function deviceFor(node) {
        if (!node) return null
        const byId = node?.properties?.["device.id"]
        if (byId !== undefined && byId !== null) {
            const hit = root.devices[String(byId)]
            if (hit) return hit
        }
        const desc = String(node?.description ?? "")
        if (desc.length === 0) return null
        let best = null
        for (const k in root.devices) {
            const d = root.devices[k]
            if (d.description.length === 0) continue
            if (desc === d.description || desc.startsWith(d.description + " ")) {
                // Longest match wins, so "HDB 630" never beats a card whose
                // description is a longer prefix of the same node.
                if (!best || d.description.length > best.description.length) best = d
            }
        }
        return best
    }

    /// True when this node's card is a real piece of hardware rather than a
    /// virtual sink (an equalizer chain, a loopback, an app's own null sink).
    function isHardware(node) { return root.deviceFor(node) !== null }

    // ── the microphone counterpart ──────────────────────────────────────
    /// PulseAudio names combined profiles "<output>+input:<something>", so the
    /// mic-off counterpart of a profile is its name with that suffix removed,
    /// and the mic-on counterpart is any profile that adds one. Splitting on
    /// the marker means this works for every card that follows the convention
    /// instead of only for the headset that prompted it.
    function micPairFor(node) {
        const dev = root.deviceFor(node)
        if (!dev?.current) return null
        const cur = dev.current.name
        const marker = "+input:"
        const at = cur.indexOf(marker)
        const base = at >= 0 ? cur.slice(0, at) : cur
        if (base.length === 0) return null

        const off = dev.profiles.find(p => p.name === base && p.available)
        const on = dev.profiles.find(p => p.name.startsWith(base + marker)
                                       && p.hasSource && p.available)
        if (!off || !on) return null
        return {
            deviceId: dev.id,
            deviceName: dev.description,
            enabled: at >= 0,
            onIndex: on.index,
            offIndex: off.index,
            onName: on.name,
            offName: off.name,
        }
    }

    /// Does this output also expose a microphone right now?
    function micEnabled(node) { return root.micPairFor(node)?.enabled ?? false }

    /// Can the microphone be turned off without losing the output?
    function canToggleMic(node) { return root.micPairFor(node) !== null }

    function setMicEnabled(node, on) {
        const pair = root.micPairFor(node)
        if (!pair || pair.enabled === on) return false
        switcher.command = ["wpctl", "set-profile", String(pair.deviceId),
                            String(on ? pair.onIndex : pair.offIndex)]
        switcher.running = true
        return true
    }

    Process {
        id: switcher
        // The card re-enumerates its endpoints after a profile change, so the
        // dump is only truthful once that has settled. Re-reading immediately
        // reported the OLD profile and left the toggle looking stuck.
        onExited: settle.restart()
    }

    Timer {
        id: settle
        interval: 600
        onTriggered: root.refresh()
    }

    // Re-read when the set of DEVICES changes — not when the node graph does.
    //
    // Watching `Pipewire.nodes` looked equivalent and was not: every stream
    // starting or stopping is a node change, so with a DAW open this re-ran
    // `pw-dump` and re-parsed a large JSON document every 600 ms forever, and
    // the whole shell felt it. Device count only moves when hardware actually
    // comes or goes, which is the thing we care about.
    readonly property int _deviceCount: (Audio.outputDevices?.length ?? 0)
                                      + (Audio.inputDevices?.length ?? 0)
    on_DeviceCountChanged: settle.restart()

    Component.onCompleted: root.refresh()
}
