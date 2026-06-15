pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs

Singleton {
    id: root

    property string currentPath: ""
    property bool isPlaying: false

    Process {
        id: playProc
        onRunningChanged: if (!running) { root.isPlaying = false; root.currentPath = "" }
    }

    // Sync stop state when MPRIS player is paused/stopped externally (corner popup controls)
    Connections {
        target: MprisController.activePlayer ?? null
        function onPlaybackStateChanged() {
            const state = MprisController.activePlayer?.playbackState
            if (root.isPlaying && state !== MprisPlaybackState.Playing) {
                root.isPlaying = false
            }
        }
    }

    function play(path) {
        if (playProc.running) playProc.kill()
        root.currentPath = path
        root.isPlaying = true
        GlobalStates.cornerPopupOpen = true
        // --no-terminal keeps mpris.lua active; title shown in MPRIS identity
        playProc.exec({ command: ["mpv", "--no-video", "--no-terminal", "--title=qs-shelf", path] })
    }

    function stop() {
        if (playProc.running) playProc.kill()
        root.isPlaying = false
        root.currentPath = ""
    }

    function toggle(path) {
        if (root.isPlaying && root.currentPath === path) stop()
        else play(path)
    }
}
