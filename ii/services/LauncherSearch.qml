pragma Singleton

import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    property string query: ""
    // Clipboard sort mode: "newest" | "oldest" | "size"
    property string clipboardSort: "newest"

    function ensurePrefix(prefix) {
        if ([Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch,].some(i => root.query.startsWith(i))) {
            root.query = prefix + root.query.slice(1);
        } else {
            root.query = prefix + root.query;
        }
    }

    // https://specifications.freedesktop.org/menu/latest/category-registry.html
    property list<string> mainRegisteredCategories: ["AudioVideo", "Development", "Education", "Game", "Graphics", "Network", "Office", "Science", "Settings", "System", "Utility"]
    property list<string> appCategories: DesktopEntries.applications.values.reduce((acc, entry) => {
        for (const category of entry.categories) {
            if (!acc.includes(category) && mainRegisteredCategories.includes(category)) {
                acc.push(category);
            }
        }
        return acc;
    }, []).sort()

    // Load user action scripts from ~/.config/illogical-impulse/actions/
    // Uses FolderListModel to auto-reload when scripts are added/removed
    property var userActionScripts: {
        const actions = [];
        for (let i = 0; i < userActionsFolder.count; i++) {
            const fileName = userActionsFolder.get(i, "fileName");
            const filePath = userActionsFolder.get(i, "filePath");
            if (fileName && filePath) {
                const actionName = fileName.replace(/\.[^/.]+$/, ""); // strip extension
                actions.push({
                    action: actionName,
                    execute: ((path) => (args) => {
                        Quickshell.execDetached([path, ...(args ? args.split(" ") : [])]);
                    })(FileUtils.trimFileProtocol(filePath.toString()))
                });
            }
        }
        return actions;
    }

    FolderListModel {
        id: shaderFolder
        folder: "file://" + Quickshell.env("HOME") + "/.config/hypr/shaders"
        nameFilters: ["*.frag", "*.glsl"]
        showDirs: false
        showDotAndDotDot: false
    }

    // Lutris cover art, keyed by slug. The desktop entry's icon is a theme name
    // (lutris_<slug>) that is usually not installed, so the artwork on disk is
    // the only picture most games actually have.
    FolderListModel {
        id: lutrisCoverArt
        folder: "file://" + Quickshell.env("HOME") + "/.local/share/lutris/coverart"
        showDirs: false
        showDotAndDotDot: false
    }

    readonly property var lutrisArt: {
        const map = {};
        for (let i = 0; i < lutrisCoverArt.count; i++) {
            const name = String(lutrisCoverArt.get(i, "fileName") ?? "");
            const slug = name.replace(/\.(jpg|jpeg|png|webp)$/i, "");
            if (slug.length > 0)
                map[slug] = FileUtils.trimFileProtocol(String(lutrisCoverArt.get(i, "filePath")));
        }
        return map;
    }

    // Built from the desktop entries Lutris writes, so installing or removing a
    // game is picked up on its own — nothing to maintain by hand.
    readonly property var gameCommands: (DesktopEntries.applications?.values ?? [])
        .filter(e => e && (e.id ?? "").startsWith("lutris-"))
        .map(e => {
            const slug = String(e.id).replace(/^lutris-/, "");
            const art = root.lutrisArt[slug];
            return {
                action: e.name ?? slug,
                icon: art ?? (e.icon ?? "videogame_asset"),
                iconType: art ? LauncherSearchResult.IconType.System
                              : LauncherSearchResult.IconType.Material,
                description: "",
                execute: () => e.execute()
            };
        })
        .sort((a, b) => String(a.action).localeCompare(String(b.action)))

    FolderListModel {
        id: userActionsFolder
        folder: Qt.resolvedUrl(Directories.userActions)
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    // Shared by the numeric --flag=value display commands. Parsing, clamping
    // and applying live in one place so a new flag is a single line rather
    // than a copy of the same five.
    function applyGrading(key, args, min, max) {
        const n = parseFloat(String(args).replace(",", "."));
        if (!isFinite(n)) return;
        const v = Math.max(min, Math.min(max, n));
        GlobalStates.displayGrading = Object.assign({}, GlobalStates.displayGrading ?? {},
                                                    { [key]: v });
    }

    // Window-scope values need a profile to live on, and only run on a
    // window-scope profile — so put the profile in a state that can show them
    // rather than saving something that silently does nothing.
    function applyWindowParam(key, args, min, max) {
        const n = parseFloat(String(args).replace(",", "."));
        if (!isFinite(n)) return;
        const app = AppDisplay.focusedApp;
        if (app.length === 0) {
            Quickshell.execDetached(["notify-send", "Display",
                Translation.tr("No focused app to apply that to"), "-a", "Shell"]);
            return;
        }
        if (!AppDisplay.has(app)) AppDisplay.setProfile(app, AppDisplay.defaults);
        AppDisplay.enabled = true;
        AppDisplay.update(app, "scope", "window");
        AppDisplay.update(app, key, Math.max(min, Math.min(max, n)));
    }

    // Built-in launcher commands as a TREE. A node with `sub` is a group;
    // a node with `execute` is a runnable leaf. Top-level groups keep the
    // `/` list short — the launcher navigates this with the query.
    property var searchActions: [
        {
            action: "sort",
            icon: "sort",
            description: Translation.tr("Sort & filter results"),
            // Bare `/sort` opens the dropdown; the leaves below switch mode
            // directly so you can go straight there without opening anything.
            execute: () => { GlobalStates.launcherSortOpen = true },
            sub: LauncherRanking.sortModes.map(m => ({
                action: `--${m.id}`,
                icon: m.icon,
                description: m.hint,
                execute: () => {
                    Config.options.launcher.sortMode = m.id
                    GlobalStates.launcherSortOpen = false
                }
            })).concat([
                {
                    action: "--reverse",
                    icon: "swap_vert",
                    description: Translation.tr("Toggle reverse order"),
                    execute: () => {
                        Config.options.launcher.reverseSort = !Config.options.launcher.reverseSort
                    }
                },
                {
                    action: "--settings",
                    icon: "tune",
                    description: Translation.tr("Open the sort & filter panel"),
                    execute: () => { GlobalStates.launcherSortOpen = true }
                },
            ])
        },
        {
            action: "theme",
            icon: "palette",
            description: Translation.tr("Appearance & wallpaper"),
            sub: [
                {
                    action: "--dark",
                    icon: "dark_mode",
                    description: Translation.tr("Switch to dark mode"),
                    execute: () => {
                        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "dark", "--noswitch"]);
                    }
                },
                {
                    action: "--light",
                    icon: "light_mode",
                    description: Translation.tr("Switch to light mode"),
                    execute: () => {
                        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "light", "--noswitch"]);
                    }
                },
                {
                    action: "--accent",
                    icon: "format_color_fill",
                    description: Translation.tr("Set the accent color from a hex value"),
                    execute: args => {
                        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--color", ...(args != '' ? [`${args}`] : [])]);
                    }
                },
                {
                    action: "--pick",
                    icon: "wallpaper",
                    description: Translation.tr("Open the wallpaper picker"),
                    execute: () => {
                        GlobalStates.wallpaperSelectorOpen = true;
                    }
                },
                {
                    action: "--random",
                    icon: "image_search",
                    description: Translation.tr("Set a random Konachan wallpaper"),
                    execute: () => {
                        Quickshell.execDetached([Quickshell.shellPath("scripts/colors/random/random_konachan_wall.sh")]);
                    }
                },
            ]
        },
        {
            action: "display",
            icon: "display_settings",
            description: Translation.tr("Display, shaders & per-app looks"),
            sub: [
                {
                    action: "--shader",
                    icon: "auto_awesome",
                    description: Translation.tr("Apply a whole-screen shader"),
                    // A group, not a leaf: selecting it drills in, so the
                    // shader list is offered as prompts instead of you having
                    // to already know the names.
                    get sub() {
                        const out = [];
                        for (let i = 0; i < shaderFolder.count; ++i) {
                            const name = String(shaderFolder.get(i, "fileName"));
                            const path = String(shaderFolder.get(i, "filePath"));
                            out.push({
                                action: name.replace(/\.(frag|glsl)$/, ""),
                                icon: "filter_vintage",
                                description: Translation.tr("Whole-screen shader"),
                                execute: () => AppDisplay.setBase(path, false)
                            });
                        }
                        out.push({
                            action: "off",
                            icon: "block",
                            description: Translation.tr("Clear the screen shader"),
                            execute: () => AppDisplay.setBase("", false)
                        });
                        return out;
                    }
                },
                {
                    action: "--effect",
                    icon: "animation",
                    description: Translation.tr("Apply an animated effect to the focused app"),
                    // Built from the packs themselves, so an effect dropped
                    // into a folder shows up here with no code change.
                    get sub() {
                        return (AppDisplay.effects ?? []).map(e => ({
                            action: String(e.name).toLowerCase().replace(/\s+/g, ""),
                            icon: e.icon ?? "animation",
                            description: e.pack + " — " + (e.desc ?? ""),
                            execute: () => {
                                const app = AppDisplay.focusedApp;
                                if (app.length === 0) {
                                    Quickshell.execDetached(["notify-send", "Effect",
                                        Translation.tr("No focused app to apply it to"), "-a", "Shell"]);
                                    return;
                                }
                                // An effect only runs on a window-scope
                                // profile, so put the profile in a state that
                                // can actually show it rather than saving
                                // something that silently does nothing.
                                if (!AppDisplay.has(app)) AppDisplay.setProfile(app, AppDisplay.defaults);
                                AppDisplay.enabled = true;
                                AppDisplay.update(app, "scope", "window");
                                AppDisplay.update(app, "effect", e.path);
                            }
                        }));
                    }
                },
                // Numeric flags: `--saturation=1.4`. They drive the same
                // grading state the panel's sliders do, so typing a value and
                // dragging a slider cannot disagree.
                {
                    action: "--saturation",
                    icon: "invert_colors",
                    description: Translation.tr("Set saturation, e.g. --saturation=1.4"),
                    execute: args => root.applyGrading("saturation", args, 0.0, 2.0)
                },
                {
                    action: "--contrast",
                    icon: "contrast",
                    description: Translation.tr("Set contrast, e.g. --contrast=1.2"),
                    execute: args => root.applyGrading("contrast", args, 0.5, 2.0)
                },
                {
                    action: "--gamma",
                    icon: "gradient",
                    description: Translation.tr("Set gamma, e.g. --gamma=0.9"),
                    execute: args => root.applyGrading("gamma", args, 0.5, 2.4)
                },
                {
                    action: "--gain",
                    icon: "exposure",
                    description: Translation.tr("Set gain, e.g. --gain=1.1"),
                    execute: args => root.applyGrading("gain", args, 0.3, 1.8)
                },
                {
                    action: "--dim",
                    icon: "brightness_low",
                    description: Translation.tr("Dim the focused app's window, e.g. --dim=0.3"),
                    execute: args => root.applyWindowParam("dim", args, 0.0, 0.9)
                },
                {
                    action: "--tint",
                    icon: "opacity",
                    description: Translation.tr("Tint the focused app's window, e.g. --tint=0.2"),
                    execute: args => root.applyWindowParam("tintStrength", args, 0.0, 0.8)
                },
                {
                    action: "--temp",
                    icon: "wb_twilight",
                    description: Translation.tr("Colour temperature in K, e.g. --temp=3500"),
                    execute: args => {
                        const n = parseFloat(String(args).replace(",", "."));
                        if (!isFinite(n)) return;
                        const k = Math.round(Math.max(1000, Math.min(20000, n)));
                        Quickshell.execDetached(["bash", "-c",
                            "hyprctl hyprsunset temperature " + k
                            + " || hyprsunset -t " + k + " &"]);
                    }
                },
                {
                    action: "--panel",
                    icon: "tune",
                    description: Translation.tr("Open the display panel"),
                    execute: () => { GlobalStates.displayOpen = true; }
                },
                {
                    action: "--perapp",
                    icon: "apps",
                    description: Translation.tr("Toggle per-app display profiles"),
                    execute: () => { AppDisplay.enabled = !AppDisplay.enabled; }
                },
                {
                    action: "--reset",
                    icon: "restart_alt",
                    description: Translation.tr("Clear grading, shader and the focused app's effect"),
                    execute: () => {
                        AppDisplay.setBase("", false);
                        const app = AppDisplay.focusedApp;
                        if (app.length > 0 && AppDisplay.has(app))
                            AppDisplay.update(app, "effect", "");
                    }
                },
            ]
        },
        {
            action: "clip",
            icon: "content_paste",
            description: Translation.tr("Clipboard"),
            sub: [
                {
                    action: "--paste",
                    icon: "content_paste_go",
                    description: Translation.tr("Paste the last N clipboard entries"),
                    execute: args => {
                        if (!/^(\d+)/.test(args.trim())) {
                            // Invalid if doesn't start with numbers
                            Quickshell.execDetached(["notify-send", Translation.tr("Superpaste"), Translation.tr("Usage: <tt>%1clip --paste NUM_OF_ENTRIES[i]</tt>\nSupply <tt>i</tt> when you want images\nExamples:\n<tt>%1clip --paste 4i</tt> for the last 4 images\n<tt>%1clip --paste 7</tt> for the last 7 entries").arg(Config.options.search.prefix.action), "-a", "Shell"]);
                            return;
                        }
                        const syntaxMatch = /^(?:(\d+)(i)?)/.exec(args.trim());
                        const count = syntaxMatch[1] ? parseInt(syntaxMatch[1]) : 1;
                        const isImage = !!syntaxMatch[2];
                        Cliphist.superpaste(count, isImage);
                    }
                },
                {
                    action: "--wipe",
                    icon: "delete_sweep",
                    description: Translation.tr("Clear clipboard history"),
                    execute: () => {
                        Cliphist.wipe();
                    }
                },
            ]
        },
        {
            action: "power",
            icon: "power_settings_new",
            description: Translation.tr("Session & power"),
            sub: [
                { action: "--lock",     icon: "lock",               description: Translation.tr("Lock the session"),    execute: () => Quickshell.execDetached(["loginctl", "lock-session"]) },
                { action: "--logout",   icon: "logout",             description: Translation.tr("Log out of Hyprland"), execute: () => Quickshell.execDetached(["hyprctl", "dispatch", "exit"]) },
                { action: "--suspend",  icon: "bedtime",            description: Translation.tr("Suspend the system"),  execute: () => Quickshell.execDetached(["systemctl", "suspend"]) },
                { action: "--reboot",   icon: "restart_alt",        description: Translation.tr("Restart the system"),  execute: () => Quickshell.execDetached(["systemctl", "reboot"]) },
                { action: "--shutdown", icon: "power_settings_new", description: Translation.tr("Power off"),           execute: () => Quickshell.execDetached(["systemctl", "poweroff"]) },
            ]
        },
        {
            action: "system",
            icon: "settings",
            description: Translation.tr("System"),
            sub: [
                { action: "--reload", icon: "refresh", description: Translation.tr("Reload the Hyprland config"), execute: () => Quickshell.execDetached(["hyprctl", "reload"]) },
            ]
        },
        {
            action: "todo",
            icon: "checklist",
            description: Translation.tr("Add a to-do task"),
            execute: args => {
                Todo.addTask(args);
            }
        },
        {
            action: "kill",
            icon: "gavel",
            description: Translation.tr("Kill running applications"),
            get sub() {
                const signals = [
                    { num: 1,  name: "hup",     desc: "SIGHUP - Hangup (1)" },
                    { num: 2,  name: "int",     desc: "SIGINT - Interrupt (2)" },
                    { num: 3,  name: "quit",    desc: "SIGQUIT - Quit (3)" },
                    { num: 4,  name: "ill",     desc: "SIGILL - Illegal Instruction (4)" },
                    { num: 5,  name: "trap",    desc: "SIGTRAP - Trace Trap (5)" },
                    { num: 6,  name: "abrt",    desc: "SIGABRT - Abort (6)" },
                    { num: 7,  name: "bus",     desc: "SIGBUS - Bus Error (7)" },
                    { num: 8,  name: "fpe",     desc: "SIGFPE - Floating Point Exception (8)" },
                    { num: 9,  name: "kill",    desc: "SIGKILL - Kill (Force, 9)" },
                    { num: 10, name: "usr1",    desc: "SIGUSR1 - User Defined 1 (10)" },
                    { num: 11, name: "segv",    desc: "SIGSEGV - Segmentation Fault (11)" },
                    { num: 12, name: "usr2",    desc: "SIGUSR2 - User Defined 2 (12)" },
                    { num: 13, name: "pipe",    desc: "SIGPIPE - Broken Pipe (13)" },
                    { num: 14, name: "alrm",    desc: "SIGALRM - Alarm Clock (14)" },
                    { num: 15, name: "term",    desc: "SIGTERM - Terminate (Nice, 15)" },
                    { num: 16, name: "stkflt",  desc: "SIGSTKFLT - Stack Fault (16)" },
                    { num: 17, name: "chld",    desc: "SIGCHLD - Child Status (17)" },
                    { num: 18, name: "cont",    desc: "SIGCONT - Continue (18)" },
                    { num: 19, name: "stop",    desc: "SIGSTOP - Stop (Pause, 19)" },
                    { num: 20, name: "tstp",    desc: "SIGTSTP - Terminal Stop (20)" },
                    { num: 21, name: "ttin",    desc: "SIGTTIN - Background Read (21)" },
                    { num: 22, name: "ttou",    desc: "SIGTTOU - Background Write (22)" },
                    { num: 23, name: "urg",     desc: "SIGURG - Urgent I/O Condition (23)" },
                    { num: 24, name: "xcpu",    desc: "SIGXCPU - CPU Limit Exceeded (24)" },
                    { num: 25, name: "xfsz",    desc: "SIGXFSZ - File Size Limit Exceeded (25)" },
                    { num: 26, name: "vtalrm",  desc: "SIGVTALRM - Virtual Timer Expired (26)" },
                    { num: 27, name: "prof",    desc: "SIGPROF - Profiling Timer Expired (27)" },
                    { num: 28, name: "winch",   desc: "SIGWINCH - Window Size Change (28)" },
                    { num: 29, name: "io",      desc: "SIGIO - I/O Possible (29)" },
                    { num: 30, name: "pwr",     desc: "SIGPWR - Power Failure (30)" },
                    { num: 31, name: "sys",     desc: "SIGSYS - Bad System Call (31)" }
                ];
                return ToplevelManager.toplevels.values.map(toplevel => {
                    const hToplevel = toplevel.HyprlandToplevel;
                    if (!hToplevel) return null;
                    const address = `0x${hToplevel.address}`;
                    const winData = HyprlandData.windowByAddress[address];
                    const appClass = winData?.class || hToplevel.appId || "Unknown";
                    const title = winData?.title || hToplevel.title || "";
                    const suffix = hToplevel.address.slice(-4);
                    const cleanClass = appClass.toLowerCase().replace(/[^a-z0-9_-]/g, "");
                    const actionName = `${cleanClass}-${suffix}`;
                    return {
                        action: actionName,
                        icon: AppSearch.guessIcon(appClass),
                        iconType: LauncherSearchResult.IconType.System,
                        description: title,
                        sub: [
                            {
                                action: "close",
                                icon: "close",
                                description: Translation.tr("Close window nicely"),
                                execute: () => {
                                    HyprDispatch.run("closewindow address:" + address);
                                }
                            }
                        ].concat(signals.map(s => ({
                            action: s.name,
                            icon: s.num === 9 ? "dangerous" : s.num === 15 ? "cancel" : "label_important",
                            description: Translation.tr(s.desc),
                            execute: () => {
                                const pid = hToplevel.pid;
                                if (pid) Quickshell.execDetached(["kill", `-${s.num}`, pid.toString()]);
                            }
                        }))).concat([
                            {
                                action: "killall",
                                icon: "delete_forever",
                                description: Translation.tr("Kill all instances of this app"),
                                execute: () => {
                                    if (appClass) Quickshell.execDetached(["killall", appClass]);
                                }
                            }
                        ])
                    };
                }).filter(Boolean);
            }
        },
    ]

    // Normalise a Config command ({ name, icon, description, exec, sub })
    // into the internal { action, icon, description, execute/sub } shape.
    function mapConfigCommand(c) {
        const icon = c.icon ?? "terminal";
        // A config command's icon may be a Material symbol name (the default,
        // and what every built-in group uses) or real artwork — an absolute
        // path or file: URL. Nodes have always been able to carry an iconType
        // (see the `n.iconType ?? Material` fallback where results are built),
        // but this mapper never set one, so a config icon was ALWAYS drawn as
        // a glyph and a cover-art path came out as a missing symbol.
        //
        // Explicit `"iconType": "system"` wins; otherwise a path is detected,
        // because that is unambiguous and saves stating it per entry.
        const looksLikePath = icon.startsWith("/") || icon.startsWith("file:");
        const node = {
            action: c.name,
            icon: icon,
            iconType: (c.iconType === "system" || looksLikePath)
                ? LauncherSearchResult.IconType.System
                : LauncherSearchResult.IconType.Material,
            description: c.description ?? ""
        };
        if (c.sub && c.sub.length > 0)
            node.sub = c.sub.map(s => root.mapConfigCommand(s));
        else
            node.execute = () => Quickshell.execDetached(["bash", "-c", c.exec]);
        return node;
    }

    // The full command tree the launcher navigates: built-in groups + user
    // action scripts + config-defined commands. A node with `sub` is a
    // group; a node with `execute` is a runnable leaf.
    property var commandTree: searchActions
        .concat(userActionScripts)
        .concat((root.gameCommands ?? []).length > 0 ? [{
            action: "games",
            icon: "sports_esports",
            description: Translation.tr("Launch a game"),
            sub: root.gameCommands
        }] : [])
        .concat((Config.options.search.commands ?? []).map(c => root.mapConfigCommand(c)))

    // Emitted when a group result is selected — asks the search widget to
    // replace the query so the group's subcommands come into view.
    signal requestQuery(string newQuery)

    property string mathResult: ""
    property bool clipboardWorkSafetyActive: {
        const enabled = Config.options.workSafety.enable.clipboard;
        const sensitiveNetwork = (StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
        return enabled && sensitiveNetwork;
    }

    function containsUnsafeLink(entry) {
        if (entry == undefined)
            return false;
        const unsafeKeywords = Config.options.workSafety.triggerCondition.linkKeywords;
        return StringUtils.stringListContainsSubstring(entry.toLowerCase(), unsafeKeywords);
    }

    Timer {
        id: nonAppResultsTimer
        interval: Config.options.search.nonAppResultDelay
        onTriggered: {
            let expr = root.query;
            if (expr.startsWith(Config.options.search.prefix.math)) {
                expr = expr.slice(Config.options.search.prefix.math.length);
            }
            mathProc.calculateExpression(expr);
        }
    }

    Process {
        id: mathProc
        property list<string> baseCommand: ["qalc", "-t"]
        function calculateExpression(expression) {
            mathProc.running = false;
            mathProc.command = baseCommand.concat(expression);
            mathProc.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                root.mathResult = data;
            }
        }
    }

    property list<var> results: {
        // Search results are handled here
        ////////////////// Skip? //////////////////
        if (root.query == "")
            return [];

        ///////////// Special cases ///////////////
        if (root.query.startsWith(Config.options.search.prefix.clipboard)) {
            // Clipboard
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.clipboard);
            const sorted = Cliphist.fuzzyQuery(searchString).slice();
            // Apply explicit sort regardless of fuzzy ordering. Each entry starts with "<id>\t..."
            const idOf = (e) => parseInt((e || "").split("\t")[0]) || 0;
            const sizeOf = (e) => {
                const s = (e || "").length;
                const m = (e || "").match(/binary data\s+(\d+(?:\.\d+)?)\s*(KiB|MiB|GiB|B)/i);
                if (m) {
                    const n = parseFloat(m[1]);
                    const u = m[2].toUpperCase();
                    return u === "GIB" ? n * 1024 * 1024 : u === "MIB" ? n * 1024 : u === "KIB" ? n : n / 1024;
                }
                return s;
            };
            if (root.clipboardSort === "newest") sorted.sort((a, b) => idOf(b) - idOf(a));
            else if (root.clipboardSort === "oldest") sorted.sort((a, b) => idOf(a) - idOf(b));
            else if (root.clipboardSort === "size")   sorted.sort((a, b) => sizeOf(b) - sizeOf(a));
            return sorted.map((entry, index, array) => {
                const mightBlurImage = Cliphist.entryIsImage(entry) && root.clipboardWorkSafetyActive;
                let shouldBlurImage = mightBlurImage;
                if (mightBlurImage) {
                    shouldBlurImage = shouldBlurImage && (root.containsUnsafeLink(array[index - 1]) || root.containsUnsafeLink(array[index + 1]));
                }
                const type = `#${entry.match(/^\s*(\S+)/)?.[1] || ""}`;
                return resultComp.createObject(null, {
                    rawValue: entry,
                    name: StringUtils.cleanCliphistEntry(entry),
                    verb: "",
                    type: type,
                    execute: () => {
                        Cliphist.copy(entry);
                    },
                    actions: [resultComp.createObject(null, {
                            name: Translation.tr("Copy"),
                            iconName: "content_copy",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Cliphist.copy(entry);
                            }
                        }),
                        // For image entries: decode to a real .png file, then
                        // offer "copy its path" and "open it in the file manager".
                        // The decode is on-demand (idempotent) so the file is
                        // guaranteed to exist when the action runs, not just
                        // when the thumbnail happened to render.
                        ...(Cliphist.entryIsImage(entry) ? (() => {
                            const imgNum  = (entry.match(/^\s*(\d+)/)?.[1]) || "";
                            const imgPath = `${Directories.cliphistDecode}/clip-${imgNum}.png`;
                            const escEntry = StringUtils.shellSingleQuoteEscape(entry);
                            const decode  = `mkdir -p '${Directories.cliphistDecode}'; [ -f '${imgPath}' ] || printf '${escEntry}' | ${Cliphist.cliphistBinary} decode > '${imgPath}'`;
                            return [resultComp.createObject(null, {
                                name: Translation.tr("Copy path"),
                                iconName: "link",
                                iconType: LauncherSearchResult.IconType.Material,
                                execute: () => {
                                    Quickshell.execDetached(["bash", "-c",
                                        `${decode}; printf '%s' '${imgPath}' | wl-copy`]);
                                }
                            }), resultComp.createObject(null, {
                                name: Translation.tr("Open in file manager"),
                                iconName: "folder_open",
                                iconType: LauncherSearchResult.IconType.Material,
                                execute: () => {
                                    // Prefer Dolphin (selects the file); fall back
                                    // to the default opener on the containing dir.
                                    // execDetached already detaches, so no & needed
                                    // and the command -v fallback works correctly.
                                    Quickshell.execDetached(["bash", "-c",
                                        `${decode}; if command -v dolphin >/dev/null 2>&1; then dolphin --select '${imgPath}'; else xdg-open '${Directories.cliphistDecode}'; fi`]);
                                }
                            })];
                        })() : []),
                        resultComp.createObject(null, {
                            name: Translation.tr("Delete"),
                            iconName: "delete",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Cliphist.deleteEntry(entry);
                            }
                        })],
                    blurImage: shouldBlurImage
                });
            }).filter(Boolean);
        } else if (root.query.startsWith(Config.options.search.prefix.emojis)) {
            // Clipboard
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.emojis);
            return Emojis.fuzzyQuery(searchString).map(entry => {
                const emoji = entry.match(/^\s*(\S+)/)?.[1] || "";
                return resultComp.createObject(null, {
                    rawValue: entry,
                    name: entry.replace(/^\s*\S+\s+/, ""),
                    iconName: emoji,
                    iconType: LauncherSearchResult.IconType.Text,
                    verb: Translation.tr("Copy"),
                    type: Translation.tr("Emoji"),
                    execute: () => {
                        Quickshell.clipboardText = entry.match(/^\s*(\S+)/)?.[1];
                    }
                });
            }).filter(Boolean);
        }

        ////////////////// Init ///////////////////
        nonAppResultsTimer.restart();
        const mathResultObject = resultComp.createObject(null, {
            name: root.mathResult,
            verb: Translation.tr("Copy"),
            type: Translation.tr("Math result"),
            fontType: LauncherSearchResult.FontType.Monospace,
            iconName: 'calculate',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                Quickshell.clipboardText = root.mathResult;
            }
        });
        const appResultObjects = AppSearch.fuzzyQuery(StringUtils.cleanPrefix(root.query, Config.options.search.prefix.app)).map(entry => {
            return resultComp.createObject(null, {
                type: Translation.tr("App"),
                id: entry.id,
                name: entry.name,
                iconName: entry.icon,
                iconType: LauncherSearchResult.IconType.System,
                verb: Translation.tr("Open"),
                execute: () => {
                    if (!entry.runInTerminal)
                        // Via AppLaunch: execute() forks the app from this
                        // process, so Hyprland can't attribute the launch.
                        AppLaunch.launch(entry);
                    else {
                        // Probably needs more proper escaping, but this will do for now
                        Quickshell.execDetached(["bash", '-c', `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(entry.command.join(' '))}'`]);
                    }
                },
                comment: entry.comment,
                runInTerminal: entry.runInTerminal,
                genericName: entry.genericName,
                keywords: entry.keywords,
                actions: entry.actions.map(action => {
                    return resultComp.createObject(null, {
                        name: action.name,
                        iconName: action.icon,
                        iconType: LauncherSearchResult.IconType.System,
                        execute: () => {
                            if (!action.runInTerminal)
                                action.execute();
                            else {
                                Quickshell.execDetached(["bash", '-c', `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(action.command.join(' '))}'`]);
                            }
                        }
                    });
                })
            });
        });
        const commandResultObject = resultComp.createObject(null, {
            name: StringUtils.cleanPrefix(root.query, Config.options.search.prefix.shellCommand).replace("file://", ""),
            verb: Translation.tr("Run"),
            type: Translation.tr("Command"),
            fontType: LauncherSearchResult.FontType.Monospace,
            iconName: 'terminal',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                let cleanedCommand = root.query.replace("file://", "");
                cleanedCommand = StringUtils.cleanPrefix(cleanedCommand, Config.options.search.prefix.shellCommand);
                if (cleanedCommand.startsWith(Config.options.search.prefix.shellCommand)) {
                    cleanedCommand = cleanedCommand.slice(Config.options.search.prefix.shellCommand.length);
                }
                Quickshell.execDetached(["bash", "-c", root.query.startsWith('sudo') ? `${Config.options.apps.terminal} fish -C '${cleanedCommand}'` : cleanedCommand]);
            }
        });
        const webSearchResultObject = resultComp.createObject(null, {
            name: StringUtils.cleanPrefix(root.query, Config.options.search.prefix.webSearch),
            verb: Translation.tr("Search"),
            type: Translation.tr("Web search"),
            iconName: 'travel_explore',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                let query = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.webSearch);
                let url = Config.options.search.engineBaseUrl + query;
                for (let site of Config.options.search.excludedSites) {
                    url += ` -site:${site}`;
                }
                Qt.openUrlExternally(url);
            }
        });
        // ── Launcher actions — tree navigation ───────────────────────────
        // Walks commandTree by the query tokens. A group token followed by a
        // space descends into it; a group as the last (unspaced) token shows
        // the group itself — selecting it drills in (requestQuery). A leaf
        // token consumes the rest of the line as its arguments.
        const launcherActionObjects = (() => {
            const actionPrefix = Config.options.search.prefix.action;
            if (!root.query.startsWith(actionPrefix)) return [];
            const body = root.query.slice(actionPrefix.length);
            const tokens = body.length > 0 ? body.split(" ") : [""];

            let level = root.commandTree;
            let pathPrefix = "";          // completed group path, space-terminated
            let partial = "";             // last (in-progress) token to filter by
            let targetLeaf = null;        // a fully-typed leaf, if any
            let leafArgs = "";
            let valid = true;

            // `--flag=value` is the same as `--flag value`, just typed in one
            // token. Splitting it here means every node gets the syntax for
            // free instead of each one parsing its own arguments — and for a
            // group, the value selects a subcommand, so `--shader=crt` and
            // `--shader crt` land in the same place.
            const eqSplit = tok => {
                const at = tok.indexOf("=");
                return at > 0 ? [tok.slice(0, at), tok.slice(at + 1)] : [tok, null];
            };

            for (let i = 0; i < tokens.length; i++) {
                const raw = tokens[i];
                const [token, inlineVal] = eqSplit(raw);
                const isLast = (i === tokens.length - 1);

                // A trailing `--flag=` with nothing after it should prompt with
                // the possible values rather than resolve to nothing.
                if (isLast && inlineVal === null) { partial = raw; break; }

                const child = (level ?? []).find(n => n.action === token);
                if (!child) { valid = false; break; }

                if (inlineVal !== null) {
                    if (child.sub && child.sub.length > 0) {
                        const kids = child.sub;
                        if (inlineVal.length === 0) {
                            // `--flag=` → offer the values.
                            level = kids;
                            pathPrefix += token + " ";
                            partial = "";
                            break;
                        }
                        const picked = kids.find(n => n.action === inlineVal);
                        if (picked && !(picked.sub && picked.sub.length > 0)) {
                            targetLeaf = picked;
                            leafArgs = tokens.slice(i + 1).join(" ");
                            break;
                        }
                        // Partial value: keep prompting from the value list.
                        level = kids;
                        pathPrefix += token + " ";
                        partial = inlineVal;
                        break;
                    }
                    // Leaf: the value IS the argument.
                    targetLeaf = child;
                    leafArgs = ([inlineVal].concat(tokens.slice(i + 1))).join(" ").trim();
                    break;
                }

                if (isLast) { partial = raw; break; }

                if (child.sub && child.sub.length > 0) {
                    level = child.sub;
                    pathPrefix += token + " ";
                } else {
                    targetLeaf = child;
                    leafArgs = tokens.slice(i + 1).join(" ");
                    break;
                }
            }
            if (!valid) return [];


            const makeLeaf = (n, full) => resultComp.createObject(null, {
                name: full,
                verb: Translation.tr("Run"),
                type: Translation.tr("Action"),
                comment: n.description ?? "",
                iconName: n.icon ?? 'settings_suggest',
                iconType: n.iconType ?? LauncherSearchResult.IconType.Material,
                execute: () => n.execute(leafArgs)
            });

            if (targetLeaf) {
                return [makeLeaf(targetLeaf, root.query)];
            }
            const p = partial.toLowerCase();
            return (level ?? [])
                .filter(n => n.action.toLowerCase().startsWith(p))
                .map(n => {
                    const full = actionPrefix + pathPrefix + n.action;
                    if (n.sub && n.sub.length > 0) {
                        return resultComp.createObject(null, {
                            name: full,
                            verb: Translation.tr("Open"),
                            type: Translation.tr("Group"),
                            comment: n.description ?? "",
                            iconName: n.icon ?? 'folder',
                            iconType: n.iconType ?? LauncherSearchResult.IconType.Material,
                            execute: () => root.requestQuery(full + " ")
                        });
                    }
                    return makeLeaf(n, full);
                });
        })();

        //////// Prioritized by prefix /////////
        let result = [];
        const startsWithNumber = /^\d/.test(root.query);
        const startsWithMathPrefix = root.query.startsWith(Config.options.search.prefix.math);
        const startsWithShellCommandPrefix = root.query.startsWith(Config.options.search.prefix.shellCommand);
        const startsWithWebSearchPrefix = root.query.startsWith(Config.options.search.prefix.webSearch);
        if (startsWithNumber || startsWithMathPrefix) {
            result.push(mathResultObject);
        } else if (startsWithShellCommandPrefix) {
            result.push(commandResultObject);
        } else if (startsWithWebSearchPrefix) {
            result.push(webSearchResultObject);
        }

        //////////////// Apps //////////////////
        result = result.concat(appResultObjects);

        ////////// Launcher actions ////////////
        result = result.concat(launcherActionObjects);

        /// Math result, command, web search ///
        if (Config.options.search.prefix.showDefaultActionsWithoutPrefix) {
            if (!startsWithShellCommandPrefix)
                result.push(commandResultObject);
            if (!startsWithNumber && !startsWithMathPrefix)
                result.push(mathResultObject);
            if (!startsWithWebSearchPrefix)
                result.push(webSearchResultObject);
        }

        return result;
    }

    Component {
        id: resultComp
        LauncherSearchResult {}
    }
}







