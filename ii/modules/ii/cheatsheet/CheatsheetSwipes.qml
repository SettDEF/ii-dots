// Touch / swipe gestures cheatsheet — documents what's available in
// tablet mode. Grouped by area. Uses the shared AccentRow widget for
// the hover treatment.
import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    implicitWidth: 720
    implicitHeight: 540

    // Gesture catalog — { icon, gesture, action, group }.
    readonly property var gestures: [
        // ── Edge swipes ───────────────────────────────────────────
        { group: "Edge swipes",     icon: "swipe_right",     gesture: "1 finger from LEFT edge → drag inward",   action: "Open Sidebar Left (drag past 140 px to commit)" },
        { group: "Edge swipes",     icon: "swipe_left",      gesture: "1 finger from RIGHT edge → drag inward",  action: "Open Sidebar Right (Quick Toggles)" },
        { group: "Edge swipes",     icon: "swipe_down",      gesture: "1 finger from TOP edge → drag inward",    action: "Open HUD" },
        { group: "Edge swipes",     icon: "swipe_up",        gesture: "1 finger from BOTTOM edge → drag inward", action: "Reveal the Dock" },
        { group: "Edge swipes",     icon: "swipe",           gesture: "2 fingers on any edge (tablet mode)",     action: "Same as drag — fires the panel instantly" },

        // ── Multi-finger gestures ─────────────────────────────────
        { group: "Multi-finger",    icon: "touch_app",       gesture: "3-finger TAP anywhere",                   action: "Open overview search (tablet mode)" },
        { group: "Multi-finger",    icon: "swipe_vertical",  gesture: "4-finger SWIPE UP",                       action: "Open Overview (tablet mode)" },
        { group: "Multi-finger",    icon: "press",           gesture: "Long-press in TOP-RIGHT corner",          action: "Power menu (Session)" },

        // ── Inside the right sidebar ─────────────────────────────
        { group: "Sidebar",         icon: "swap_horiz",      gesture: "1 finger horizontal swipe in Quick Toggles", action: "Switch tab (left / right)" },

        // ── Touchpad widget ──────────────────────────────────────
        { group: "Virtual touchpad", icon: "touchpad_mouse", gesture: "Drag inside the touchpad surface",        action: "Move the cursor (relative)" },
        { group: "Virtual touchpad", icon: "ads_click",      gesture: "Tap on touchpad surface",                 action: "Left click" },
        { group: "Virtual touchpad", icon: "schedule",       gesture: "Long-press (450 ms) on touchpad surface", action: "Right click" }
    ]

    // Group → list-of-rows derived map (no spread — QML JS doesn't support it).
    readonly property var groups: {
        const m = {}
        const order = []
        for (const g of gestures) {
            if (!m[g.group]) { m[g.group] = []; order.push(g.group) }
            m[g.group].push(g)
        }
        m._order = order
        return m
    }

    ScrollView {
        anchors.fill: parent
        anchors.margins: 8
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        clip: true

        ColumnLayout {
            width: parent.width
            spacing: 14

            // ── Intro / hint ────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: introCol.implicitHeight + 20
                radius: Appearance.rounding.small
                color: Qt.alpha(Appearance.colors.colSecondaryContainer, 0.4)

                ColumnLayout {
                    id: introCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4
                    StyledText {
                        text: qsTr("Touch gestures")
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Medium
                        color: Appearance.m3colors.m3onSecondaryContainer
                    }
                    StyledText {
                        text: qsTr("Most gestures only fire while tablet mode is on (toggle via the quick-toggle widget or `qs -c ii ipc call tablet on`).")
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }

            // ── Each group ──────────────────────────────────────────
            Repeater {
                model: root.groups._order
                delegate: ColumnLayout {
                    required property var modelData     // group name
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        text: modelData
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.m3colors.m3primary
                        Layout.leftMargin: 4
                    }

                    Repeater {
                        model: root.groups[parent.modelData]
                        delegate: AccentRow {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 44   // taller to fit the 2-line text
                            icon: modelData.icon
                            label: modelData.gesture + "    →    " + modelData.action
                        }
                    }
                }
            }
        }
    }
}
