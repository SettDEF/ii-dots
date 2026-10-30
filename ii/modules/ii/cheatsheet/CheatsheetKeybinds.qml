pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    /// Sub-category: "desktop" (Hyprland), or an app id from AppKeybinds
    /// (tmux, wezterm, …). Searching looks through ALL of them, unless an app
    /// was picked while searching (`scope`): then only that one.
    property string app: "desktop"
    property string scope: ""
    readonly property var appEntry: AppKeybinds.apps.find(a => a.id === root.app) ?? null
    readonly property var keybinds: {
        const searching = (root._q ?? "").trim().length > 0;
        if (!searching && root.app !== "desktop")
            return { children: (root.appEntry?.sections ?? []).map(s => ({ name: s.name, keybinds: s.keybinds, children: [] })) };
        if (!searching) return HyprlandKeybinds.keybinds;
        // search: the desktop's sections, then every app's, named "tmux · Panes"
        if (root.scope === "desktop") return HyprlandKeybinds.keybinds;
        const out = root.scope ? [] : (HyprlandKeybinds.keybinds?.children ?? []).slice();
        for (const a of AppKeybinds.apps.filter(a => !root.scope || a.id === root.scope))
            for (const s of a.sections)
                out.push({ name: `${a.name} · ${s.name}`, keybinds: s.keybinds, children: [] });
        return { children: out };
    }
    property real spacing: 20
    property real titleSpacing: 7
    property real padding: 4
    /// Cap, or one bind whose comment is a command line sets the column width.
    property real maxCommentWidth: 300
    /// The visible width (the scroll view's), which the columns can exceed:
    /// the app chips centre in what you see, not over the whole content.
    property real viewWidth: width
    /// Where the app bar floats (the page's scroll view); null = inline.
    property Item floatHost: null

    /// Height to fit in, set by the host. 0 = unknown.
    property real heightBudget: 0

    // Sections are flattened out of the source and repacked into as many
    // columns as the height needs, rather than taking the source's grouping.
    // Measured, not estimated: hidden instances of the things being measured,
    // so the arithmetic cannot drift from the fonts.
    readonly property real rowHeight: rowMeasure.implicitHeight + 4   // + GridLayout.rowSpacing
    readonly property real sectionTitleHeight: titleMeasure.implicitHeight + root.titleSpacing

    KeyboardKey {
        id: rowMeasure
        visible: false
        key: "M"
        pixelSize: Config.options.cheatsheet.fontSize.key
    }
    StyledText {
        id: titleMeasure
        visible: false
        text: "M"
        font {
            family: Appearance.font.family.title
            pixelSize: Appearance.font.pixelSize.title
            variableAxes: Appearance.font.variableAxes.title
        }
    }

    function _flatten(node, out) {
        if (!node) return out;
        if ((node.keybinds?.length ?? 0) > 0) out.push(node);
        for (const c of (node.children ?? [])) root._flatten(c, out);
        return out;
    }

    readonly property var flatSections: root._flatten({ children: root.keybinds?.children ?? [] }, [])

    // ── search: the settings app's matcher (fuzzysort), one ranking ──
    /// Set by the search field in the cheatsheet header (Cheatsheet.qml).
    property string query: ""

    /// The query the results follow: settles 150 ms after the last
    /// keystroke, so typing does not re-rank and re-lay-out the whole sheet
    /// on every letter (it lagged).
    property string _q: ""
    onQueryChanged: if (query.trim() === "") { qDebounce.stop(); _q = ""; scope = ""; } else qDebounce.restart()
    Timer { id: qDebounce; interval: 150; onTriggered: root._q = root.query }

    // Names people type for the same key or action. A query word in a group
    // finds every word of it, so "win" finds Super, "screenshot" finds a bind
    // labelled "capture", "close" finds "kill".
    readonly property var keyAliases: ({
        "win": "super", "windows": "super", "mod": "super", "meta": "super", "cmd": "super", "logo": "super",
        "control": "ctrl", "strg": "ctrl", "ctl": "ctrl", "option": "alt", "opt": "alt",
        "enter": "return", "esc": "escape", "del": "delete", "bksp": "backspace", "spc": "space",
        "pgup": "page_up", "pgdn": "page_down", "lmb": "mouse:272", "rmb": "mouse:273"
    })
    readonly property var actionGroups: [
        ["screenshot", "capture", "grim", "snip", "region", "screen shot"],
        ["record", "recording", "screencast", "cast", "video"],
        ["close", "kill", "quit", "exit"],
        ["terminal", "term", "kitty", "foot", "wezterm", "console", "shell"],
        ["volume", "audio", "sound", "mute", "speaker"],
        ["mic", "microphone"],
        ["brightness", "backlight", "screen light"],
        ["workspace", "desktop", "virtual desktop"],
        ["fullscreen", "maximize", "maximise"],
        ["float", "floating", "tiling", "tile"],
        ["clipboard", "clip", "paste", "copy"],
        ["launcher", "search", "apps", "run", "overview"],
        ["lock", "lockscreen", "screen lock"],
        ["move", "drag", "send"],
        ["focus", "switch", "select"],
        ["media", "music", "play", "pause", "next", "previous", "track"],
        ["notification", "notifications", "notify"],
        ["power", "shutdown", "reboot", "logout", "session"],
        ["emoji", "emojis", "symbol"],
        ["color", "colour", "picker", "colorpicker"],
        ["wallpaper", "background"],
    ]
    function _norm(t) { return String(t ?? "").toLowerCase(); }
    /// Text plus its words run together ("scroll bar" → "scrollbar"), like settings.
    function _sq(t) { return t + " " + t.replace(/\s+/g, ""); }

    /// Every bind, prepared once (not per keystroke).
    readonly property var haystack: {
        const out = [];
        for (const sec of root.flatSections) {
            for (const kb of sec.keybinds) {
                const mods = (kb.mods ?? []).map(m => root._norm(m));
                const key = root._norm(kb.key);
                const comment = String(kb.comment ?? "");
                const lc = comment.toLowerCase();
                const extra = root.actionGroups.filter(g => g.some(w => lc.includes(w))).map(g => g.join(" ")).join(" ");
                const words = s => String(s).toLowerCase().split(/[^a-z0-9#]+/).filter(w => w);
                out.push({
                    kb, section: sec.name ?? "",
                    lc,
                    commentWords: words(comment),
                    otherWords: words(`${sec.name ?? ""} ${extra}`),
                    keyWords: mods.concat([key]).map(k => k.toLowerCase()),
                    combo: new Set(mods.concat([key])),
                    commentKey: Fuzzy.prepare(comment),
                    comboKey: Fuzzy.prepare(mods.concat([key]).join(" ") + " " + mods.concat([key]).join("+")),
                    allKey: Fuzzy.prepare(root._sq(`${comment} ${sec.name ?? ""} ${extra}`))
                });
            }
        }
        return out;
    }

    /// The query with key aliases spelled the way binds store them.
    function _canon(q) {
        return q.toLowerCase().split(/[\s+]+/).filter(t => t).map(t => root.keyAliases[t] ?? t);
    }
    /// fuzzysort's highlight, made safe for rich text (the label may hold < or &).
    function _highlight(res, text) {
        if (!res) return "";
        const marked = Fuzzy.highlight(res, "\u0001", "\u0002") || text;
        const esc = marked.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        return esc.replace(/\u0001/g, `<b><font color="${Appearance.colors.colPrimary}">`).replace(/\u0002/g, "</font></b>");
    }

    readonly property var shownSections: {
        const q = root._q.trim();
        if (!q) return root.flatSections;
        const terms = root._canon(q);
        // a typed key combination ("super shift s", "ctrl+alt+t"): exactly
        // those keys, first
        const comboHits = new Set(root.haystack.filter(h => terms.length > 1 && terms.length === h.combo.size && terms.every(t => h.combo.has(t))));
        const query = terms.join(" ");

        // Strict first: EVERY typed word must match a word of the bind — its
        // label, its section, an alias group, or one of its keys. Whole words
        // beat word starts beat text inside a word, the label beats the rest,
        // and the exact phrase in the label beats everything. The old loose
        // fuzzy pass let letters scattered across unrelated words count as a
        // hit, which is what made results look random.
        const strict = [];
        for (const h of root.haystack) {
            if (comboHits.has(h)) continue;
            let score = 0, ok = true;
            for (const t of terms) {
                let best = 0;
                for (const w of h.commentWords) {
                    if (w === t) best = Math.max(best, 100);
                    else if (w.startsWith(t)) best = Math.max(best, 70 + 20 * t.length / w.length);
                    else if (t.length >= 3 && w.includes(t)) best = Math.max(best, 35);
                }
                for (const w of h.otherWords) {
                    if (w === t) best = Math.max(best, 45);
                    else if (w.startsWith(t)) best = Math.max(best, 30);
                }
                for (const k of h.keyWords) if (k === t) best = Math.max(best, 55);
                if (best === 0) { ok = false; break; }
                score += best;
            }
            if (!ok) continue;
            if (terms.length > 1 && h.lc.includes(terms.join(" "))) score += 150;
            if (h.lc.startsWith(terms[0])) score += 20;
            score -= h.lc.length * 0.05;   // a short label that matches is the more specific one
            strict.push({ h, s: score });
        }

        const ranked = [];
        for (const h of comboHits) ranked.push({ h, s: 1e9, res: null });
        if (strict.length > 0) {
            strict.sort((a, b) => b.s - a.s);
            for (const it of strict)
                // fuzzysort over just this bind's label, for the highlight
                ranked.push({ h: it.h, s: it.s, res: Fuzzy.go(query, [it.h], { key: "commentKey", threshold: -100000 })[0] ?? null });
        } else {
            // nothing matched word for word: a typo. Fuzzy, but tight — the
            // label only, and only close matches.
            const hits = Fuzzy.go(query, root.haystack, {
                all: false,
                keys: ["commentKey", "comboKey"],
                threshold: -1200,
                scoreFn: a => Math.max(a[0] ? a[0].score : -9999, a[1] ? a[1].score - 100 : -9999)
            });
            for (const r of hits) {
                if (comboHits.has(r.obj)) continue;
                ranked.push({ h: r.obj, s: r.score - 1e6, res: r[0] });
            }
        }
        // sections in order of their best hit, binds in order of score
        const bySec = new Map();
        for (const it of ranked) {
            const name = it.h.section;
            if (!bySec.has(name)) bySec.set(name, { best: it.s, list: [] });
            const kb = Object.assign({}, it.h.kb);
            if (it.res) kb._hl = root._highlight(it.res, String(it.h.kb.comment ?? ""));
            bySec.get(name).list.push(kb);
        }
        const out = [];
        for (const sec of root.flatSections) {
            const e = bySec.get(sec.name ?? "");
            if (e) out.push(Object.assign({}, sec, { keybinds: e.list, _best: e.best }));
        }
        out.sort((x, y) => y._best - x._best);
        return out;
    }
    readonly property int matchCount: shownSections.reduce((n, s) => n + s.keybinds.length, 0)

    readonly property var packedColumns: {
        const secs = root.shownSections;
        if (secs.length === 0) return [];
        // No budget yet: one column per section, so frame one is not wrong.
        if (root.heightBudget <= 100)
            return secs.map(s => ({ name: "", keybinds: [], children: [s] }));

        const height = s => root.sectionTitleHeight + s.keybinds.length * root.rowHeight;
        const total = secs.reduce((n, s) => n + height(s) + root.spacing, 0);
        // Ceil, so the last column is the short one rather than everything
        // overflowing by a row.
        const columns = Math.max(1, Math.ceil(total / root.heightBudget));
        const target = total / columns;

        const out = [];
        let current = null;
        let used = 0;
        for (const s of secs) {
            if (current === null) {
                current = { name: "", keybinds: [], children: [] };
                out.push(current);
                used = 0;
            }
            current.children.push(s);
            used += height(s) + root.spacing;
            // Break AFTER filling: testing first strands an oversized section.
            if (used >= target && out.length < columns) current = null;
        }
        return out;
    }
    implicitWidth: contentCol.implicitWidth + padding * 2
    implicitHeight: contentCol.implicitHeight + padding * 2
    // Excellent symbol explaination and source :
    // http://xahlee.info/comp/unicode_computing_symbols.html
    // https://www.nerdfonts.com/cheat-sheet
    property var macSymbolMap: ({
        "Ctrl": "󰘴",
        "Alt": "󰘵",
        "Shift": "󰘶",
        "Space": "󱁐",
        "Tab": "↹",
        "Equal": "󰇼",
        "Minus": "",
        "Print": "",
        "BackSpace": "󰭜",
        "Delete": "⌦",
        "Return": "󰌑",
        "Period": ".",
        "Escape": "⎋"
      })
    property var functionSymbolMap: ({
        "F1":  "󱊫",
        "F2":  "󱊬",
        "F3":  "󱊭",
        "F4":  "󱊮",
        "F5":  "󱊯",
        "F6":  "󱊰",
        "F7":  "󱊱",
        "F8":  "󱊲",
        "F9":  "󱊳",
        "F10": "󱊴",
        "F11": "󱊵",
        "F12": "󱊶",
    })

    property var mouseSymbolMap: ({
        "mouse_up": "󱕐",
        "mouse_down": "󱕑",
        "mouse:272": "L󰍽",
        "mouse:273": "R󰍽",
        "Scroll ↑/↓": "󱕒",
        "Page_↑/↓": "⇞/⇟",
    })

    property var keyBlacklist: ["Super_L"]
    property var keySubstitutions: Object.assign({
        "Super": "",
        "mouse_up": "Scroll ↓",    // ikr, weird
        "mouse_down": "Scroll ↑",  // trust me bro
        "mouse:272": "LMB",
        "mouse:273": "RMB",
        "mouse:275": "MouseBack",
        "Slash": "/",
        "Hash": "#",
        "Return": "Enter",
        // "Shift": "",
      },
      !!Config.options.cheatsheet.superKey ? {
          "Super": Config.options.cheatsheet.superKey,
      }: {},
      Config.options.cheatsheet.useMacSymbol ? macSymbolMap : {},
      Config.options.cheatsheet.useFnSymbol ? functionSymbolMap : {},
      Config.options.cheatsheet.useMouseSymbol ? mouseSymbolMap : {},
    )

    // Layout-aware: resolve a raw key (notably `code:NN`) to the label of
    // the active/selected keyboard layout, then apply the substitutions.
    function displayKey(raw) {
        const resolved = KeyboardLayout.resolveKey(raw)
        // a key the layout cannot resolve (", !, …) shows as it is
        return keySubstitutions[resolved] || resolved || String(raw ?? "")
    }

    Column {
        id: contentCol
        anchors.centerIn: parent
        spacing: 14

        // ── Sub-categories: the desktop, then each app keybinds-sync found ──
        // A floating bar at the bottom of the visible page: taken out of the
        // scrolling column (parent: floatHost) so it stays put while the
        // keybinds scroll under it.
        Rectangle {
            id: appDock
            parent: root.floatHost ?? contentCol
            z: 10
            visible: AppKeybinds.apps.length > 0
            anchors.horizontalCenter: root.floatHost ? parent.horizontalCenter : undefined
            anchors.bottom: root.floatHost ? parent.bottom : undefined
            anchors.bottomMargin: 14
            implicitWidth: appChips.implicitWidth + 12
            implicitHeight: appChips.implicitHeight + 12
            // too many apps for the width: the others shrink to their icon (name on hover), the open one keeps it
            readonly property var entries: [{ id: "desktop", name: Translation.tr("Desktop"), icon: "desktop_windows" }].concat(AppKeybinds.apps)
            readonly property real roomy: entries.reduce((w, e) => w + 49 + String(e.name).length * 8.5 + 6, 0) + 52
            readonly property bool compact: roomy > (parent ? parent.width - 28 : 9999)
            // the wheel over the bar goes to the next or previous app
            WheelHandler {
                onWheel: (ev) => {
                    const ids = appDock.entries.map(e => e.id);
                    const i = Math.max(0, ids.indexOf(root.app));
                    root.app = ids[(i + (ev.angleDelta.y < 0 || ev.angleDelta.x < 0 ? 1 : ids.length - 1)) % ids.length];
                }
            }
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        Row {
            id: appChips
            anchors.centerIn: parent
            spacing: 6
            Repeater {
                model: appDock.entries
                delegate: Rectangle {
                    id: appChip
                    required property var modelData
                    // searching: lit when the search is narrowed to it; else the app shown
                    readonly property bool sel: (root._q ?? "").trim() === "" ? root.app === appChip.modelData.id : root.scope === appChip.modelData.id
                    readonly property bool labelled: appChip.sel || !appDock.compact
                    implicitWidth: appChipRow.implicitWidth + (appChip.labelled ? 26 : 17)
                    implicitHeight: 34
                    radius: Appearance.rounding.full
                    color: appChip.sel ? Appearance.colors.colPrimary
                         : appChipHover.hovered ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                    HoverHandler { id: appChipHover; cursorShape: Qt.PointingHandCursor }
                    // while searching: narrows the search to this app; again: every app
                    TapHandler { onTapped: { root.app = appChip.modelData.id; if ((root.query ?? "").trim() !== "") root.scope = root.scope === appChip.modelData.id ? "" : appChip.modelData.id; } }
                    StyledToolTip {
                        extraVisibleCondition: false
                        alternativeVisibleCondition: appChipHover.hovered && !appChip.labelled
                        text: appChip.modelData.name
                    }
                    Row {
                        id: appChipRow
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: appChip.modelData.icon
                            iconSize: 17
                            fill: appChip.sel ? 1 : 0
                            color: appChip.sel ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            visible: appChip.labelled
                            anchors.verticalCenter: parent.verticalCenter
                            text: appChip.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: appChip.sel ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }
                    }
                }
            }
            // re-collect now (normally automatic when an app's config changes)
            Rectangle {
                implicitWidth: 34
                implicitHeight: 34
                radius: 17
                color: syncHover.hovered ? Appearance.colors.colLayer2 : "transparent"
                HoverHandler { id: syncHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: AppKeybinds.sync() }
                MaterialSymbol { anchors.centerIn: parent; text: "sync"; iconSize: 17; color: Appearance.colors.colSubtext }
                StyledToolTip {
                    extraVisibleCondition: false
                    alternativeVisibleCondition: syncHover.hovered
                    text: Translation.tr("Read the apps' keybinds again (happens by itself when their config changes)")
                }
            }
        }
        }
        // the app's own key words: "Prefix = Ctrl+Space", "Leader = Ctrl+Q"
        StyledText {
            x: Math.max(-contentCol.x, (root.viewWidth - width) / 2 - contentCol.x)
            visible: root.app !== "desktop" && (root.appEntry?.note ?? "") !== "" && (root._q ?? "").trim() === ""
            text: root.appEntry?.note ?? ""
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        // ── Keyboard-layout badge ─────────────────────────────────────
        // Click to cycle: Auto → each configured layout → Auto.
        Rectangle {
            id: layoutChip
            readonly property bool switchable: KeyboardLayout.availableLayouts.length > 1
            // With one layout there is nothing to switch to, so it is inert.
            // The layout is still shown in Settings > System > Keyboard.
            visible: layoutChip.switchable
            readonly property int layoutIndex: KeyboardLayout.availableLayouts.indexOf(KeyboardLayout.effectiveLayout)
            readonly property string variantSuffix: (layoutIndex >= 0
                && KeyboardLayout.availableVariants[layoutIndex])
                ? " (" + KeyboardLayout.availableVariants[layoutIndex] + ")" : ""
            implicitWidth: chipRow.implicitWidth + 22
            implicitHeight: chipRow.implicitHeight + 12
            radius: Appearance.rounding.full
            color: chipArea.containsMouse && layoutChip.switchable
                ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 7

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "keyboard"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer0
                    text: (KeyboardLayout.isAuto ? qsTr("Auto · ") : "")
                        + KeyboardLayout.effectiveLayout.toUpperCase()
                        + layoutChip.variantSuffix
                }
                StyledText {
                    visible: layoutChip.switchable
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.5
                    text: "▾"
                }
            }

            MouseArea {
                id: chipArea
                anchors.fill: parent
                enabled: layoutChip.switchable
                hoverEnabled: true
                cursorShape: layoutChip.switchable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: KeyboardLayout.cycleLayout()
            }

            StyledToolTip {
                extraVisibleCondition: false
                alternativeVisibleCondition: chipArea.containsMouse
                text: Translation.tr("Which keyboard layout these keys are shown for. Binds written as a key CODE resolve differently per layout, so this is what makes them read correctly.\nClick to switch.")
            }
        }

        Row { // Keybind columns
            id: row
            spacing: root.spacing

            Repeater {
                model: root.packedColumns

                delegate: Column { // Keybind sections
                    spacing: root.spacing
                    required property var modelData
                    anchors.top: row.top

                    Repeater {
                        model: modelData.children

                        delegate: Item { // Section with real keybinds
                            id: keybindSection
                            required property var modelData
                            implicitWidth: sectionColumn.implicitWidth
                            implicitHeight: sectionColumn.implicitHeight

                            Column {
                                id: sectionColumn
                                anchors.centerIn: parent
                                spacing: root.titleSpacing

                                StyledText {
                                    id: sectionTitle
                                    font {
                                        family: Appearance.font.family.title
                                        pixelSize: Appearance.font.pixelSize.title
                                        variableAxes: Appearance.font.variableAxes.title
                                    }
                                    color: Appearance.colors.colOnLayer0
                                    text: keybindSection.modelData.name
                                }

                                GridLayout {
                                    id: keybindGrid
                                    columns: 2
                                    columnSpacing: 4
                                    rowSpacing: 4

                                    Repeater {
                                        model: {
                                            // Touch codeToKey so the grid rebuilds
                                            // when the keyboard layout changes.
                                            void KeyboardLayout.codeToKey;
                                            var result = [];
                                            for (var i = 0; i < keybindSection.modelData.keybinds.length; i++) {
                                                const keybind = keybindSection.modelData.keybinds[i];
                                                const showKey = !root.keyBlacklist.includes(keybind.key);

                                                if (!Config.options.cheatsheet.splitButtons) {
                                                    var mods = [];
                                                    for (var j = 0; j < keybind.mods.length; j++) {
                                                        mods.push(root.displayKey(keybind.mods[j]));
                                                    }
                                                    var joined = mods.join(' ');
                                                    if (showKey && joined.length) joined += ' ';
                                                    if (showKey) joined += root.displayKey(keybind.key);
                                                    result.push({
                                                        "type": "keys",
                                                        "mods": [joined],
                                                        "key": keybind.key,
                                                    });
                                                } else {
                                                    result.push({
                                                        "type": "keys",
                                                        "mods": keybind.mods,
                                                        "key": keybind.key,
                                                    });
                                                }
                                                result.push({
                                                    "type": "comment",
                                                    "comment": keybind.comment,
                                                    "hl": keybind._hl ?? "",
                                                });
                                            }
                                            return result;
                                        }
                                        delegate: Item {
                                            required property var modelData
                                            implicitWidth: keybindLoader.implicitWidth
                                            implicitHeight: keybindLoader.implicitHeight

                                            Loader {
                                                id: keybindLoader
                                                sourceComponent: (modelData.type === "keys") ? keysComponent : commentComponent
                                            }

                                            Component {
                                                id: keysComponent
                                                Row {
                                                    spacing: 4
                                                    Repeater {
                                                        model: modelData.mods
                                                        delegate: KeyboardKey {
                                                            required property var modelData
                                                            key: root.displayKey(modelData)
                                                            pixelSize: Config.options.cheatsheet.fontSize.key
                                                        }
                                                    }
                                                    StyledText {
                                                        id: keybindPlus
                                                        visible: Config.options.cheatsheet.splitButtons && !root.keyBlacklist.includes(modelData.key) && modelData.mods.length > 0
                                                        text: "+"
                                                    }
                                                    KeyboardKey {
                                                        id: keybindKey
                                                        visible: Config.options.cheatsheet.splitButtons && !root.keyBlacklist.includes(modelData.key)
                                                        key: root.displayKey(modelData.key)
                                                        pixelSize: Config.options.cheatsheet.fontSize.key
                                                        color: Appearance.colors.colOnLayer0
                                                    }
                                                }
                                            }

                                            Component {
                                                id: commentComponent
                                                Item {
                                                    id: commentItem
                                                    // Left-aligned: a GridLayout column is as wide
                                                    // as its widest cell, and centring in that
                                                    // strands every short label mid-gap.
                                                    implicitWidth: Math.min(commentText.implicitWidth, root.maxCommentWidth) + 8
                                                    implicitHeight: commentText.implicitHeight

                                                    StyledText {
                                                        id: commentText
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 8
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        // Capped: a command-line label runs off-window.
                                                        width: Math.min(implicitWidth, root.maxCommentWidth)
                                                        elide: Text.ElideRight
                                                        font.pixelSize: Config.options.cheatsheet.fontSize.comment || Appearance.font.pixelSize.smaller
                                                        // the matched letters lit while searching
                                                        textFormat: modelData.hl ? Text.StyledText : Text.PlainText
                                                        text: modelData.hl || modelData.comment

                                                        StyledToolTip {
                                                            extraVisibleCondition: false
                                                            alternativeVisibleCondition: commentHover.hovered
                                                                && commentText.implicitWidth > root.maxCommentWidth
                                                            text: modelData.comment
                                                        }
                                                        HoverHandler { id: commentHover }
                                                    }
                                                }
                                            }
                                        }

                                    }
                                }
                            }
                        }

                    }
                }

            }
        }
    }
}
