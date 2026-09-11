pragma Singleton
pragma ComponentBehavior: Bound

// Real loudness measurement of whatever is currently playing.
//
// Nothing in PipeWire's control API reports level: pactl and the Quickshell
// Pipewire service both expose the volume you SET, not the signal that comes
// out. Answering "how loud is it actually" means reading the samples, so this
// taps the default sink's monitor and runs EBU R128 over it.
//
// LUFS rather than a raw meter on purpose: it is loudness as perceived and as
// standardised for broadcast, so the numbers mean something outside this
// panel. Roughly:
//     -14 LUFS   streaming target (Spotify/YouTube)
//     -23 LUFS   EBU broadcast target
//     below -40  effectively silence
// True peak is reported alongside because loudness and clipping are different
// questions — quiet material can still clip.
//
// Costs about 3% of one core, so it only runs while `active` is set.

import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Gate. Panels set this while a meter is on screen and clear it after.
    property bool active: false

    readonly property string monitorSource:
        (Audio.sink?.name ?? "").length > 0 ? Audio.sink.name + ".monitor" : ""

    // Momentary (400ms window) — the "right now" number.
    property real momentaryLufs: -70
    // Short-term (3s) and integrated (whole session), for context.
    property real shortTermLufs: -70
    property real integratedLufs: -70
    property real loudnessRange: 0
    // Per-channel true peak in dBFS for the current frame, and the running max.
    property var channelPeaks: []
    property var channelTruePeaks: []
    property bool measuring: false

    // -70 LUFS is the floor ffmpeg reports for silence; treat anything at or
    // below it as "nothing playing" rather than as a real reading.
    readonly property bool silent: root.momentaryLufs <= -60

    // ── Peak hold ───────────────────────────────────────────────────────
    // The momentary value moves far too fast to read: by the time your eye
    // reaches the bar the loud part is over. So the peak is caught instantly,
    // held long enough to actually see, then allowed to fall back — the
    // behaviour of a hardware PPM, and the reason every real meter has one.
    property real peakHoldLufs: -70
    property real peakHoldTruePeak: -70
    // True on the tick the peak jumped up. The UI disables its position
    // animation while this is set: easing the RISE would smooth away the
    // transient the marker exists to catch, whereas easing the fall is what
    // makes it readable.
    property bool rising: false
    // Hold for ~1.2s, then decay at 10 dB/s. Slow enough to read, fast enough
    // that the marker still tracks a quietening passage.
    readonly property int holdTicks: 24
    readonly property real decayPerTick: 0.5

    Timer {
        interval: 50
        repeat: true
        running: root.active
        property int heldLufs: 0
        property int heldPeak: 0
        onTriggered: {
            if (root.momentaryLufs >= root.peakHoldLufs) {
                root.rising = true;
                root.peakHoldLufs = root.momentaryLufs;
                root.rising = false;
                heldLufs = 0;
            } else if (heldLufs < root.holdTicks) {
                heldLufs++;
            } else {
                root.peakHoldLufs = Math.max(-70, root.peakHoldLufs - root.decayPerTick);
            }

            // Same hold-then-decay per channel, so each ring keeps its own
            // marker instead of every channel sharing one global peak.
            const holds = [...root.channelHolds];
            for (let i = 0; i < root.channelPeaks.length; ++i) {
                const cur = root.channelPeaks[i];
                const held = holds[i];
                if (held === undefined || !isFinite(held) || cur >= held) holds[i] = cur;
                else holds[i] = Math.max(-70, held - root.decayPerTick);
            }
            holds.length = root.channelPeaks.length;
            root.channelHolds = holds;

            const tp = root.channelTruePeaks.length > 0
                     ? Math.max(...root.channelTruePeaks) : -70;
            if (tp >= root.peakHoldTruePeak) {
                root.peakHoldTruePeak = tp;
                heldPeak = 0;
            } else if (heldPeak < root.holdTicks) {
                heldPeak++;
            } else {
                root.peakHoldTruePeak = Math.max(-70, root.peakHoldTruePeak - root.decayPerTick);
            }
        }
    }

    // 0..1 for a meter bar. -60 LUFS at the bottom, 0 at the top: a linear
    // scale over dB would leave everything audible bunched at the very top.
    function normalized(lufs) {
        return Math.max(0, Math.min(1, (lufs + 60) / 60));
    }

    // Peak of one channel as 0..1, -60..0 dBFS.
    function peakNormalized(index) {
        const p = root.channelPeaks[index];
        if (p === undefined || !isFinite(p)) return 0;
        return Math.max(0, Math.min(1, (p + 60) / 60));
    }

    // Per-channel peak HOLD, on the same 0..1 scale. -1 when there is nothing
    // held, so a caller can hide its marker rather than pin it at the floor.
    property var channelHolds: []
    function channelPeakHoldNormalized(index) {
        const p = root.channelHolds[index];
        if (p === undefined || !isFinite(p) || p <= -60) return -1;
        return Math.max(0, Math.min(1, (p + 60) / 60));
    }

    function reset() {
        root.momentaryLufs = -70;
        root.shortTermLufs = -70;
        root.integratedLufs = -70;
        root.loudnessRange = 0;
        root.channelPeaks = [];
        root.channelTruePeaks = [];
        root.peakHoldLufs = -70;
        root.peakHoldTruePeak = -70;
        root.channelHolds = [];
    }

    Process {
        id: meterProc
        // Restarting on a source change is the point of binding the command to
        // monitorSource: switching headphones mid-measurement would otherwise
        // keep metering a device you are no longer listening to.
        command: ["ffmpeg", "-hide_banner", "-f", "pulse",
                  "-i", root.monitorSource,
                  "-af", "ebur128=peak=true", "-f", "null", "-"]
        running: root.active && root.monitorSource.length > 0
        onRunningChanged: {
            root.measuring = running;
            if (!running) root.reset();
        }
        // ffmpeg writes filter output to stderr, not stdout.
        stderr: SplitParser {
            onRead: line => {
                if (line.indexOf("ebur128") < 0 || line.indexOf("M:") < 0) return;
                // t: 3.99  TARGET:-23 LUFS  M: -29.9 S: -28.3  I: -28.1 LUFS
                //   LRA: 0.5 LU  FTPK: -22.5 -24.6 dBFS  TPK: -12.6 -14.5 dBFS
                const num = (re) => {
                    const m = line.match(re);
                    return m ? parseFloat(m[1]) : NaN;
                };
                const m = num(/M:\s*(-?[0-9.]+|-inf)/);
                if (isFinite(m)) root.momentaryLufs = m;
                const s = num(/S:\s*(-?[0-9.]+)/);
                if (isFinite(s)) root.shortTermLufs = s;
                const i = num(/I:\s*(-?[0-9.]+)/);
                if (isFinite(i)) root.integratedLufs = i;
                const lra = num(/LRA:\s*(-?[0-9.]+)/);
                if (isFinite(lra)) root.loudnessRange = lra;

                // FTPK/TPK carry one figure per channel, so the count follows
                // the device rather than being assumed to be two.
                const ftpk = line.match(/FTPK:\s*([-0-9.\s]+?)\s*dBFS/);
                if (ftpk) {
                    root.channelPeaks = ftpk[1].trim().split(/\s+/)
                        .map(parseFloat).filter(isFinite);
                }
                const tpk = line.match(/TPK:\s*([-0-9.\s]+?)\s*dBFS/);
                if (tpk) {
                    root.channelTruePeaks = tpk[1].trim().split(/\s+/)
                        .map(parseFloat).filter(isFinite);
                }
            }
        }
    }
}
