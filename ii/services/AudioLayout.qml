pragma Singleton
pragma ComponentBehavior: Bound

// Shared knowledge about audio device SHAPE — channel maps, speaker positions,
// what kind of device something physically is.
//
// This lives in a singleton rather than inside the audio panel because every
// one of these questions comes up in more than one place: the bar indicator
// wants the device icon, the volume mixer wants to know whether a stream is
// stereo, the OSD wants the layout name. Answering them in each file meant
// each file guessed slightly differently.
//
// Import with `qs.services` and call AudioLayout.<fn>(…) — nothing here holds
// state, so it is safe to call from a binding.

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // ── Chassis ─────────────────────────────────────────────────────────
    // "Built-in output" is not one shape. Drawing a clamshell laptop on a
    // detachable tablet is simply wrong artwork, and the speakers are in a
    // different place on each. DMI knows which this is, so ask it rather than
    // assume the common case.
    //   10 Notebook · 30 Tablet · 31 Convertible · 32 Detachable
    property int chassisType: 10
    readonly property bool isTabletChassis:
        root.chassisType === 30 || root.chassisType === 31 || root.chassisType === 32

    FileView {
        path: "file:///sys/class/dmi/id/chassis_type"
        onLoaded: {
            const v = parseInt(String(text()).trim(), 10);
            if (isFinite(v)) root.chassisType = v;
        }
    }

    // ── Speaker positions ───────────────────────────────────────────────
    // Normalised 0..1 coordinates in a top-down room with the listener at the
    // centre. Unknown channels return null rather than a default position: a
    // speaker drawn in the wrong place is worse than one not drawn at all,
    // because the whole point of the diagram is to trust where things are.
    // Quickshell's PwNodeAudio.channels reports SPA channel POSITION CODES —
    // integers, not names. Matching only on strings meant every channel fell
    // through to the default, so the panel showed raw "3" and "4" instead of
    // L and R, and the room view could not place a single speaker. Codes are
    // normalised to names here, once, so nothing downstream has to know.
    readonly property var spaChannelNames: ({
        2: "MONO", 3: "FL", 4: "FR", 5: "FC", 6: "LFE",
        7: "SL", 8: "SR", 12: "RL", 13: "RR"
    })

    function channelName(channel) {
        if (typeof channel === "number" || /^\d+$/.test(String(channel)))
            return root.spaChannelNames[parseInt(channel, 10)] ?? String(channel);
        return String(channel).toUpperCase();
    }

    function positionFor(channel) {
        switch (root.channelName(channel)) {
            case "FL": case "FRONT-LEFT":   return { x: 0.22, y: 0.24, label: "L"   };
            case "FR": case "FRONT-RIGHT":  return { x: 0.78, y: 0.24, label: "R"   };
            case "FC": case "FRONT-CENTER": return { x: 0.50, y: 0.16, label: "C"   };
            case "LFE":                     return { x: 0.50, y: 0.42, label: "LFE" };
            case "SL": case "SIDE-LEFT":    return { x: 0.12, y: 0.55, label: "SL"  };
            case "SR": case "SIDE-RIGHT":   return { x: 0.88, y: 0.55, label: "SR"  };
            case "RL": case "REAR-LEFT":    return { x: 0.24, y: 0.84, label: "RL"  };
            case "RR": case "REAR-RIGHT":   return { x: 0.76, y: 0.84, label: "RR"  };
            case "MONO":                    return { x: 0.50, y: 0.30, label: "M"   };
            default: return null;
        }
    }

    function labelFor(channel) {
        return root.positionFor(channel)?.label ?? root.channelName(channel);
    }

    // "Stereo", "5.1", "7.1" … Counted from the channel map rather than read
    // from a profile name, because a card advertising a 5.1 profile can still
    // be running in stereo.
    function layoutName(channels) {
        const n = (channels ?? []).length;
        if (n === 0) return "—";
        if (n === 1) return "Mono";
        if (n === 2) return "Stereo";
        const hasLfe = channels.some(c => root.channelName(c) === "LFE");
        return (n - (hasLfe ? 1 : 0)) + "." + (hasLfe ? "1" : "0");
    }

    function isStereo(channels) { return (channels ?? []).length === 2; }

    // ── Balance ─────────────────────────────────────────────────────────
    // Derived from the two channel volumes rather than stored separately, so
    // it cannot drift out of sync with what the device is actually doing.
    // -1 is hard left, +1 hard right.
    function balanceOf(volumes) {
        const v = volumes ?? [];
        if (v.length !== 2) return 0;
        const peak = Math.max(v[0] ?? 0, v[1] ?? 0);
        if (peak <= 0) return 0;
        return ((v[1] ?? 0) - (v[0] ?? 0)) / peak;
    }

    // Returns the new volume list; the caller assigns it. Keeping this pure
    // means it can be unit-reasoned about and reused for streams as well as
    // devices.
    function volumesForBalance(volumes, balance) {
        const v = volumes ?? [];
        if (v.length !== 2) return v;
        const peak = Math.max(v[0] ?? 0, v[1] ?? 0);
        return [
            peak * (balance > 0 ? (1 - balance) : 1),
            peak * (balance < 0 ? (1 + balance) : 1)
        ];
    }

    function withChannel(volumes, index, value) {
        const next = [...(volumes ?? [])];
        next[index] = Math.max(0, Math.min(1, value));
        return next;
    }

    // ── Device identity ─────────────────────────────────────────────────
    // What KIND of thing this is, for icon purposes. Matched on the node name
    // as well as the description because the description is a marketing string
    // ("HDB 630") that often names neither the transport nor the form factor.
    function kindOf(node) {
        const p = node?.properties ?? ({});
        // PipeWire and BlueZ publish what the device IS. Prefer that over
        // guessing from the product name — "HDB 630" names neither the
        // transport nor the form factor, and a name-only heuristic classed
        // every USB device as headphones, including USB speakers and DACs.
        const ff = String(p["device.form_factor"] ?? "").toLowerCase();
        const bus = String(p["device.bus"] ?? "").toLowerCase();

        // BlueZ's idea of what the thing IS survives the cable; the bus
        // fallbacks below cannot. This is why a JBL Xtreme drew headphones.
        const byDevice = Devices.audioFormFactorFor(root.productName(node))
                      || Devices.audioFormFactorFor(Audio.friendlyDeviceName(node));
        if (byDevice === "speaker") return "speaker";
        if (byDevice === "headset") return "bluetooth-headset";
        if (byDevice === "headphones") return bus === "bluetooth" ? "bluetooth-headset" : "headphones";
        if (byDevice === "earbuds") return "earbuds";

        if (ff === "headset" || ff === "hands-free") return "bluetooth-headset";
        if (ff === "headphone") return bus === "bluetooth" ? "bluetooth-headset" : "headphones";
        if (ff === "earbud" || ff === "earpiece") return "earbuds";
        if (ff === "speaker") return "speaker";
        if (ff === "internal") return "laptop";
        if (bus === "bluetooth") return "bluetooth-headset";

        // Fall back to the strings only when the metadata says nothing.
        const s = ((node?.name ?? "") + " " + (node?.description ?? "")
                   + " " + (node?.nickname ?? "")).toLowerCase();
        if (s.includes("bluez") || s.includes("bluetooth")) return "bluetooth-headset";
        if (s.includes("hdmi") || s.includes("displayport")) return "hdmi";
        if (s.includes("earbud") || s.includes("airpod") || s.includes("buds")) return "earbuds";
        if (s.includes("headphone") || s.includes("headset") || s.includes("hearing"))
            return "headphones";
        // No "usb -> headphones": a bus says how it is attached, not what it is.
        return "laptop";
    }

    // The model, as the device reports it — "HDB 630" rather than the mangled
    // ALSA node name. Falls back through the fields most likely to be set.
    function productName(node) {
        const p = node?.properties ?? ({});
        return p["device.product.name"] || node?.nickname
            || p["device.description"] || node?.description || "";
    }

    // Vendor, recovered from the bus id when present: the product name usually
    // omits it ("HDB 630" does not say Sennheiser).
    function vendorName(node) {
        const p = node?.properties ?? ({});
        const v = String(p["device.vendor.name"] ?? "");
        if (v.length > 0) return v;
        const id = String(p["device.bus-id"] ?? "");
        const m = id.match(/^usb-([A-Za-z]+(?:_[A-Za-z]+)*)_/);
        return m ? m[1].replace(/_/g, " ") : "";
    }

    // How it is connected, for the subtitle line.
    function transportOf(node) {
        const bus = String(node?.properties?.["device.bus"] ?? "").toLowerCase();
        switch (bus) {
            case "bluetooth": return "Bluetooth";
            case "usb":       return "USB";
            case "pci":       return "Built-in";
            default:          return "";
        }
    }

    // Bespoke SVGs for the two common cases; "" means fall back to a
    // MaterialSymbol, which materialSymbolFor() supplies.
    function iconFor(node) {
        switch (root.kindOf(node)) {
            case "headphones":
            case "bluetooth-headset": return "headphones-symbolic.svg";
            case "earbuds":           return "earbuds-symbolic.svg";
            // Only where the drawing is true: it is a strap-carry capsule, and
            // an Echo Dot is a puck. A wrong picture beats no generic one.
            case "speaker":           return root.isStrapCapsuleSpeaker(node)
                                             ? "speaker-portable-symbolic.svg" : "";
            case "laptop":            return root.isTabletChassis
                                             ? "tablet-audio-symbolic.svg"
                                             : "laptop-audio-symbolic.svg";
            default:                  return "";
        }
    }

    /// Speakers actually shaped like the icon. Matched on the model name: no
    /// metadata describes a silhouette, and BlueZ says "loudspeaker" for a
    /// puck, a boombox and a soundbar alike.
    function isStrapCapsuleSpeaker(node) {
        const n = ((root.productName(node) ?? "") + " "
                 + (node?.description ?? "") + " " + (node?.name ?? "")).toLowerCase();
        if (!n.includes("jbl")) return false;
        return /xtreme|charge|flip|pulse|boombox|go\b|clip/.test(n);
    }

    function materialSymbolFor(node) {
        switch (root.kindOf(node)) {
            case "bluetooth-headset": return "bluetooth";
            case "hdmi":              return "settings_input_hdmi";
            case "headphones":        return "headphones";
            case "earbuds":           return "earbuds";
            default:                  return "speaker";
        }
    }

    // ── Stereo preview glyph ────────────────────────────────────────────
    // For a two-channel device, a picture of the ACTUAL hardware beats an
    // abstract room diagram: headphones are on your head, not placed around
    // you, and a laptop's speakers are in a fixed spot you already know. Both
    // get their glyph drawn large with the two level rings overlaid on the real
    // emitters. Anything else (surround, external speakers, HDMI) keeps the
    // top-down room view, where position is the whole point.
    function hasGlyphPreview(node, channels) {
        if (!root.isStereo(channels)) return false;
        switch (root.kindOf(node)) {
            case "headphones": case "bluetooth-headset":
            case "earbuds": case "laptop": return true;
            default: return false;
        }
    }

    // Preview artwork is SEPARATE from the list icons. The list draws at 20px,
    // the preview at ~150px, and one 24-unit glyph cannot serve both: scaled
    // 6x its strokes become slabs and the shape reads as a blob rather than as
    // a device. These are drawn on a 96 grid for the large size.
    function previewGlyphFor(node) {
        switch (root.kindOf(node)) {
            case "headphones":
            case "bluetooth-headset": return "headphones-preview.svg";
            case "earbuds":           return "earbuds-symbolic.svg";
            case "laptop":            return root.isTabletChassis
                                             ? "tablet-speakers-preview.svg"
                                             : "laptop-speakers-preview.svg";
            default:                  return "";
        }
    }

    // Where the two channels physically come out, as a fraction of the glyph
    // box. These track the SVGs — change one and change the other.
    function glyphChannelSpots(node) {
        switch (root.kindOf(node)) {
            case "headphones":
            case "bluetooth-headset": return { left: 0.190, right: 0.810, y: 0.660 };
            case "earbuds":           return { left: 0.260, right: 0.740, y: 0.315 };
            // A tablet's speakers fire from the SIDES, level with the middle
            // of the screen — not from a deck below it.
            case "laptop":            return root.isTabletChassis
                                             ? { left: 0.115, right: 0.885, y: 0.480 }
                                             : { left: 0.245, right: 0.755, y: 0.688 };
            default:                  return { left: 0.25,  right: 0.75,  y: 0.5   };
        }
    }

    // What the preview is showing, for the caption.
    function previewCaption(node) {
        switch (root.kindOf(node)) {
            case "headphones":
            case "bluetooth-headset":
            case "earbuds": return "Left / right ear";
            case "laptop":  return root.isTabletChassis ? "Side-firing speakers"
                                                        : "Built-in speakers";
            default:        return "";
        }
    }

    // A small badge over the device icon, so a wireless headset is
    // distinguishable from a wired one at a glance rather than only by name.
    function badgeFor(node) {
        switch (root.kindOf(node)) {
            case "bluetooth-headset": return "bluetooth";
            case "hdmi":              return "cable";
            default:                  return "";
        }
    }

    // ── Test tone ───────────────────────────────────────────────────────
    // One sine into one channel, so you can confirm a speaker is alive and on
    // the side you believe it is. `-l 1` stops it after a single pass; without
    // that speaker-test runs until killed.
    function testChannelCommand(channelCount, index) {
        return ["speaker-test", "-c", String(Math.max(1, channelCount)),
                "-t", "sine", "-f", "440", "-l", "1", "-s", String(index + 1)];
    }
}
