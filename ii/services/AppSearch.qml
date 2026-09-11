pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import qs.services

/**
 * - Eases fuzzy searching for applications by name
 * - Guesses icon name for window class name
 */
Singleton {
    id: root
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property var substitutions: ({
        "code-url-handler": "visual-studio-code",
        "Code": "visual-studio-code",
        "gnome-tweaks": "org.gnome.tweaks",
        "pavucontrol-qt": "pavucontrol",
        "wps": "wps-office2019-kprometheus",
        "wpsoffice": "wps-office2019-kprometheus",
        "footclient": "foot",
    })
    property var regexSubstitutions: [
        {
            "regex": /^steam_app_(\d+)$/,
            "replace": "steam_icon_$1"
        },
        {
            "regex": /Minecraft.*/,
            "replace": "minecraft"
        },
        {
            "regex": /.*polkit.*/,
            "replace": "system-lock-screen"
        },
        {
            "regex": /gcr.prompter/,
            "replace": "system-lock-screen"
        }
    ]

    // Deduped list to fix double icons
    readonly property list<DesktopEntry> list: Array.from(DesktopEntries.applications.values)
        .filter((app, index, self) => 
            index === self.findIndex((t) => (
                t.id === app.id
            ))
    )
    
    readonly property var preppedNames: list.map(a => ({
        name: Fuzzy.prepare(`${a.name} `),
        entry: a
    }))

    readonly property var preppedIcons: list.map(a => ({
        name: Fuzzy.prepare(`${a.icon} `),
        entry: a
    }))

    /**
     * Score every app against `search`, then hand the scored list to
     * LauncherRanking to be ordered by the user's chosen sort mode.
     *
     * The match score is kept all the way through rather than being collapsed
     * into an order here: "relevance" needs it as the primary key, and every
     * other mode still wants it as a tiebreak. Returns a bare DesktopEntry[]
     * so callers are unchanged.
     *
     * Note fuzzysort is passed `all: true`, so an EMPTY search returns every
     * app in raw list order with no scoring — which is precisely the case
     * where a usage-based sort earns its keep.
     */
    // Match only — no user preferences applied. Returns [{entry, score}] in
    // best-match-first order.
    function scoreQuery(search: string): var {
        if (root.sloppySearch) {
            return list.map(obj => ({
                entry: obj,
                score: Levendist.computeScore(obj.name.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
        }
        return Fuzzy.go(search, preppedNames, {
            all: true,
            key: "name"
        }).map(r => ({ entry: r.obj.entry, score: r.score ?? 0 }))
    }

    // Pure relevance, no ranking and no hiding. Used by guessIcon(), which
    // wants the best NAME match — applying the user's frecency order there
    // would hand back whatever they launch most, and filtering hidden entries
    // would lose icons for apps deliberately kept out of the launcher.
    function relevanceQuery(search: string): var {
        return root.scoreQuery(search).map(item => item.entry)
    }

    function fuzzyQuery(search: string): var { // Idk why list<DesktopEntry> doesn't work
        let scored = root.scoreQuery(search)

        if (!(Config.options?.launcher?.showTerminalApps ?? true))
            scored = scored.filter(it => !it.entry?.runInTerminal)

        return LauncherRanking.apply(scored, Config.options?.launcher?.sortMode, {
            showHidden:  Config.options?.launcher?.showHidden ?? false,
            usePriority: Config.options?.launcher?.usePriorityBoost ?? true,
            reverse:     Config.options?.launcher?.reverseSort ?? false,
        }).map(item => item.entry)
    }

    function iconExists(iconName) {
        if (!iconName || iconName.length == 0) return false;
        return (Quickshell.iconPath(iconName, true).length > 0)
            && !iconName.includes("image-missing");
    }

    // Like iconExists, but lets a literal path through — a desktop entry may
    // point at a file rather than a theme name, and iconPath can't vouch for
    // those.
    function iconUsable(iconName) {
        if (!iconName || iconName.length == 0) return false;
        if (iconName.startsWith("/") || iconName.startsWith("file:")) return true;
        return root.iconExists(iconName);
    }

    // Resolved icons, keyed by what was asked for. guessIcon ends in fuzzy
    // name matching, so its answer depends on how much of DesktopEntries has
    // loaded — the same window could get one icon at startup and another a
    // second later, which is the flicker. Memoising freezes the first good
    // answer. Cleared whenever the entry list changes, so installing an app
    // still takes effect, and failures are never cached.
    property var iconCache: ({})
    onListChanged: root.iconCache = ({})

    function getReverseDomainNameAppName(str) {
        return str.split('.').slice(-1)[0]
    }

    function getKebabNormalizedAppName(str) {
        return str.toLowerCase().replace(/\s+/g, "-");
    }

    function getUndescoreToKebabAppName(str) {
        return str.toLowerCase().replace(/_/g, "-");
    }

    function guessIcon(str) {
        if (!str || str.length == 0) return "image-missing";

        const cached = root.iconCache[str];
        if (cached !== undefined) return cached;

        const guess = root.resolveIcon(str);
        // Never cache a give-up: entries may still be loading, and freezing
        // the fallback would make it permanent for the session.
        if (guess !== "application-x-executable" && guess !== "image-missing")
            root.iconCache[str] = guess;
        return guess;
    }

    function resolveIcon(str) {
        // Quickshell's desktop entry lookup
        const entry = DesktopEntries.byId(str);
        if (entry && root.iconUsable(entry.icon)) return entry.icon;

        // Normal substitutions
        if (substitutions[str]) return substitutions[str];
        if (substitutions[str.toLowerCase()]) return substitutions[str.toLowerCase()];

        // Regex substitutions
        for (let i = 0; i < regexSubstitutions.length; i++) {
            const substitution = regexSubstitutions[i];
            const replacedName = str.replace(
                substitution.regex,
                substitution.replace,
            );
            if (replacedName != str) return replacedName;
        }

        // Icon exists -> return as is
        if (iconExists(str)) return str;


        // Simple guesses
        const lowercased = str.toLowerCase();
        if (iconExists(lowercased)) return lowercased;

        const reverseDomainNameAppName = getReverseDomainNameAppName(str);
        if (iconExists(reverseDomainNameAppName)) return reverseDomainNameAppName;

        const lowercasedDomainNameAppName = reverseDomainNameAppName.toLowerCase();
        if (iconExists(lowercasedDomainNameAppName)) return lowercasedDomainNameAppName;

        const kebabNormalizedGuess = getKebabNormalizedAppName(str);
        if (iconExists(kebabNormalizedGuess)) return kebabNormalizedGuess;

        const undescoreToKebabGuess = getUndescoreToKebabAppName(str);
        if (iconExists(undescoreToKebabGuess)) return undescoreToKebabGuess;

        // Quickshell's own appId → entry heuristic. Deliberately BEFORE the
        // fuzzy passes below, which is the opposite of the order this used to
        // run in, and the reason icons sometimes disagreed with KDE's.
        //
        // byId() misses more often than it looks: Hyprland reports a window
        // class that is frequently not the desktop-entry id (Bitwig reports
        // "com.bitwig.BitwigStudi" for "com.bitwig.BitwigStudio"). Every one of
        // those misses used to fall through to a fuzzy NAME search, which
        // always answers with something — the best-scoring entry, not
        // necessarily this app's — so a near-miss silently became a confident
        // wrong icon. KDE resolves the entry properly and gets the right one.
        //
        // heuristicLookup is the principled matcher, so it goes ahead of the
        // guesswork; fuzzy stays as the last resort before giving up.
        const heuristicEntry = DesktopEntries.heuristicLookup(str);
        if (heuristicEntry && root.iconUsable(heuristicEntry.icon)) return heuristicEntry.icon;

        // Fuzzy search over desktop entries — last resort. These can and do
        // return an unrelated app, so nothing principled may come after them.
        const iconSearchResults = Fuzzy.go(str, preppedIcons, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
        if (iconSearchResults.length > 0) {
            const guess = iconSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        const nameSearchResults = root.relevanceQuery(str);
        if (nameSearchResults.length > 0) {
            const guess = nameSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        // Give up
        return "application-x-executable";
    }
}
