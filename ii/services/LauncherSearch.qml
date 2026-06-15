pragma Singleton

import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
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
        id: userActionsFolder
        folder: Qt.resolvedUrl(Directories.userActions)
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    // Built-in launcher commands as a TREE. A node with `sub` is a group;
    // a node with `execute` is a runnable leaf. Top-level groups keep the
    // `/` list short — the launcher navigates this with the query.
    property var searchActions: [
        {
            action: "theme",
            icon: "palette",
            description: Translation.tr("Appearance & wallpaper"),
            sub: [
                {
                    action: "dark",
                    icon: "dark_mode",
                    description: Translation.tr("Switch to dark mode"),
                    execute: () => {
                        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "dark", "--noswitch"]);
                    }
                },
                {
                    action: "light",
                    icon: "light_mode",
                    description: Translation.tr("Switch to light mode"),
                    execute: () => {
                        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "light", "--noswitch"]);
                    }
                },
                {
                    action: "accent",
                    icon: "format_color_fill",
                    description: Translation.tr("Set the accent color from a hex value"),
                    execute: args => {
                        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--color", ...(args != '' ? [`${args}`] : [])]);
                    }
                },
                {
                    action: "pick",
                    icon: "wallpaper",
                    description: Translation.tr("Open the wallpaper picker"),
                    execute: () => {
                        GlobalStates.wallpaperSelectorOpen = true;
                    }
                },
                {
                    action: "random",
                    icon: "image_search",
                    description: Translation.tr("Set a random Konachan wallpaper"),
                    execute: () => {
                        Quickshell.execDetached([Quickshell.shellPath("scripts/colors/random/random_konachan_wall.sh")]);
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
                    action: "paste",
                    icon: "content_paste_go",
                    description: Translation.tr("Paste the last N clipboard entries"),
                    execute: args => {
                        if (!/^(\d+)/.test(args.trim())) {
                            // Invalid if doesn't start with numbers
                            Quickshell.execDetached(["notify-send", Translation.tr("Superpaste"), Translation.tr("Usage: <tt>%1clip paste NUM_OF_ENTRIES[i]</tt>\nSupply <tt>i</tt> when you want images\nExamples:\n<tt>%1clip paste 4i</tt> for the last 4 images\n<tt>%1clip paste 7</tt> for the last 7 entries").arg(Config.options.search.prefix.action), "-a", "Shell"]);
                            return;
                        }
                        const syntaxMatch = /^(?:(\d+)(i)?)/.exec(args.trim());
                        const count = syntaxMatch[1] ? parseInt(syntaxMatch[1]) : 1;
                        const isImage = !!syntaxMatch[2];
                        Cliphist.superpaste(count, isImage);
                    }
                },
                {
                    action: "wipe",
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
                { action: "lock",     icon: "lock",               description: Translation.tr("Lock the session"),    execute: () => Quickshell.execDetached(["loginctl", "lock-session"]) },
                { action: "logout",   icon: "logout",             description: Translation.tr("Log out of Hyprland"), execute: () => Quickshell.execDetached(["hyprctl", "dispatch", "exit"]) },
                { action: "suspend",  icon: "bedtime",            description: Translation.tr("Suspend the system"),  execute: () => Quickshell.execDetached(["systemctl", "suspend"]) },
                { action: "reboot",   icon: "restart_alt",        description: Translation.tr("Restart the system"),  execute: () => Quickshell.execDetached(["systemctl", "reboot"]) },
                { action: "shutdown", icon: "power_settings_new", description: Translation.tr("Power off"),           execute: () => Quickshell.execDetached(["systemctl", "poweroff"]) },
            ]
        },
        {
            action: "system",
            icon: "settings",
            description: Translation.tr("System"),
            sub: [
                { action: "reload", icon: "refresh", description: Translation.tr("Reload the Hyprland config"), execute: () => Quickshell.execDetached(["hyprctl", "reload"]) },
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
    ]

    // Normalise a Config command ({ name, icon, description, exec, sub })
    // into the internal { action, icon, description, execute/sub } shape.
    function mapConfigCommand(c) {
        const node = {
            action: c.name,
            icon: c.icon ?? "terminal",
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
                        }), resultComp.createObject(null, {
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
                        entry.execute();
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

            for (let i = 0; i < tokens.length; i++) {
                const token = tokens[i];
                if (i === tokens.length - 1) { partial = token; break; }
                const child = (level ?? []).find(n => n.action === token);
                if (child && child.sub && child.sub.length > 0) {
                    level = child.sub;
                    pathPrefix += token + " ";
                } else if (child) {
                    targetLeaf = child;
                    leafArgs = tokens.slice(i + 1).join(" ");
                    break;
                } else {
                    valid = false; break;
                }
            }
            if (!valid) return [];

            const makeLeaf = (n, full) => resultComp.createObject(null, {
                name: full,
                verb: Translation.tr("Run"),
                type: Translation.tr("Action"),
                comment: n.description ?? "",
                iconName: n.icon ?? 'settings_suggest',
                iconType: LauncherSearchResult.IconType.Material,
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
                            iconType: LauncherSearchResult.IconType.Material,
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
