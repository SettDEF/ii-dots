pragma Singleton
pragma ComponentBehavior: Bound

// Live captions — what is being SAID on an audio node, written on screen.
//
// THE POINT
//   Voice chat is the one thing on a desktop you cannot scroll back, pause, or
//   re-read. In VRChat half the room is speaking a language you do not have,
//   over game audio, at whatever volume their mic happens to be — and if you
//   miss it, it is gone. This turns that stream into text you can actually
//   look at.
//
// WHERE THE AUDIO GOES
//   Nowhere. Transcription runs locally (whisper.cpp) against a chunk of the
//   node's monitor. Only when you pick a target language other than English
//   does any TEXT go to a translator, and never the recording. The voices being
//   captioned belong to other people, so that boundary is deliberate and worth
//   keeping.
//
// WHAT IT LISTENS TO
//   Any node's monitor. For a game that means the sink it plays through, so the
//   captions cover everything you hear — voices and game audio together. There
//   is no speaker separation here and this does not pretend otherwise.
//
// Import with `qs.services`.

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    /// Touch from a Scope so the service exists before its UI does.
    readonly property bool ready: true

    property bool active: false
    /// Node to listen to. Empty means "whatever the current output is".
    property string target: ""
    property string model: `${Quickshell.env("HOME")}/.local/share/whisper/ggml-base.bin`
    property int chunkSeconds: 5
    /// "" = transcribe as spoken. "English" is handled by whisper itself,
    /// offline; anything else goes through the translator.
    property string translateTo: ""
    property string language: "auto"

    /// Newest last. Capped — this is a caption strip, not a transcript archive.
    property var lines: []
    property string lastError: ""
    readonly property bool engineMissing: root.lastError.indexOf("whisper") >= 0
                                       || root.lastError.indexOf("model") >= 0

    readonly property string effectiveTarget:
        root.target.length > 0 ? root.target
                               : (Audio.sink?.name ? Audio.sink.name + ".monitor" : "")

    function clear() { root.lines = [] }
    function toggle() { root.active = !root.active }

    function _push(entry) {
        const next = root.lines.slice()
        next.push(entry)
        root.lines = next.slice(-40)
    }

    Process {
        id: proc
        running: root.active && root.effectiveTarget.length > 0
        command: {
            const a = [`${Quickshell.env("HOME")}/.config/quickshell/ii/scripts/captions/captions.sh`,
                       "--target", root.effectiveTarget,
                       "--model", root.model,
                       "--chunk", String(root.chunkSeconds),
                       "--lang", root.language]
            if (root.translateTo.length > 0) { a.push("--translate-to"); a.push(root.translateTo) }
            return a
        }
        stdout: SplitParser {
            // One JSON object per line, so a partial read can never be mistaken
            // for a caption.
            onRead: line => {
                const s = String(line).trim()
                if (s.length === 0) return
                let o
                try { o = JSON.parse(s) } catch (e) { return }
                if (o.error) { root.lastError = String(o.error); root.active = false; return }
                if (!o.text) return
                root.lastError = ""
                root._push({ at: o.t, text: String(o.text),
                             translation: String(o.translation ?? "") })
            }
        }
        onExited: (code) => {
            // Exiting on its own means the pipeline failed; without this the
            // toggle stays lit over something that stopped working.
            if (root.active && code !== 0) root.active = false
        }
    }
}
