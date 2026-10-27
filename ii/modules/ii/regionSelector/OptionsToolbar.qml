pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

// The capture bar, in Windows' Snipping Tool order: Snip | Record, the mode box (rectangle, window,
// full screen, freeform: a dropdown), what a snip does (text extractor, search) or a recording's
// sound, the colour picker, the timer, and ⋯ for the settings. Each button has its own theme hue.
Toolbar {
    id: root

    // Use a synchronizer on these
    property var action
    property var selectionMode
    signal dismiss()
    /// Close now, capture again after this many seconds.
    signal delayed(int seconds)
    /// The whole screen, at once.
    signal fullScreen()
    /// a dropdown from an element at (x, y: its bottom, h: its height) in the window
    signal menu(var items, real x, real y, real h)

    readonly property bool recording: root.action === RegionSelection.SnipAction.Record || root.action === RegionSelection.SnipAction.RecordWithSound
    function setRecording(on) {
        if (on === root.recording) return;
        root.action = on ? (Persistent.states.snip.sound ? RegionSelection.SnipAction.RecordWithSound : RegionSelection.SnipAction.Record)
                         : RegionSelection.SnipAction.Copy;
    }
    /// a snip's own action, or plain copy again when it is on already
    function toggleAction(a) { root.action = root.action === a ? RegionSelection.SnipAction.Copy : a; }

    readonly property var delays: [3, 5, 10]
    readonly property var shapes: [
        { mode: RegionSelection.SelectionMode.RectCorners, icon: "crop_free", label: Translation.tr("Rectangle"), key: "R" },
        { mode: RegionSelection.SelectionMode.Window, icon: "select_window", label: Translation.tr("Window"), key: "W" },
        { mode: -1, icon: "fullscreen", label: Translation.tr("Full screen"), key: "F" },
        { mode: RegionSelection.SelectionMode.Circle, icon: "gesture", label: Translation.tr("Freeform"), key: "D" },
    ]
    readonly property var shape: root.shapes.find(s => s.mode === root.selectionMode) ?? root.shapes[0]
    function pickShape(s) {
        if (s.mode === -1) root.fullScreen();
        else root.selectionMode = s.mode;
    }
    /// R W F D from the keyboard (RegionSelection passes them)
    function shapeKey(k) {
        const s = root.shapes.find(x => x.key === k);
        if (s) root.pickShape(s);
        return !!s;
    }
    function openAt(item, items) {
        const p = item.mapToItem(null, 0, item.height);
        root.menu(items, p.x, p.y + 4, item.height + 8);
    }

    // Keyboard: ←/→ walk the mode box and the timer; Enter or Space opens / starts it.
    property int keyIndex: -1
    function moveKey(step) { root.keyIndex = root.keyIndex < 0 ? 0 : (root.keyIndex + 1) % 2; }
    function activateKey() {
        if (root.keyIndex === 0) modeBox.clicked();
        else if (root.keyIndex === 1) root.delayed(Persistent.states.snip.delay);
    }

    // Snip | Record
    RowLayout {
        Layout.fillHeight: true
        spacing: 2
        HueToolbarButton {
            hue: Appearance.colors.colHueBlue
            symbol: "photo_camera"
            toggled: !root.recording
            onClicked: root.setRecording(false)
            StyledToolTip { text: Translation.tr("Snip") }
        }
        HueToolbarButton {
            hue: Appearance.colors.colHueRed
            symbol: "videocam"
            toggled: root.recording
            onClicked: root.setRecording(true)
            StyledToolTip { text: Translation.tr("Record") }
        }
    }

    Rectangle { Layout.alignment: Qt.AlignVCenter; implicitWidth: 1; implicitHeight: 22; color: Appearance.colors.colOutlineVariant }

    // the mode box: this mode's icon and ▾; the list of modes above it
    ToolbarButton {
        id: modeBox
        toggled: root.keyIndex === 0
        implicitWidth: modeRow.implicitWidth + 22
        padding: 0
        colBackgroundToggled: ColorUtils.transparentize(Appearance.colors.colHueCyan, 0.72)
        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colHueCyan, 0.84)
        onClicked: root.openAt(modeBox, root.shapes.map(s => ({
            icon: s.icon, label: s.label, shortcut: s.key,
            iconColor: s === root.shape ? Appearance.colors.colHueCyan : undefined,
            onTriggered: () => root.pickShape(s)
        })))
        contentItem: Item {
            implicitWidth: modeRow.implicitWidth
            Row {
                id: modeRow
                anchors.centerIn: parent
                spacing: 2
                MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: root.shape.icon; iconSize: 20; color: Appearance.colors.colHueCyan }
                MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "arrow_drop_down"; iconSize: 18; color: Appearance.colors.colOnSurfaceVariant }
            }
        }
        StyledToolTip { text: Translation.tr("Mode: %1 (R W F D)").arg(root.shape.label) }
    }

    Rectangle { Layout.alignment: Qt.AlignVCenter; implicitWidth: 1; implicitHeight: 22; color: Appearance.colors.colOutlineVariant }

    // what a snip does (copy is the plain snip; right-drag edits) — or a recording's sound
    RowLayout {
        Layout.fillHeight: true
        spacing: 2
        HueToolbarButton {
            visible: !root.recording
            hue: Appearance.colors.colHueGreen
            symbol: "document_scanner"
            toggled: root.action === RegionSelection.SnipAction.CharRecognition
            onClicked: root.toggleAction(RegionSelection.SnipAction.CharRecognition)
            StyledToolTip { text: Translation.tr("Text extractor: copy the text in it") }
        }
        HueToolbarButton {
            visible: !root.recording
            hue: Appearance.colors.colHueYellow
            symbol: "image_search"
            toggled: root.action === RegionSelection.SnipAction.Search
            onClicked: root.toggleAction(RegionSelection.SnipAction.Search)
            StyledToolTip { text: Translation.tr("Search it (Lens)") }
        }
        HueToolbarButton {
            visible: root.recording
            hue: Appearance.colors.colHueYellow
            symbol: root.action === RegionSelection.SnipAction.RecordWithSound ? "volume_up" : "volume_off"
            toggled: root.action === RegionSelection.SnipAction.RecordWithSound
            onClicked: {
                const on = root.action !== RegionSelection.SnipAction.RecordWithSound;
                Persistent.states.snip.sound = on;
                root.action = on ? RegionSelection.SnipAction.RecordWithSound : RegionSelection.SnipAction.Record;
            }
            StyledToolTip { text: Translation.tr("System sound in the recording") }
        }
        HueToolbarButton {
            hue: Appearance.colors.colHueMagenta
            symbol: "colorize"
            onClicked: {
                root.dismiss();
                ColorPick.pick();
            }
            StyledToolTip { text: Translation.tr("Colour picker: every format, its shades, tinct's palette") }
        }
    }

    Rectangle { Layout.alignment: Qt.AlignVCenter; implicitWidth: 1; implicitHeight: 22; color: Appearance.colors.colOutlineVariant }

    // Delay: one timer button (close, count down, capture fresh — for menus and hover states).
    // Click starts it; right-click or the wheel picks 3 / 5 / 10 s, remembered.
    ToolbarButton {
        id: delayBtn
        readonly property int secs: Persistent.states.snip.delay
        function cycle(step) {
            const i = root.delays.indexOf(delayBtn.secs);
            Persistent.states.snip.delay = root.delays[((i < 0 ? 0 : i) + step + root.delays.length) % root.delays.length];
        }
        toggled: root.keyIndex === 1
        implicitWidth: delayRow.implicitWidth + 20
        padding: 0
        onClicked: root.delayed(delayBtn.secs)
        altAction: () => delayBtn.cycle(1)
        WheelHandler { onWheel: e => delayBtn.cycle(e.angleDelta.y > 0 ? 1 : -1) }
        contentItem: Item {
            implicitWidth: delayRow.implicitWidth
            Row {
                id: delayRow
                anchors.centerIn: parent
                spacing: 4
                MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "timer"; iconSize: 20; color: Appearance.colors.colOnSurfaceVariant }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: delayBtn.secs + "s"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }
        StyledToolTip { text: Translation.tr("Capture in %1 s (right-click or scroll: 3 / 5 / 10 s)").arg(delayBtn.secs) }
    }

    // ⋯: the settings for snips, switched in place
    HueToolbarButton {
        id: moreBtn
        hue: Appearance.colors.colPrimary
        symbol: "more_horiz"
        onClicked: {
            const on = v => v ? "check_box" : "check_box_outline_blank";
            const saving = Config.options.screenSnip.savePath.length > 0;
            const shots = Directories.home.replace("file://", "") + "/Pictures/Screenshots";
            root.openAt(moreBtn, [
                { icon: on(saving), label: Translation.tr("Save snips to Pictures/Screenshots"),
                  onTriggered: () => { Config.options.screenSnip.savePath = saving ? "" : shots; } },
                { icon: on(Config.options.screenSnip.includeCursor), label: Translation.tr("Include the mouse pointer"),
                  onTriggered: () => { Config.options.screenSnip.includeCursor = !Config.options.screenSnip.includeCursor; } },
                { icon: on(Config.options.regionSelector.targetRegions.windows), label: Translation.tr("Show windows to click"),
                  onTriggered: () => { Config.options.regionSelector.targetRegions.windows = !Config.options.regionSelector.targetRegions.windows; } },
                { icon: on(Config.options.regionSelector.rect.showAimLines), label: Translation.tr("Aim lines"),
                  onTriggered: () => { Config.options.regionSelector.rect.showAimLines = !Config.options.regionSelector.rect.showAimLines; } },
                { separator: true },
                { icon: "folder_open", label: Translation.tr("Open the screenshots folder"),
                  onTriggered: () => { root.dismiss(); Quickshell.execDetached(["xdg-open", saving ? Config.options.screenSnip.savePath : shots]); } },
                { icon: "settings", label: Translation.tr("All screenshot settings…"),
                  onTriggered: () => { root.dismiss(); SettingsApp.open(); } },
            ]);
        }
        StyledToolTip { text: Translation.tr("Settings") }
    }
}
