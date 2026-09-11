pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Records what is coming out of the speakers.
 *
 * Taps the default sink's monitor, the same source AudioMeter measures, so it
 * captures the mix exactly as heard — every app, post-volume — rather than any
 * single stream.
 *
 * A singleton on purpose: the keybind has to work while the Audio panel is
 * closed, and the panel is unloaded when it is.
 */
Singleton {
    id: root

    property bool recording: false
    property string outputPath: ""
    property string lastError: ""

    readonly property string monitorSource:
        (Audio.sink?.name ?? "").length > 0 ? Audio.sink.name + ".monitor" : ""

    // XDG Music is the right home for these, but only when it is actually
    // reachable: here it is a symlink into an unmounted drive, and ffmpeg
    // writing there would hang for the full autofs timeout. Probed once,
    // capped, and never on the UI thread; ~/Recordings is the fallback.
    property bool musicUsable: false
    readonly property string musicDir: FileUtils.trimFileProtocol(Directories.music)
    readonly property string directory: root.musicUsable
        ? root.musicDir
        : FileUtils.trimFileProtocol(Directories.home) + "/Recordings"

    Process {
        id: musicProbe
        running: true
        // -w, not just -d: a directory we cannot write to is no more useful
        // than one that is not there.
        command: ["bash", "-c",
            `timeout 1 test -d '${root.musicDir.replace(/'/g, "'\\''")}' && ` +
            `timeout 1 test -w '${root.musicDir.replace(/'/g, "'\\''")}' && echo ok`]
        stdout: StdioCollector {
            onStreamFinished: root.musicUsable = this.text.trim() === "ok"
        }
    }

    property double startedAt: 0
    property int elapsed: 0

    // A binding on Date.now() would never re-evaluate; the tick is what makes
    // the panel's timer move.
    Timer {
        running: root.recording
        interval: 1000
        repeat: true
        onTriggered: root.elapsed = Math.floor((Date.now() - root.startedAt) / 1000)
    }

    function formatElapsed() {
        const s = root.elapsed;
        const mm = String(Math.floor(s / 60)).padStart(2, "0");
        const ss = String(s % 60).padStart(2, "0");
        return `${mm}:${ss}`;
    }

    function _stamp() {
        const d = new Date();
        const p = n => String(n).padStart(2, "0");
        return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}` +
               `_${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
    }

    function start() {
        if (root.recording)
            return;
        if (root.monitorSource.length === 0) {
            root.lastError = Translation.tr("No output device");
            return;
        }
        root.lastError = "";
        const dir = root.directory;
        root.outputPath = `${dir}/recording-${root._stamp()}.flac`;
        root.startedAt = Date.now();
        root.elapsed = 0;
        // exec, so the signal on stop reaches ffmpeg itself rather than the
        // wrapping shell — ffmpeg finalises the file on SIGTERM, and a killed
        // shell would leave it unfinalised.
        recordProc.command = ["bash", "-c",
            `mkdir -p '${dir.replace(/'/g, "'\\''")}' && ` +
            `exec ffmpeg -hide_banner -nostdin -loglevel error ` +
            `-f pulse -i '${root.monitorSource.replace(/'/g, "'\\''")}' ` +
            `-c:a flac '${root.outputPath.replace(/'/g, "'\\''")}'`];
        recordProc.running = true;
        root.recording = true;
    }

    function stop() {
        if (!root.recording)
            return;
        recordProc.running = false;   // SIGTERM; ffmpeg writes the trailer
        root.recording = false;
    }

    function toggle() {
        if (root.recording)
            root.stop();
        else
            root.start();
    }

    Process {
        id: recordProc
        stderr: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                if (text.length > 0)
                    root.lastError = text.split("\n").pop();
            }
        }
        onExited: (code) => {
            // Non-zero with no message still needs surfacing, or a failed
            // recording looks identical to a successful one.
            if (code !== 0 && code !== 255 && root.lastError.length === 0)
                root.lastError = Translation.tr("Recorder exited with code %1").arg(code);
            root.recording = false;
        }
    }
}
