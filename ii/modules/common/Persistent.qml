pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property alias states: persistentStatesJsonAdapter
    property string fileDir: Directories.state
    property string fileName: "states.json"
    property string filePath: `${root.fileDir}/${root.fileName}`

    property bool ready: false
    property string previousHyprlandInstanceSignature: ""
    property bool isNewHyprlandInstance: previousHyprlandInstanceSignature !== states.hyprlandInstanceSignature

    onReadyChanged: {
        root.previousHyprlandInstanceSignature = root.states.hyprlandInstanceSignature
        root.states.hyprlandInstanceSignature = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    }

    Timer {
        id: fileReloadTimer
        interval: 100
        repeat: false
        onTriggered: {
            persistentStatesFileView.reload()
        }
    }

    Timer {
        id: fileWriteTimer
        interval: 100
        repeat: false
        onTriggered: {
            persistentStatesFileView.writeAdapter()
        }
    }

    FileView {
        id: persistentStatesFileView
        path: root.filePath

        watchChanges: true
        onFileChanged: fileReloadTimer.restart()
        onAdapterUpdated: fileWriteTimer.restart()
        onLoaded: root.ready = true
        onLoadFailed: error => {
            console.log("Failed to load persistent states file:", error);
            if (error == FileViewError.FileNotFound) {
                fileWriteTimer.restart();
            }
        }

        adapter: JsonAdapter {
            id: persistentStatesJsonAdapter

            property string hyprlandInstanceSignature: ""

            property JsonObject devices: JsonObject {
                // Per-device rules, applied when the device appears.
                //
                // Keyed by the PipeWire CARD NAME (`alsa_card.usb-Roland_DJ-808-01`)
                // because that is the only identifier that survives a replug:
                // the ALSA index renumbers, and the node id is new every time.
                //
                // A JSON string rather than nested JsonObjects — JsonObject has
                // no dynamic keys, the same reason `draw.customPalettes` and
                // `cheatsheet.mdScrollMap` are strings.
                property string rules: "{}"
            }

            property JsonObject ai: JsonObject {
                property string model: "gemini-2.5-flash"
                property real temperature: 0.5
            }

            property JsonObject draw: JsonObject {
                // JSON-encoded [{id, name, colors[]}], same reason as
                // mdScrollMap: JsonObject doesn't take list properties.
                property string customPalettes: "[]"
                property string activePalette: "studio"
                // Colours mixed by hand, most recent first. Same JSON-in-a-
                // string reason as customPalettes.
                property string recentColors: "[]"
            }

            property JsonObject cheatsheet: JsonObject {
                property int tabIndex: 0
                // Markdown viewer state ─────────────────────────────────
                property string mdActivePath: ""
                property string mdRootPath: ""
                // JSON-encoded { "<file path>": contentY } so each
                // cheatsheet remembers its own scroll position across
                // panel close → reopen cycles. Stored as a string because
                // JsonObject doesn't take dynamic keys.
                property string mdScrollMap: "{}"
            }

            // skwd wallpaper picker — restored when the Loader re-
            // instantiates SkwdWallContent on reopen, so the source tab,
            // query, carousel position, and per-sub Reddit pagination
            // counter all survive close → open.
            property JsonObject skwd: JsonObject {
                property string activeSource: "local"
                property string activeMediaType: "all"
                property string query: ""
                property int activeIndex: 0
                // Focused wallpaper by path; the index drifts as items arrive.
                property string activePath: ""
                property real lastPrune: 0
                // JSON-encoded { "subreddit": pageNumber }. String for the
                // same dynamic-key reason as mdScrollMap above.
                property string redditPageMap: "{}"
                // Forced Reddit listing sort from the filter chips.
                // "" = AUTO (advance through the sorts as each dries up).
                property string forcedSort: ""
                // JSON array of favourited wallpaper paths.
                property string favorites: "[]"
                property string whFilters: "{}"
                property int rotateMinutes: 0
                property string rotateFrom: "favorites"   // favorites | folder
                property string rotateHistory: "[]"
            }

            // Native wallpaper selector (file-picker) filter state.
            property JsonObject wallpaperPicker: JsonObject {
                property string typeFilter:  "all"      // all | pic | vid
                property string sortMode:    "newest"   // newest | oldest | az | za | largest | smallest
                property string orientation: "all"      // all | landscape | portrait | square
            }

            property JsonObject sidebar: JsonObject {
                property JsonObject bottomGroup: JsonObject {
                    property bool collapsed: false
                    property int tab: 0
                }
            }

            property JsonObject dock: JsonObject {
                // Which edit-panel tab you were last on. Reopening on
                // Behaviour every time is a step backwards from a panel you
                // visit repeatedly while tuning one thing.
                property int editTab: 0
            }

            property JsonObject booru: JsonObject {
                property bool allowNsfw: false
                property string provider: "yandere"
            }

            property JsonObject idle: JsonObject {
                property bool inhibit: false
            }

            property JsonObject audio: JsonObject {
                // appKey -> volume (0..1) for apps that are open but not
                // currently streaming. JSON-encoded because JsonObject cannot
                // hold dynamic keys. Applied to the app's stream as soon as
                // one appears.
                property string appVolumes: "{}"
            }

            property JsonObject mic: JsonObject {
                // The hardware capture gain the user chose, in dB.
                //
                // Persisted because ALSA will not do it for us: mixer values live
                // in the driver, and every replug, USB reset, card renumbering or
                // profile switch drops them back to the factory value — 60 dB, i.e.
                // maximum, on the NT1. Mic.qml re-applies this whenever the device
                // reappears, which is the only way the setting survives at all.
                property real gainDb: 20

                // Which input to control, by PipeWire node name. Empty follows
                // the system default — a bad default here, since that is a
                // global setting other apps change, and it was observed pointing
                // at a muted onboard input while the real mic sat unused.
                property string preferredSource: ""

                property bool noiseSuppression: false
                property real vadThreshold: 74
                property bool echoCancel: false
                property bool highPass: false
                property real highPassHz: 80
            }

            property JsonObject lid: JsonObject {
                property bool enabled: false   // react to lid close (clamshell / suspend)
            }

            property JsonObject gameMode: JsonObject {
                property bool manual: false
                property bool auto: true
                property string saved: "{}"   // Hyprland values to put back
            }

            property JsonObject rog: JsonObject {
                property int watts: 35
                property string activePreset: "Balanced"
                property string curve: "[]"     // JSON of the live fan pwmValues[8]
                // JSON array of { name, watts, pwms[8], temps[8] } custom presets.
                // Stored as a STRING (not nested JsonObjects/`property var`) to dodge
                // the JsonAdapter reload segfault — see Config.qml playerColors.
                property string presets: "[]"
                property string chargerProfile: "Performance"   // the most the charger may use
            }

            property JsonObject touchpad: JsonObject {
                property bool hasCustomPos: false
                property real x: 0
                property real y: 0
            }

            property JsonObject osk: JsonObject {
                property bool hasCustomPos: false
                property real x: 0
                property real y: 0
            }

            property JsonObject overlay: JsonObject {
                property list<string> open: ["crosshair", "recorder", "volumeMixer", "resources"]
                property JsonObject crosshair: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property real x: 827
                    property real y: 441
                    property real width: 250
                    property real height: 100
                }
                property JsonObject floatingImage: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 1650
                    property real y: 390
                    property real width: 0
                    property real height: 0
                }
                property JsonObject fpsLimiter: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 1570
                    property real y: 615
                    property real width: 280
                    property real height: 80
                }
                property JsonObject recorder: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 80
                    property real y: 80
                    property real width: 350
                    property real height: 130
                }
                property JsonObject resources: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property real x: 1500
                    property real y: 770
                    property real width: 350
                    property real height: 200
                    property int tabIndex: 0
                }
                property JsonObject volumeMixer: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 80
                    property real y: 280
                    property real width: 350
                    property real height: 600
                    property int tabIndex: 0
                }
                property JsonObject notes: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property real x: 1400
                    property real y: 42
                    property real width: 460
                    property real height: 330
                }
            }

            property JsonObject bar: JsonObject {
                // JSON-encoded { "<appId>": ["actionId", ...] } — which three
                // quick actions each application shows under the window pill.
                // A string rather than a JsonObject for the same reason as
                // mdScrollMap above: the keys are app ids, so they are dynamic.
                property string windowActionMap: "{}"
            }

            property JsonObject timer: JsonObject {
                property JsonObject pomodoro: JsonObject {
                    property bool running: false
                    property int start: 0
                    property bool isBreak: false
                    property int cycle: 0
                }
                property JsonObject stopwatch: JsonObject {
                    property bool running: false
                    property int start: 0
                    property list<var> laps: []
                }
                property JsonObject countdown: JsonObject {
                    property bool running: false
                    // Unix seconds the countdown ends at, so it stays correct
                    // across a reload rather than restarting from the remainder.
                    property int endsAt: 0
                    property int duration: 300
                }
            }
        }
    }
}
