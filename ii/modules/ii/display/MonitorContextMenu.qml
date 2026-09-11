// Right-click menu for one monitor in the arrangement view.
//
// A PopupWindow rather than an in-panel overlay: DisplaySettings masks its
// layer surface to `mainCard` (see its `mask: Region`), and anything drawn
// outside that region renders but never receives clicks. Its own surface has
// no mask. Same reasoning as LauncherEntryMenu.
//
// Turning a display OFF goes through MonitorSafety, never MonitorManager
// directly — that is what puts the countdown and the last-monitor refusal in
// the path. Turning one ON is unguarded on purpose: adding output cannot
// strand you.
pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

PopupWindow {
    id: root

    required property Item anchorItem
    property string monName: ""
    color: "transparent"

    signal requestOpen(string name)

    readonly property var mon: (MonitorManager.friendly ?? []).find(m => m.name === root.monName) ?? null
    readonly property bool isOff: root.mon?.disabled ?? false
    readonly property bool mirroring: (root.mon?.mirrorOf ?? "").length > 0
    readonly property int overrides: DisplayProfiles.overrideCount(root.monName)
    readonly property var others: (MonitorManager.friendly ?? []).filter(m => m.name !== root.monName)
    // "" when allowed; otherwise the sentence explaining the refusal.
    readonly property string offBlocked: root.isOff ? "" : MonitorSafety.blockReason(root.monName)

    // Anchored where the pointer was, so the menu opens at the corner of the
    // box you actually clicked rather than at the arrangement's origin.
    property real _x: 0
    property real _y: 0

    function openAt(name, x, y) {
        if (!name || name.length === 0) return;
        root.monName = name;
        root._x = x;
        root._y = y;
        root.visible = true;
    }
    function close() { root.visible = false }

    anchor {
        window: root.anchorItem ? root.anchorItem.QsWindow.window : null
        gravity: Edges.Bottom | Edges.Right
        edges: Edges.Bottom | Edges.Right
        adjustment: PopupAdjustment.Flip | PopupAdjustment.SlideX
        // Guarded: mapFromItem() throws if evaluated before the anchor belongs
        // to a window.
        rect: (root.visible && root.anchorItem && root.anchorItem.QsWindow?.window)
            ? Qt.rect(root.anchorItem.QsWindow.mapFromItem(root.anchorItem, root._x, root._y).x,
                      root.anchorItem.QsWindow.mapFromItem(root.anchorItem, root._x, root._y).y,
                      1, 1)
            : Qt.rect(0, 0, 1, 1)
    }

    implicitWidth: panel.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: panel.implicitHeight + Appearance.sizes.elevationMargin * 2

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: root.close()
        onWheel: wheel => wheel.accepted = true
    }

    StyledRectangularShadow { target: panel }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        implicitWidth: 250
        implicitHeight: col.implicitHeight + 12
        radius: Appearance.rounding.small
        // m3surfaceContainer, not colLayer1: colLayer1 is solveOverlayColor()'d
        // against the shell backdrop and reads see-through in its own window.
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        focus: root.visible
        Keys.onEscapePressed: event => { root.close(); event.accepted = true }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            spacing: 1

            // `icon` and `label` are FINAL on Button — hence the row* names.
            component MenuRow: RippleButton {
                Layout.fillWidth: true
                implicitHeight: 31
                buttonRadius: Appearance.rounding.verysmall
                property string rowIcon: ""
                property string rowLabel: ""
                property bool danger: false
                contentItem: RowLayout {
                    spacing: 8
                    MaterialSymbol {
                        Layout.leftMargin: 4
                        text: rowIcon
                        iconSize: Appearance.font.pixelSize.large
                        color: !enabled ? Appearance.colors.colSubtext
                             : danger ? Appearance.m3colors.m3error
                                      : Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: rowLabel
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: !enabled ? Appearance.colors.colSubtext
                             : danger ? Appearance.m3colors.m3error
                                      : Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                }
            }

            // ── Header ──────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 4
                Layout.bottomMargin: 2
                spacing: 7
                MaterialSymbol {
                    text: root.isOff ? "desktop_access_disabled" : "monitor"
                    iconSize: 16
                    color: root.isOff ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: root.monName
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.bold: true
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        visible: text.length > 0
                        text: root.mon
                            ? (root.isOff
                                ? Translation.tr("Turned off")
                                : root.mon.width + "×" + root.mon.height + " @ "
                                  + Math.round(root.mon.refreshRate) + " Hz")
                            : ""
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.bottomMargin: 3
                implicitHeight: 1
                color: Appearance.colors.colLayer0Border
            }

            MenuRow {
                rowIcon: "tune"
                rowLabel: Translation.tr("Display settings…")
                onClicked: { root.requestOpen(root.monName); root.close() }
            }

            // ── Power ───────────────────────────────────────────────────
            MenuRow {
                visible: root.isOff
                rowIcon: "power_settings_new"
                rowLabel: Translation.tr("Turn this display on")
                onClicked: { MonitorSafety.enable(root.monName); root.close() }
            }
            MenuRow {
                visible: !root.isOff
                rowIcon: "desktop_access_disabled"
                rowLabel: Translation.tr("Turn this display off…")
                danger: true
                // Greyed rather than hidden: a control that silently vanishes
                // reads as a bug. The reason sits directly underneath.
                enabled: root.offBlocked.length === 0
                onClicked: {
                    if (MonitorSafety.requestDisable(root.monName)) root.close();
                }
            }
            StyledText {
                visible: root.offBlocked.length > 0
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 6
                Layout.bottomMargin: 3
                text: root.offBlocked
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }

            // ── Mirroring ───────────────────────────────────────────────
            MenuRow {
                visible: !root.isOff && root.mirroring
                rowIcon: "flip_to_front"
                rowLabel: Translation.tr("Stop mirroring")
                onClicked: { MonitorManager.setMirror(root.monName, ""); root.close() }
            }
            MenuRow {
                visible: !root.isOff && !root.mirroring && root.others.length > 0
                rowIcon: "screen_share"
                rowLabel: root.others.length > 0
                    ? Translation.tr("Mirror onto %1").arg(root.others[0].name) : ""
                onClicked: {
                    if (root.others.length > 0)
                        MonitorManager.setMirror(root.monName, root.others[0].name);
                    root.close();
                }
            }

            Rectangle {
                visible: root.others.length > 0 || root.overrides > 0
                Layout.fillWidth: true
                Layout.topMargin: 3
                Layout.bottomMargin: 3
                implicitHeight: 1
                color: Appearance.colors.colLayer0Border
            }

            // ── Saved settings ──────────────────────────────────────────
            MenuRow {
                visible: root.others.length > 0
                rowIcon: "content_copy"
                rowLabel: Translation.tr("Copy settings to other displays")
                onClicked: {
                    for (const o of root.others) {
                        DisplayProfiles.copyTo(root.monName, o.name);
                        DisplayProfiles.apply(o.name);
                    }
                    root.close();
                }
            }
            MenuRow {
                rowIcon: "restart_alt"
                rowLabel: root.overrides > 0
                    ? Translation.tr("Forget %1 saved override(s)").arg(root.overrides)
                    : Translation.tr("No saved overrides")
                enabled: root.overrides > 0
                danger: root.overrides > 0
                // Forgets what was saved. It cannot put the display back to how
                // it looked — Hyprland has no undo — so this is Forget, not Revert.
                onClicked: { DisplayProfiles.clear(root.monName); root.close() }
            }
        }
    }
}
