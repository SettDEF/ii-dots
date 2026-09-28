pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common.functions

Singleton {
    id: root
    property string filePath: Directories.shellConfigPath
    property alias options: configOptionsJsonAdapter
    property bool ready: false
    property int readWriteDelay: 50 // milliseconds
    property bool blockWrites: false

    function setNestedValue(nestedKey, value) {
        let keys = nestedKey.split(".");
        let obj = root.options;
        let parents = [obj];

        // Traverse and collect parent objects
        for (let i = 0; i < keys.length - 1; ++i) {
            if (!obj[keys[i]] || typeof obj[keys[i]] !== "object") {
                obj[keys[i]] = {};
            }
            obj = obj[keys[i]];
            parents.push(obj);
        }

        // Convert value to correct type using JSON.parse when safe
        let convertedValue = value;
        if (typeof value === "string") {
            let trimmed = value.trim();
            if (trimmed === "true" || trimmed === "false" || !isNaN(Number(trimmed))) {
                try {
                    convertedValue = JSON.parse(trimmed);
                } catch (e) {
                    convertedValue = value;
                }
            }
        }

        obj[keys[keys.length - 1]] = convertedValue;
    }

    Timer {
        id: fileReloadTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            configFileView.reload()
        }
    }

    Timer {
        id: fileWriteTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            configFileView.writeAdapter()
        }
    }

    FileView {
        id: configFileView
        path: root.filePath
        watchChanges: true
        blockWrites: root.blockWrites
        onFileChanged: fileReloadTimer.restart()
        onAdapterUpdated: fileWriteTimer.restart()
        onLoaded: root.ready = true
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) {
                writeAdapter();
            }
        }

        JsonAdapter {
            id: configOptionsJsonAdapter

            property string panelFamily: "ii" // "ii", "waffle"
            // Tablet mode: bigger bar, auto-OSK in launcher, touch-friendly hit targets.
            property bool tabletMode: false

            // Email widget — URL opened by the inbox quicktoggle.
            property JsonObject email: JsonObject {
                property string openUrl: "https://mail.google.com"
            }

            property JsonObject policies: JsonObject {
                property int ai: 1 // 0: No | 1: Yes | 2: Local
                property int weeb: 1 // 0: No | 1: Open | 2: Closet
            }

            property JsonObject ai: JsonObject {
                property string systemPrompt: "## Style\n- Use casual tone, don't be formal! Make sure you answer precisely without hallucination and prefer bullet points over walls of text. You can have a friendly greeting at the beginning of the conversation, but don't repeat the user's question\n\n## Context (ignore when irrelevant)\n- You are a helpful and inspiring sidebar assistant on a {DISTRO} Linux system\n- Desktop environment: {DE}\n- Current date & time: {DATETIME}\n- Focused app: {WINDOWCLASS}\n\n## Presentation\n- Use Markdown features in your response: \n  - **Bold** text to **highlight keywords** in your response\n  - **Split long information into small sections** with h2 headers and a relevant emoji at the start of it (for example `## 🐧 Linux`). Bullet points are preferred over long paragraphs, unless you're offering writing support or instructed otherwise by the user.\n- Asked to compare different options? You should firstly use a table to compare the main aspects, then elaborate or include relevant comments from online forums *after* the table. Make sure to provide a final recommendation for the user's use case!\n- Use LaTeX formatting for mathematical and scientific notations whenever appropriate. Enclose all LaTeX '$$' delimiters. NEVER generate LaTeX code in a latex block unless the user explicitly asks for it. DO NOT use LaTeX for regular documents (resumes, letters, essays, CVs, etc.).\n"
                property string tool: "functions" // search, functions, or none
                property list<var> extraModels: [
                    {
                        "api_format": "openai", // Most of the time you want "openai". Use "gemini" for Google's models
                        "description": "This is a custom model. Edit the config to add more! | Anyway, this is DeepSeek R1 Distill LLaMA 70B",
                        "endpoint": "https://openrouter.ai/api/v1/chat/completions",
                        "homepage": "https://openrouter.ai/deepseek/deepseek-r1-distill-llama-70b:free", // Not mandatory
                        "icon": "spark-symbolic", // Not mandatory
                        "key_get_link": "https://openrouter.ai/settings/keys", // Not mandatory
                        "key_id": "openrouter",
                        "model": "deepseek/deepseek-r1-distill-llama-70b:free",
                        "name": "Custom: DS R1 Dstl. LLaMA 70B",
                        "requires_key": true
                    }
                ]
            }

            property JsonObject appearance: JsonObject {
                property bool extraBackgroundTint: true

                // How every scroll bar in the shell is drawn.
                property JsonObject scrollbar: JsonObject {
                    // "minimal" — thumb only, track on hover
                    // "rail"    — track always drawn behind the thumb
                    // "stripes" — track drawn as rungs, thumb rides over them
                    property string style: "minimal"
                    property int width: 4
                    property int activeWidth: 9
                    // What widens when you go near it:
                    //   "bar"   the thumb, and the track with it
                    //   "track" only the track — the thumb stays thin inside it
                    //   "none"  nothing moves
                    property string hoverGrow: "bar"
                    property bool alwaysVisible: false  // not just while engaged
                    property bool showMap: true         // landmark dots, where supplied
                    property bool magnets: true         // release snaps to nearest
                    property bool labels: true          // name the one under the pointer
                }
                property int fakeScreenRounding: 2 // 0: None | 1: Always | 2: When not fullscreen
                property JsonObject fonts: JsonObject {
                    property string main: "Google Sans Flex"
                    property string numbers: "Google Sans Flex"
                    property string title: "Google Sans Flex"
                    property string iconNerd: "JetBrains Mono NF"
                    property string monospace: "JetBrains Mono NF"
                    property string reading: "Readex Pro"
                    property string expressive: "Space Grotesk"
                }
                property JsonObject transparency: JsonObject {
                    property bool enable: false
                    property bool automatic: true
                    property real backgroundTransparency: 0.11
                    property real contentTransparency: 0.57
                }
                property JsonObject wallpaperTheming: JsonObject {
                    property bool enableAppsAndShell: true
                    property bool enableQtApps: true
                    property bool enableTerminal: true
                    property JsonObject terminalGenerationProps: JsonObject {
                        property real harmony: 0.6
                        property real harmonizeThreshold: 100
                        property real termFgBoost: 0.35
                        property bool forceDarkMode: false
                    }
                }
                property JsonObject palette: JsonObject {
                    property string type: "auto" // Allowed: auto, scheme-content, scheme-expressive, scheme-fidelity, scheme-fruit-salad, scheme-monochrome, scheme-neutral, scheme-rainbow, scheme-tonal-spot
                    property string accentColor: ""
                }
            }

            property JsonObject audio: JsonObject {
                // Values in %
                property JsonObject protection: JsonObject {
                    // Prevent sudden bangs
                    property bool enable: false
                    property real maxAllowedIncrease: 10
                    property real maxAllowed: 99
                }
            }

            property JsonObject apps: JsonObject {
                property string bluetooth: "kcmshell6 kcm_bluetooth"
                property string changePassword: "wezterm start --always-new-process -- fish -i -c 'passwd; read -P \"Press Enter to close...\"'"
                property string network: "kcmshell6 kcm_networkmanagement"
                property string manageUser: "kcmshell6 kcm_users"
                property string networkEthernet: "kcmshell6 kcm_networkmanagement"
                property string taskManager: "plasma-systemmonitor --page-name Processes"
                property string terminal: "wezterm start --always-new-process" // This is only for shell actions
                property string update: "wezterm start --always-new-process -- fish -i -c 'pkexec pacman -Syu; read -P \"Press Enter to close...\"'"
                property string volumeMixer: `~/.config/hypr/hyprland/scripts/launch_first_available.sh "pavucontrol-qt" "pavucontrol"`
            }

            // Touchpad speed profile (libinput sensitivity — not a grab).
            // Context-switched pointer profiles. See services/KinetixProfiles.
            property JsonObject kinetix: JsonObject {
                property bool profilesEnabled: true
                // [ { scope: "app"|"workspace"|"monitor", match, name,
                //     settings: { ...engine fields... } } ]
                // JSON text, not a map: a `property var` with dynamic keys
                // inside a nested JsonObject segfaults Quickshell.
                property string profiles: "[]"
            }

            property JsonObject kinetixTouchpad: JsonObject {
                property bool enabled: false
                property real sensitivity: 0.0   // -1 slow .. 0 default .. 1 fast
                property bool flat: false        // flat = no acceleration
            }

            // On-screen stats overlay (FPS / net / CPU / GPU).
            property JsonObject statsHud: JsonObject {
                property string layout: "bar"        // bar | stack | compact | detailed
                property string position: "top-right" // top-left|top-right|bottom-left|bottom-right
                property real opacity: 0.88
                property bool showIcons: true
                property int marginX: 10
                property int marginY: 10
                property string iface: ""            // "" = auto-pick the busiest
                // Free placement, set by dragging in edit mode. The corner is
                // kept as well as the offsets: anchoring to the NEAREST corner
                // means the overlay stays put when the screen resolution
                // changes, which absolute coordinates would not.
                property bool editMode: false
                property int snapPx: 12              // magnet radius
                property bool snapGrid: true         // magnet to edges/centres
                property bool snapDots: false        // magnet to the dotted grid
                property int gridSize: 20            // dotted-grid spacing (px)
                property bool showGrid: true         // draw the grid while placing
                // Used when layout == "custom": exactly the stats you ticked,
                // in the order you put them.
                property list<string> fields: ["fps", "cpu", "gpu", "ram", "net"]
                // { appId: { layout, fields, position, opacity } }
                // A game wants FPS and temps; a compile wants CPU and disk.
                // Stored as JSON text because JsonAdapter has no map type.
                property string appProfiles: "{}"
                // How the overlay presents itself:
                //   always  floating card, click-through, never in the way
                //   peek    a thin tab at the edge that expands on hover
                //   dock    a full-width strip pinned to an edge
                // Remembered across restarts — an overlay you have to re-enable
                // every time the shell reloads is not an overlay you leave on.
                property bool enabled: false
                property string mode: "always"
                property int peekSize: 5        // px of tab left showing
                property bool dockReserve: false // dock: push windows aside?
                // Per-stat unit choices. The same number is useful in
                // different shapes: a network rate as MB/s tells you about
                // file transfers, as Mbit/s it tells you about your link
                // speed. { statId: formatId } — see StatsHudBridge.formats.
                property string units: "{}"
            }

            property JsonObject background: JsonObject {
                // Pack effect drawn over the wallpaper (path to its .json).
                // Empty = off. This runs on OUR layer rather than through
                // decoration:screen_shader, so it costs no damage-tracking
                // and cannot fight the colour-grading sliders.
                property string effect: ""
                property real effectStrength: -1   // -1 = use the effect's own default
                // Per-effect variable overrides, as JSON keyed by effect path:
                //   { "<effect.json path>": { "<param id>": value } }
                // Keyed by effect so switching effects and back keeps each
                // one's tuning. A JSON string (not a JsonObject) because the
                // shape is dynamic — one entry per effect the user has touched.
                property string effectParams: "{}"
                property JsonObject widgets: JsonObject {
                    property JsonObject clock: JsonObject {
                        property bool enable: true
                        property bool showOnlyWhenLocked: false
                        property string placementStrategy: "leastBusy" // "free", "leastBusy", "mostBusy"
                        property real x: 100
                        property real y: 100
                        property string style: "cookie"        // Options: "cookie", "digital"
                        property string styleLocked: "cookie"  // Options: "cookie", "digital"
                        property JsonObject cookie: JsonObject {
                            property bool aiStyling: false
                            property int sides: 14
                            property string dialNumberStyle: "full"   // Options: "dots" , "numbers", "full" , "none"
                            property string hourHandStyle: "fill"     // Options: "classic", "fill", "hollow", "hide"
                            property string minuteHandStyle: "medium" // Options "classic", "thin", "medium", "bold", "hide"
                            property string secondHandStyle: "dot"    // Options: "dot", "line", "classic", "hide"
                            property string dateStyle: "bubble"       // Options: "border", "rect", "bubble" , "hide"
                            property bool timeIndicators: true
                            property bool hourMarks: false
                            property bool dateInClock: true
                            property bool constantlyRotate: false
                            property bool useSineCookie: false
                        }
                        property JsonObject digital: JsonObject {
                            property bool adaptiveAlignment: true
                            property bool showDate: true
                            property bool animateChange: true
                            property bool vertical: false
                            property JsonObject font: JsonObject {
                                property string family: "Google Sans Flex"
                                property real weight: 350
                                property real width: 100
                                property real size: 90
                                property real roundness: 0
                            }
                        }
                        property JsonObject quote: JsonObject {
                            property bool enable: false
                            property string text: ""
                        }
                    }
                    property JsonObject weather: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 400
                        property real y: 100
                    }
                    property JsonObject calendar: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property string sizeMode: "2x2"
                    }
                    property JsonObject worldClock: JsonObject {
                        property bool enable: false
                        property list<string> timezones: ["Australia/Sydney", "Asia/Tokyo", "Europe/London", "America/New_York"]
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property string sizeMode: "2x2"
                        property int clockCount: 4
                    }
                    property JsonObject todo: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                    }
                    property JsonObject userCard: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property string sizeMode: "1x2"
                    }
                    property JsonObject customImage: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property string path: ""
                        property string shape: "Cookie4Sided"
                        property real size: 200
                    }
                    property JsonObject visualizer: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 0
                        property real y: 0
                    }
                    property JsonObject resources: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property bool vertical: false
                    }
                    property JsonObject timers: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property bool vertical: false
                    }
                }
                // Freeze widgets where they are, so a stray drag can't shove
                // one off the desktop.
                property bool widgetsLocked: false
                property string wallpaperPath: ""
                // The ORIGINAL source file — set alongside wallpaperPath by
                // every apply site. For direct applies this equals
                // wallpaperPath; for walltune applies it's the un-processed
                // source (the processed-[ab].png slot alternates and would
                // otherwise scramble per-file crop lookups).
                property string wallpaperSourcePath: ""
                property string thumbnailPath: ""
                // JSON { monitorName: imagePath }: monitors showing their own wallpaper.
                // Cleared by any apply to all monitors.
                property string monitorWallpapers: "{}"
                property bool hideWhenFullscreen: true
                // Per-wallpaper crop. offsetX/Y in [-1, 1] (fraction of
                // movable space); scale ≥ 1 zooms in. 0/0/1 = default.
                // Map keyed by wallpaperPath so each wallpaper remembers
                // its own framing.
                property JsonObject crop: JsonObject {
                    property real offsetX: 0
                    property real offsetY: 0
                    property real scale:   1
                    property string perFile: "{}"   // JSON: { path → {offsetX, offsetY, scale} }
                    // Incremented by the adjuster on every Save; readers
                    // include it in their bindings to force re-evaluation
                    // when `perFile` (a string) is mutated, since JsonObject
                    // doesn't always fire propertyChanged for string writes.
                    property int rev: 0
                }
                property JsonObject parallax: JsonObject {
                    property bool vertical: false
                    property bool autoVertical: false
                    property bool enableWorkspace: true
                    property real workspaceZoom: 1.07 // Relative to your screen, not wallpaper size
                    // How long the wallpaper takes to slide to the new
                    // workspace. Was hardcoded at 600, which is nearly double
                    // the shell's longest standard animation (400) and read as
                    // sluggish next to everything else moving.
                    property int duration: 400
                    property bool enableSidebar: true
                    property real widgetsFactor: 1.2
                }
            }

            property JsonObject monitors: JsonObject {
                // Give a display its best mode and a scale that divides the
                // panel evenly, once per connection. Off means nothing is
                // touched automatically; MonitorAutoMode.applyAll() still
                // works by hand.
                property bool autoBestMode: true
                property bool notifyOnChange: true
            }

            property JsonObject bar: JsonObject {
                property JsonObject autoHide: JsonObject {
                    property bool enable: false
                    // Get out of the way of fullscreen windows. Independent of
                    // `enable`: people who want the bar permanently visible
                    // still do not want it painted over a fullscreen game.
                    property bool onFullscreen: true
                    property int hoverRegionWidth: 2
                    property bool pushWindows: false
                    property JsonObject showWhenPressingSuper: JsonObject {
                        property bool enable: true
                        property int delay: 140
                    }
                }
                property bool bottom: false // Instead of top
                property int cornerStyle: 0 // 0: Hug | 1: Float | 2: Plain rectangle
                property bool floatStyleShadow: true // Show shadow behind bar when cornerStyle == 1 (Float)
                property bool borderless: false // true for no grouping of items
                property string topLeftIcon: "spark" // Options: "distro" or any icon name in ~/.config/quickshell/ii/assets/icons
                property bool showBackground: true
                property bool verbose: true
                // Pluggable bar widgets, the same mechanism the dock uses: a
                // JSON array of ids from BarWidgets.catalog, in display order.
                // Empty by default, so the bar looks exactly as it did until
                // something is switched on.
                property string widgets: "[]"
                // Per-widget settings, { widgetId: { key: value } }. Defaults
                // live in BarWidgets.catalog, so only overrides are stored.
                property string widgetSettings: "{}"
                property bool vertical: false
                property JsonObject resources: JsonObject {
                    property bool alwaysShowSwap: true
                    property bool alwaysShowCpu: true
                    property int memoryWarningThreshold: 95
                    property int swapWarningThreshold: 85
                    property int cpuWarningThreshold: 90
                    // CPU/RAM/swap readout on the bar beside the active-window
                    // pill (key name predates the move out of the pill itself):
                    // 0 = never, 1 = only the ones near critical, 2 = always.
                    property int showInWindowPill: 1
                    // Percentage at which RAM/swap/CPU counts as near critical
                    // for the mode above.
                    property int criticalThreshold: 85
                }
                // Spectrum in the media island. Costs a cava process while
                // something plays, so it's a switch.
                property bool showVisualizer: true
                property list<string> screenList: [] // List of names, like "eDP-1", find out with 'hyprctl monitors' command
                property JsonObject utilButtons: JsonObject {
                    property bool showScreenSnip: true
                    property bool showColorPicker: false
                    property bool showMicToggle: false
                    property bool showKeyboardToggle: true
                    property bool showTouchpadToggle: true
                    property bool showDarkModeToggle: true
                    property bool showPerformanceProfileToggle: false
                    property bool showScreenRecord: false
                }
                property JsonObject workspaces: JsonObject {
                    property bool monochromeIcons: true
                    property int shown: 10
                    property bool showAppIcons: true
                    property bool alwaysShowNumbers: false
                    property int showNumberDelay: 300 // milliseconds
                    property list<string> numberMap: ["1", "2"] // Characters to show instead of numbers on workspace indicator
                    property bool useNerdFont: false
                    // Roman numerals (I, II, III...) vs plain digits on the
                    // workspace slots. Separate from useNerdFont, which swaps
                    // the glyph set entirely.
                    property bool romanNumerals: true
                    // The cookie blob's spin + numeral flash on every workspace
                    // change. Purely decorative; off makes switching silent.
                    property bool switchFlash: true
                    // The media / notification slot on the right of the island
                    // (play button, track title, transport controls).
                    property bool showMediaContext: true
                    // Slot + active-indicator shape:
                    //   "cookie"   = squircle blob (default, 4-sided SineCookie)
                    //   "pill"     = round occupied chips + circular active dot
                    //   "rounded"  = rounded-rectangle occupied chips + matching diamond
                    //   "square"   = sharp-corner occupied chips + diamond
                    //   "hexagon"  = circular chips + 6-sided cookie active
                    property string shape: "cookie"
                }
                property JsonObject weather: JsonObject {
                    property bool enable: false
                    property bool enableGPS: true // gps based location
                    property string city: "" // When 'enableGPS' is false
                    property bool useUSCS: false // Instead of metric (SI) units
                    property int fetchInterval: 10 // minutes
                }
                property JsonObject indicators: JsonObject {
                    property JsonObject notifications: JsonObject {
                        property bool showUnreadCount: false
                    }
                }
                property JsonObject tooltips: JsonObject {
                    property bool clickToShow: false
                }
            }

            property JsonObject battery: JsonObject {
                property int low: 20
                property int critical: 5
                property int full: 101
                property bool automaticSuspend: true
                property int suspend: 3
            }

            property JsonObject calendar: JsonObject {
                property string locale: "en-GB"
            }

            property JsonObject cheatsheet: JsonObject {
                // Use a nerdfont to see the icons
                // 0: 󰖳  | 1: 󰌽 | 2: 󰘳 | 3:  | 4: 󰨡
                // 5:  | 6:  | 7: 󰣇 | 8:  | 9: 
                // 10:  | 11:  | 12:  | 13:  | 14: 󱄛
                property string superKey: ""
                property bool useMacSymbol: false
                property bool splitButtons: false
                property bool useMouseSymbol: false
                property bool useFnSymbol: false
                property JsonObject fontSize: JsonObject {
                    property int key: Appearance.font.pixelSize.smaller
                    property int comment: Appearance.font.pixelSize.smaller
                }
            }

            property JsonObject conflictKiller: JsonObject {
                property bool autoKillNotificationDaemons: false
                property bool autoKillTrays: false
            }

            property JsonObject crosshair: JsonObject {
                // Valorant crosshair format. Use https://www.vcrdb.net/builder
                property string code: "0;P;d;1;0l;10;0o;2;1b;0"
            }

            property JsonObject dock: JsonObject {
                property bool enable: false
                property bool showBackground: true
                property bool showPinButton: true
                property bool showAppsButton: true
                property bool showMedia: true
                property bool monochromeIcons: true
                // Off, a preview is one frame grabbed on hover instead of a
                // GPU copy per window per frame.
                property bool livePreviews: true
                // "grow" | "rise" | "fade" | "none". All transforms — animating
                // the popup's size resizes its Wayland surface every frame.
                property string previewAnimation: "grow"
                property real height: 60
                property real hoverRegionHeight: 2
                // Detach from the screen edge so the dock reads as an island
                // rather than a bar welded to the bottom.
                property bool floating: true
                property real floatingMargin: 8
                // "bottom" | "top". Anything else is treated as bottom.
                property string position: "bottom"
                // Hover grows the card upward in a popup; the dock never
                // changes size, so it reads as breaking out.
                property bool mediaExpandOnHover: false
                property real mediaExpandedHeight: 44
                // Gap between dock items. 3 was tight enough that icons ran
                // together into one blob at a glance.
                property real spacing: 6
                // Enabled dock widgets, in order, as a JSON array of ids from
                // DockWidgets.catalog. A string because JsonAdapter segfaults
                // on a `property var` inside a JsonObject.
                property string widgets: "[]"
                // Per-widget settings, { widgetId: { key: value } }. Defaults
                // live in DockWidgets.catalog, so only overrides are stored.
                property string widgetSettings: "{}"
                // When the folder grid appears on hovering a file manager:
                //   "always"    whenever the icon is hovered
                //   "noWindows" only when that app has nothing open, so the
                //               popup does not grow to hold both
                //   "off"       never
                property string folderGrid: "always"
                property bool pinnedOnStartup: false
                property bool hoverToReveal: true // When false, only reveals on empty workspace
                property list<string> pinnedApps: [ // IDs of pinned entries
                    "org.kde.dolphin", "kitty",]
                property list<string> ignoredAppRegexes: []
            }

            property JsonObject interactions: JsonObject {
                property JsonObject scrolling: JsonObject {
                    property bool fasterTouchpadScroll: false // Enable faster scrolling with touchpad
                    property int mouseScrollDeltaThreshold: 120 // delta >= this then it gets detected as mouse scroll rather than touchpad
                    property int mouseScrollFactor: 120
                    property int touchpadScrollFactor: 450
                }
                property JsonObject deadPixelWorkaround: JsonObject { // Hyprland leaves out 1 pixel on the right for interactions
                    property bool enable: false
                }
            }

            property JsonObject language: JsonObject {
                property string ui: "auto" // UI language. "auto" for system locale, or specific language code like "zh_CN", "en_US"
                property JsonObject translator: JsonObject {
                    property string engine: "auto" // Run `trans -list-engines` for available engines. auto should use google
                    property string targetLanguage: "auto" // Run `trans -list-all` for available languages
                    property string sourceLanguage: "auto"
                }
            }

            property JsonObject launcher: JsonObject {
                property list<string> pinnedApps: [ "org.kde.dolphin", "kitty", "cmake-gui"]

                // ── Ordering ─────────────────────────────────────────────
                // frecency | relevance | frequency | recent | alphabetical
                property string sortMode: "frecency"
                property bool reverseSort: false
                // Manual per-entry importance, highest first. An ORDERED LIST
                // rather than an {id: rank} map on purpose: dynamic keys in a
                // nested JsonObject are exactly what the JsonAdapter cannot
                // store safely. Mirrors pinnedApps above.
                property list<string> priorityApps: []
                // Applied as a boost on top of whatever sortMode is active, so
                // prioritising something doesn't force you out of relevance.
                property bool usePriorityBoost: true

                // ── Usage tracking ───────────────────────────────────────
                // Counts live in ii/services/LauncherRanking.qml, not here —
                // they're hot and dynamically keyed.
                property bool trackUsage: true
                // Days until a launch counts half as much, for "Smart" sort.
                property real frecencyHalfLife: 14

                // ── Which entries appear ─────────────────────────────────
                property list<string> hiddenApps: []
                property bool showHidden: false
                property bool showTerminalApps: true
                property bool showDesktopActions: true
                property int maxResults: 15

                // ── Row appearance ───────────────────────────────────────
                property bool showLaunchCounts: false
                property bool showDescriptions: true
                property bool compactRows: false
            }

            property JsonObject light: JsonObject {
                property JsonObject night: JsonObject {
                    property bool automatic: true
                    property string from: "19:00" // Format: "HH:mm", 24-hour time
                    property string to: "06:30"   // Format: "HH:mm", 24-hour time
                    property int colorTemperature: 5000
                }
                property JsonObject antiFlashbang: JsonObject {
                    property bool enable: false
                }
            }

            property JsonObject lock: JsonObject {
                property bool useHyprlock: false
                property bool launchOnStartup: false
                property JsonObject blur: JsonObject {
                    property bool enable: true
                    property real radius: 100
                    property real extraZoom: 1.1
                }
                property bool centerClock: true
                property bool showLockedText: true
                property JsonObject security: JsonObject {
                    property bool unlockKeyring: true
                    property bool requirePasswordToPower: false
                }
                property bool materialShapeChars: true
            }

            property JsonObject media: JsonObject {
                // Corner radius of album artwork, everywhere it is drawn — the
                // dock card and the media popup share one widget, so one value
                // keeps them consistent. 0 = square.
                property real coverRadius: 8
                // Attempt to remove dupes (the aggregator playerctl one and browsers' native ones when there's plasma browser integration)
                property bool filterDuplicatePlayers: true
                // JSON-encoded map of desktopEntry substrings (lowercase) to accent colors.
                // Example: '{"spotify":"#1db954","firefox":"#ff6611"}'.
                // Stored as a string (not a JsonObject / property var) because Quickshell's
                // JsonAdapter (jsonadapter.cpp:164) segfaults on a `property var` inside a
                // nested JsonObject when the file is reloaded.
                property string playerColors: "{}"
            }

            property JsonObject networking: JsonObject {
                property string userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
            }

            property JsonObject notifications: JsonObject {
                property int timeout: 7000
                // Shell-played notification sound. Lets the shell be the single,
                // controllable source of notification sound (respecting per-app
                // mute + the global silent toggle) — disable the apps' own
                // sounds (e.g. Telegram) so this isn't doubled.
                property bool sound: true
                // freedesktop sound-theme event id (played via canberra-gtk-play,
                // honours the user's sound theme). e.g. "message-new-instant",
                // "bell", "dialog-information".
                property string soundName: "message-new-instant"
            }

            property JsonObject osd: JsonObject {
                property int timeout: 1000
            }

            property JsonObject osk: JsonObject {
                // Manual layout, used only when followSystemLayout is false.
                // Must be a key of onScreenKeyboard/layouts.js `byName`
                // ("English (US)", "German", "Russian") — the previous default
                // "qwerty_full" was not one, so it silently fell back.
                property string layout: "English (US)"
                // Draw the keymap of the keyboard currently in use.
                property bool followSystemLayout: true
                property bool pinnedOnStartup: false
            }

            property JsonObject touchpad: JsonObject {
                property string side: "right" // "right" or "left"
            }

            property JsonObject overlay: JsonObject {
                property bool openingZoomAnimation: true
                property bool darkenScreen: true
                property real clickthroughOpacity: 0.8
                property JsonObject floatingImage: JsonObject {
                    property string imageSource: "https://media.tenor.com/H5U5bJzj3oAAAAAi/kukuru.gif"
                    property real scale: 0.5
                }
            }

            property JsonObject overview: JsonObject {
                property bool enable: true
                property real scale: 0.18 // Relative to screen size
                property real rows: 2
                property real columns: 5
                property bool orderRightLeft: false
                property bool orderBottomUp: false
                property bool centerIcons: true
            }

            property JsonObject regionSelector: JsonObject {
                property JsonObject targetRegions: JsonObject {
                    property bool windows: true
                    property bool layers: false
                    property bool content: true
                    property bool showLabel: false
                    property real opacity: 0.3
                    property real contentRegionOpacity: 0.8
                    property int selectionPadding: 5
                }
                property JsonObject rect: JsonObject {
                    property bool showAimLines: true
                }
                property JsonObject circle: JsonObject {
                    property int strokeWidth: 6
                    property int padding: 10
                }
                property JsonObject annotation: JsonObject {
                    property bool useSatty: false
                }
            }

            property JsonObject resources: JsonObject {
                property int updateInterval: 3000
                property int historyLength: 60
            }

            property JsonObject tray: JsonObject {
                property bool monochromeIcons: true
                property bool showItemId: false
                property bool invertPinnedItems: true // Makes the below a whitelist for the tray and blacklist for the pinned area
                property list<var> pinnedItems: [ "Fcitx" ]
                property bool filterPassive: true
            }

            property JsonObject musicRecognition: JsonObject {
                property int timeout: 16
                property int interval: 4
            }

            property JsonObject search: JsonObject {
                property int nonAppResultDelay: 30 // This prevents lagging when typing
                property string engineBaseUrl: "https://www.google.com/search?q="
                property list<string> excludedSites: ["quora.com", "facebook.com"]
                property bool sloppy: false // Uses levenshtein distance based scoring instead of fuzzy sort. Very weird.
                property JsonObject prefix: JsonObject {
                    property bool showDefaultActionsWithoutPrefix: true
                    property string action: "/"
                    property string app: ">"
                    property string clipboard: ";"
                    property string emojis: ":"
                    property string math: "="
                    property string shellCommand: "$"
                    property string webSearch: "?"
                    property string theme: ","
                }
                property JsonObject imageSearch: JsonObject {
                    property string imageSearchEngineBaseUrl: "https://lens.google.com/uploadbyurl?url="
                    property bool useCircleSelection: false
                }
                // User-defined launcher commands (run via the `/` action prefix).
                //   Leaf:  { "name", "icon", "description", "exec" }
                //   Group: { "name", "icon", "description", "sub": [ ...leaves ] }
                //          → children become `/<group> <child>` subcommands.
                property list<var> commands: [
                    // { "name": "mixer", "icon": "tune", "exec": "pavucontrol" },
                    // { "name": "dev", "icon": "code", "description": "Dev tools", "sub": [
                    //     { "name": "btop", "icon": "monitoring",  "exec": "kitty -e btop" },
                    //     { "name": "logs", "icon": "description", "exec": "kitty -e journalctl -f" },
                    // ]},
                ]
            }

            property JsonObject sidebar: JsonObject {
                property bool keepRightSidebarLoaded: true
                property JsonObject translator: JsonObject {
                    property bool enable: false
                    property int delay: 300 // Delay before sending request. Reduces (potential) rate limits and lag.
                }
                property JsonObject finance: JsonObject {
                    // Shown even before a bank is linked, because the tab is
                    // where the setup lives — gating it on having data made the
                    // setup screen unreachable.
                    property bool enable: true
                }
                property JsonObject ai: JsonObject {
                    property bool textFadeIn: false
                }
                property JsonObject booru: JsonObject {
                    property bool allowNsfw: false
                    property string defaultProvider: "yandere"
                    property int limit: 20
                    property JsonObject zerochan: JsonObject {
                        property string username: "[unset]"
                    }
                }
                property JsonObject cornerOpen: JsonObject {
                    property bool enable: true
                    property bool bottom: false
                    property bool valueScroll: true
                    property bool clickless: false
                    property int cornerRegionWidth: 250
                    property int cornerRegionHeight: 5
                    property bool visualize: false
                    property bool clicklessCornerEnd: true
                    property int clicklessCornerVerticalOffset: 1
                }

                property JsonObject quickToggles: JsonObject {
                    property string style: "android" // Options: classic, android
                    property JsonObject android: JsonObject {
                        property int columns: 5
                        // When true, tiles in each row stretch to fill the full available width.
                        property bool autoFill: false
                        // Legacy single-list; kept for back-compat when tabs is empty.
                        property list<var> toggles: [
                            { "size": 2, "type": "network" },
                            { "size": 2, "type": "bluetooth"  },
                            { "size": 1, "type": "idleInhibitor" },
                            { "size": 1, "type": "mic" },
                            { "size": 2, "type": "audio" },
                            { "size": 2, "type": "nightLight" }
                        ]
                        // Multi-tab layout — user-customizable. Each tab is { name, icon, toggles: [...] }.
                        property list<var> tabs: [
                            { "name": "Network", "icon": "wifi",         "toggles": [
                                { "size": 2, "type": "network" },
                                { "size": 2, "type": "bluetooth" },
                                { "size": 1, "type": "kdeconnect" }
                            ]},
                            { "name": "Media",   "icon": "graphic_eq",   "toggles": [
                                { "size": 2, "type": "audio" },
                                { "size": 2, "type": "audioOutput" },
                                { "size": 1, "type": "mic" },
                                { "size": 1, "type": "musicRecognition" },
                                { "size": 1, "type": "notifications" }
                            ]},
                            { "name": "System",  "icon": "tune",         "toggles": [
                                { "size": 2, "type": "nightLight" },
                                { "size": 1, "type": "idleInhibitor" },
                                { "size": 1, "type": "sleepTimer" },
                                { "size": 1, "type": "darkMode" },
                                { "size": 1, "type": "gameMode" }
                            ]}
                        ]
                    }
                }

                property JsonObject quickSliders: JsonObject {
                    property bool enable: false
                    property bool showMic: false
                    property bool showVolume: true
                    property bool showBrightness: true
                }
            }

            property JsonObject screenRecord: JsonObject {
                property string savePath: Directories.videos.replace("file://","") // strip "file://"
            }

            property JsonObject screenSnip: JsonObject {
                property string savePath: "" // only copy to clipboard when empty
                // Include the mouse cursor in captures (grim -c). Off by default:
                // a cursor in a UI screenshot is usually noise, but it's the
                // whole point when documenting a hover or drag.
                property bool includeCursor: false
            }

            property JsonObject sounds: JsonObject {
                property bool battery: false
                property bool pomodoro: false
                property string theme: "freedesktop"
            }

            property JsonObject time: JsonObject {
                // https://doc.qt.io/qt-6/qtime.html#toString
                property string format: "hh:mm"
                property string shortDateFormat: "dd/MM"
                property string dateWithYearFormat: "dd/MM/yyyy"
                property string dateFormat: "ddd, dd/MM"
                property JsonObject pomodoro: JsonObject {
                    property int breakTime: 300
                    property int cyclesBeforeLongBreak: 4
                    property int focus: 1500
                    property int longBreak: 900
                }
                property bool secondPrecision: false
            }

            property JsonObject updates: JsonObject {
                property int checkInterval: 120 // minutes
                property int adviseUpdateThreshold: 75 // packages
                property int stronglyAdviseUpdateThreshold: 200 // packages

                // The shell's own checkout, not the pacman counts above.
                property JsonObject shell: JsonObject {
                    property bool enable: true
                    property int checkIntervalHours: 6
                    // Off: the shell hot-reloads on the pull, so an unattended
                    // update changes the desktop underfoot.
                    property bool autoApply: false
                    property bool notify: true
                }
            }
            
            property JsonObject wallpaperSelector: JsonObject {
                property bool useSystemFileDialog: false
            }
            
            property JsonObject windows: JsonObject {
                property bool showTitlebar: true // Client-side decoration for shell apps
                property bool centerTitle: true
                property bool useThemeColorsForDecorations: false // false = macOS Traffic Lights, true = Material Theme
                property bool showButtonIconsOnHover: false // false = Always show icons, true = Show icons on hover only
            }

            property JsonObject hacks: JsonObject {
                property int arbitraryRaceConditionDelay: 20 // milliseconds
            }

            property JsonObject workSafety: JsonObject {
                property JsonObject enable: JsonObject {
                    property bool wallpaper: false
                    property bool clipboard: false
                }
                property JsonObject triggerCondition: JsonObject {
                    property list<string> networkNameKeywords: ["airport", "cafe", "college", "company", "eduroam", "free", "guest", "public", "school", "university"]
                    property list<string> fileKeywords: ["anime", "booru", "ecchi", "hentai", "yande.re", "konachan", "breast", "nipples", "pussy", "nsfw", "spoiler", "girl"]
                    property list<string> linkKeywords: ["hentai", "porn", "sukebei", "hitomi.la", "rule34", "gelbooru", "fanbox", "dlsite"]
                }
            }

            property JsonObject waffles: JsonObject {
                // Some spots are kinda janky/awkward. Setting the following to
                // false will make (some) stuff also be like that for accuracy. 
                // Example: the right-click menu of the Start button
                property JsonObject tweaks: JsonObject {
                    property bool switchHandlePositionFix: true
                    property bool smootherMenuAnimations: true
                    property bool smootherSearchBar: true
                }
                property JsonObject bar: JsonObject {
                    property bool bottom: true
                    property bool leftAlignApps: false
                }
                property JsonObject actionCenter: JsonObject {
                    property list<string> toggles: [ "network", "bluetooth", "easyEffects", "powerProfile", "idleInhibitor", "nightLight", "darkMode", "antiFlashbang", "cloudflareWarp", "mic", "musicRecognition", "notifications", "onScreenKeyboard", "gameMode", "screenSnip", "colorPicker" ]
                }
                property JsonObject calendar: JsonObject {
                    property bool force2CharDayOfWeek: true
                }
            }
            // KDE-style desktop icons. Renders ~/Desktop on the Background
            // layer with snap-grid positioning, thumbnails, and a right-
            // click context menu. Lazy-loaded when `enable` is false so
            // RAM cost is zero unless turned on.
            property JsonObject desktop: JsonObject {
                property JsonObject icons: JsonObject {
                    property bool enable: false
                    property int  iconSize: 64       // delegate size in px
                    property bool showHidden: false
                    property bool thumbnails: true   // image/video previews
                    property string sortMode: "name" // name | mtime | size | type
                    // Per-icon positions (JSON map: name → {x, y}).
                    // Empty = use auto-grid layout.
                    property string positions: "{}"
                }
            }
        }
    }
}
