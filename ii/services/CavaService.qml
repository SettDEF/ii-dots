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

    readonly property bool active: GlobalStates.mediaControlsOpen
        || GlobalStates.cornerPopupOpen
        || ShelfPlayer.isPlaying

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
