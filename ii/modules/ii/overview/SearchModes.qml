pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// The launcher's modes: over the search field, its text giving way to them, as the capture bar's
// toggles (pairs of hue buttons). Ctrl+1…0 / Ctrl+Tab pick a mode, Alt+1…4 run the selected result's
// own actions, plus a mode's extras; the keys show faintly at the field's end (hintText).
Item {
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
        root.picking = false;
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

    /// the field is the pairs of modes now (a click on the search icon, scrolling on it, Ctrl+Space)
    property bool picking: false
    /// the mode the arrows are on while picking
    property int sel: 0
    onPickingChanged: if (picking) root.sel = Math.max(0, root.modes.indexOf(root.active))
    /// the keys, faint at the field's right end (SearchBar draws them)
    readonly property string hintText: root.hints.map(h => "<b><font color='%1'>%2</font></b> %3".arg(root.hue).arg(h.key).arg(StringUtils.escapeHtml(h.label))).join("  ·  ")
    readonly property real stripWidth: strip.implicitWidth + 16
    /// where the search icon is, from this item's left, and its size: the pill grows out of it
    property real origin: 0
    property real originSize: height

    /// The arrows, Enter and Esc while picking; any other key closes the pairs and types on.
    function pickerKey(event) {
        if (!root.picking) return false;
        const n = root.modes.length;
        switch (event.key) {
        case Qt.Key_Left: root.sel = (root.sel + n - 1) % n; return true;
        case Qt.Key_Right: case Qt.Key_Tab: root.sel = (root.sel + 1) % n; return true;
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: root.pick(root.modes[root.sel]); return true;
        case Qt.Key_Escape: root.picking = false; return true;
        default: root.picking = false; return false;
        }
    }

    // the icon's shape grows out across the field, with a bounce, and the pairs stand on it
    Rectangle {
        id: pill
        z: -1
        readonly property real full: root.width - root.origin
        x: root.origin
        anchors.verticalCenter: parent.verticalCenter
        width: root.picking ? full : root.originSize
        height: root.picking ? root.height : root.originSize
        radius: height / 2
        color: ColorUtils.transparentize(root.hue, 0.8)
        opacity: root.picking ? 1 : 0
        Behavior on width { NumberAnimation { duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
        Behavior on height { NumberAnimation { duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
        Behavior on opacity { NumberAnimation { duration: root.picking ? 90 : 260; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 160 } }
    }

    // the pairs, where the text was: they come in as the text goes
    RowLayout {
        id: strip
        anchors.centerIn: parent
        spacing: 6
        opacity: root.picking ? 1 : 0
        scale: root.picking ? 1 : 0.94
        visible: opacity > 0
        // a moment after the pill, so they ride in on it
        Behavior on opacity { SequentialAnimation { PauseAnimation { duration: root.picking ? 110 : 0 } NumberAnimation { duration: 200; easing.type: Easing.OutCubic } } }
        Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
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
                    implicitHeight: 20
                    color: Appearance.colors.colOutlineVariant
                }
                Repeater {
                    model: group.modelData
                    delegate: HueToolbarButton {
                        id: btn
                        required property var modelData
                        readonly property int n: root.modes.indexOf(btn.modelData)
                        implicitHeight: 32
                        implicitWidth: 34
                        hue: btn.modelData.hue
                        symbol: btn.modelData.icon
                        toggled: root.active === btn.modelData
                        onClicked: root.pick(btn.modelData)
                        StyledToolTip { text: "%1   %2   Ctrl+%3".arg(btn.modelData.label).arg(root.p[btn.modelData.id].trim()).arg((btn.n + 1) % 10) }
                        // where the arrows are
                        Rectangle {
                            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 1 }
                            width: 14
                            height: 2
                            radius: 1
                            color: btn.modelData.hue
                            visible: root.picking && root.sel === btn.n
                        }
                    }
                }
            }
        }
    }

    Shortcut { sequences: ["Ctrl+Space"]; enabled: GlobalStates.overviewOpen; onActivated: root.picking = !root.picking }
    Item {
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
