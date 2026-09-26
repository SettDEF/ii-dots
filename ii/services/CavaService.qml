pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    property list<real> visualizerPoints: []

    // The bar and desktop spectrums live on screen rather than in a popup, so
    // they need the feed while anything plays. Gated on their switches, so
    // both off never spawns cava.
    readonly property bool visualizerWants: MprisController.anyPlaying
        && ((Config.options?.bar?.showVisualizer ?? false)
            || (Config.options?.background?.widgets?.visualizer?.enable ?? false))

    readonly property bool active: GlobalStates.mediaControlsOpen
        || GlobalStates.cornerPopupOpen
        || (!GameMode.active && (ShelfPlayer.isPlaying || visualizerWants))

    Process {
        id: cavaProc
        running: root.active
        command: ["cava", "-p", FileUtils.trimFileProtocol(Directories.scriptPath) + "/cava/raw_output_config.txt"]
        stdout: SplitParser {
            onRead: data => {
                const points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p))
                root.visualizerPoints = points
            }
        }
        onRunningChanged: if (!running) root.visualizerPoints = []
    }
}
