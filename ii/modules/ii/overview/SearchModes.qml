pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// The launcher's modes as the capture bar's toggles (pairs of hue buttons) and each mode's keys:
// Ctrl+1…0 / Ctrl+Tab pick a mode, Alt+1…4 run the selected result's own actions, plus a mode's extras.
ColumnLayout {
    id: root
    required property var bar
    /// the selected result (its verb and actions are this mode's keys)
    property var entry: null
    readonly property var input: root.bar.searchInput
    readonly property var p: Config.options.search.prefix
    readonly property var groups: [
        [
            { id: "app", icon: "apps", label: Translation.tr("Apps"), hue: Appearance.colors.colHueBlue },
            { id: "action", icon: "settings_suggest", label: Translation.tr("Commands"), hue: Appearance.colors.colHueMagenta },
        ],
        [
            { id: "clipboard", icon: "content_paste_search", label: Translation.tr("Clipboard"), hue: Appearance.colors.colHueGreen },
            { id: "emojis", icon: "add_reaction", label: Translation.tr("Emoji"), hue: Appearance.colors.colHueYellow },
        ],
        [
            { id: "math", icon: "calculate", label: Translation.tr("Math"), hue: Appearance.colors.colHueCyan },
            { id: "shellCommand", icon: "terminal", label: Translation.tr("Shell command"), hue: Appearance.colors.colHueRed },
        ],
        [
            { id: "webSearch", icon: "travel_explore", label: Translation.tr("Web search"), hue: Appearance.colors.colPrimary },
            { id: "translate", icon: "translate", label: Translation.tr("Translate"), hue: Appearance.colors.colTertiary },
        ],
        [
            { id: "theme", icon: "palette", label: Translation.tr("Themes"), hue: Appearance.colors.colSecondary },
            { id: "notifications", icon: "notifications", label: Translation.tr("Notifications"), hue: ColorUtils.mix(Appearance.colors.colHueRed, Appearance.colors.colHueYellow) },
        ],
    ]
    readonly property var modes: {
        const out = [];
        for (let i = 0; i < root.groups.length; i++)
            for (let j = 0; j < root.groups[i].length; j++)
                out.push(root.groups[i][j]);
        return out;
    }
    // the mode the text is in: the longest prefix it starts with ("tr " before a one-letter one)
    readonly property var active: {
        const t = root.input.text;
        let best = null;
        for (let i = 0; i < root.modes.length; i++) {
            const m = root.modes[i];
            const pre = root.p[m.id];
            if (pre && t.startsWith(pre) && (!best || pre.length > root.p[best.id].length)) best = m;
        }
        return best;
    }
    readonly property color hue: root.active ? root.active.hue : Appearance.colors.colPrimary

    function pick(m) {
        const t = root.input.text;
        const body = root.active ? t.slice(root.p[root.active.id].length) : t;
        root.input.text = !m || root.active === m ? body : root.p[m.id] + body;
        root.input.forceActiveFocus();
        root.input.cursorPosition = root.input.text.length;
    }
    function step(by) {
        const i = root.active ? root.modes.indexOf(root.active) : -1;
        // -1 is plain search, between the last mode and the first
        const n = root.modes.length + 1;
        const next = ((i + 1 + by) % n + n) % n - 1;
        root.pick(next < 0 ? null : root.modes[next]);
    }

    // a mode's own keys beyond the result's actions
    readonly property var extras: {
        if (!root.active) return [];
        switch (root.active.id) {
        case "clipboard": return [{
            key: "Alt+S", label: Translation.tr("sort: %1").arg(root.bar.sortModes.find(s => s.id === root.bar.sortMode)?.label ?? ""),
            run: () => {
                const ids = root.bar.sortModes.map(s => s.id);
                root.bar.sortMode = ids[(ids.indexOf(root.bar.sortMode) + 1) % ids.length];
            }
        }];
        case "webSearch": return [{
            key: "Alt+L", label: Translation.tr("Lens"),
            run: () => {
                GlobalStates.overviewOpen = false;
                Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "search"]);
            }
        }];
        default: return [];
        }
    }
    readonly property var actions: (root.entry?.actions ?? []).slice(0, 4)
    // what the hint line says: Enter, the actions, the extras
    readonly property var hints: {
        const out = [];
        if (root.entry?.verb) out.push({ key: "Enter", label: root.entry.verb });
        root.actions.forEach((a, i) => out.push({ key: "Alt+" + (i + 1), label: a.name }));
        return out.concat(root.extras);
    }

    spacing: 2

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: 6
        Repeater {
            model: root.groups
            delegate: RowLayout {
                id: group
                required property var modelData
                required property int index
                spacing: 2
                Rectangle {
                    visible: group.index > 0
                    Layout.alignment: Qt.AlignVCenter
                    Layout.rightMargin: 4
                    implicitWidth: 1
                    implicitHeight: 22
                    color: Appearance.colors.colOutlineVariant
                }
                Repeater {
                    model: group.modelData
                    delegate: HueToolbarButton {
                        id: btn
                        required property var modelData
                        readonly property int n: root.modes.indexOf(btn.modelData) + 1
                        implicitHeight: 36
                        implicitWidth: 38
                        hue: btn.modelData.hue
                        symbol: btn.modelData.icon
                        toggled: root.active === btn.modelData
                        onClicked: root.pick(btn.modelData)
                        StyledToolTip { text: "%1   %2   Ctrl+%3".arg(btn.modelData.label).arg(root.p[btn.modelData.id].trim()).arg(btn.n % 10) }
                    }
                }
            }
        }
    }

    // this mode's keys, in its hue
    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 14
        Layout.rightMargin: 14
        Layout.preferredWidth: 0
        visible: root.hints.length > 0
        elide: Text.ElideRight
        // one line: StyledText wraps, and at no width of its own it was measured as a tall block
        wrapMode: Text.NoWrap
        maximumLineCount: 1
        textFormat: Text.StyledText
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        text: root.hints.map(h => "<b><font color='%1'>%2</font></b> %3".arg(root.hue).arg(h.key).arg(StringUtils.escapeHtml(h.label))).join("   ")
    }

    // the keys (the launcher's window only), in one item of no height: the column spaces every item
    Item {
        Layout.preferredHeight: 0
        Layout.topMargin: -root.spacing
        Shortcut { sequences: ["Ctrl+Tab"]; enabled: GlobalStates.overviewOpen; onActivated: root.step(1) }
        Shortcut { sequences: ["Ctrl+Shift+Tab", "Ctrl+Backtab"]; enabled: GlobalStates.overviewOpen; onActivated: root.step(-1) }
        Repeater {
            model: 10
            delegate: Item {
                id: k
                required property int index
                Shortcut { sequence: "Ctrl+" + ((k.index + 1) % 10); enabled: GlobalStates.overviewOpen; onActivated: root.pick(root.modes[k.index]) }
            }
        }
        Repeater {
            model: 4
            delegate: Item {
                id: a
                required property int index
                Shortcut { sequence: "Alt+" + (a.index + 1); enabled: GlobalStates.overviewOpen && a.index < root.actions.length; onActivated: root.actions[a.index].execute() }
            }
        }
        Shortcut { sequence: "Alt+S"; enabled: GlobalStates.overviewOpen && root.active?.id === "clipboard"; onActivated: root.extras[0].run() }
        Shortcut { sequence: "Alt+L"; enabled: GlobalStates.overviewOpen && root.active?.id === "webSearch"; onActivated: root.extras[0].run() }
    }
}
