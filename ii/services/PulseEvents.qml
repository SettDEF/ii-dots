pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * One `pactl subscribe` for the whole shell: what changed in the audio server, as signals, so
 * the parts that show audio state rescan when it changes instead of polling pactl on a timer.
 *   sinkInput:    a playing stream (an app's output) came, went or changed (mute, volume)
 *   sourceOutput: a recording stream (an app using a mic) came, went or changed
 */
Singleton {
    id: root

    signal sinkInput()
    signal sourceOutput()

    Process {
        id: events
        running: true
        command: ["pactl", "subscribe"]
        stdout: SplitParser {
            onRead: line => {
                if (line.includes("sink-input")) root.sinkInput();
                else if (line.includes("source-output")) root.sourceOutput();
            }
        }
        // the audio server restarted: listen again, and tell everyone to rescan
        onExited: restart.restart()
    }
    Timer {
        id: restart
        interval: 3000
        onTriggered: {
            events.running = true;
            root.sinkInput();
            root.sourceOutput();
        }
    }
}
