// Horizontal pill tab bar with a sliding indicator behind the active
// tab. Compact (icon-only) when inactive, expanded (icon + label) when
// active. Drop-in replacement for inline pill rows.
//
// Usage:
//   PillTabBar {
//       tabs: [
//           { id: "files",  icon: "folder_open", label: "Files"  },
//           { id: "media",  icon: "music_note",  label: "Media"  }
//       ]
//       current: "files"
//       onTabSelected: id => GlobalStates.shelfTab = id
//   }
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

Item {
    id: root

    required property var tabs              // [{ id, icon, label }]
    required property string current
    signal tabSelected(string id)

    // ── Multi-select mode ──────────────────────────────────────────────
    // When true, multiple tabs can be marked active at once. The sliding
    // indicator hides; each active tab gets its own static pill background.
    // `current` is ignored in this mode in favour of `activeIds`. Tap still
    // emits `tabSelected(id)` — the consumer decides whether to add the id,
    // remove it, or toggle.
    property bool multiSelect: false
    property var activeIds: []   // list<string>

    function isActive(id) {
        if (multiSelect) {
            for (let i = 0; i < activeIds.length; ++i)
                if (activeIds[i] === id) return true
            return false
        }
        return current === id
    }

    // When true the tab row is pinned to the left edge instead of
    // centered. With a fixed-width host this keeps the first tab from
    // drifting as the active pill expands/collapses.
    property bool leftAligned: false

    // When true no tab ever expands to show its label — every tab is a
    // fixed icon circle, the active one marked by the indicator pill.
    // The row width is then constant, so nothing shifts on a switch.
    // The label (kept in the tab data) surfaces as a hover tooltip.
    property bool iconOnly: false

    // When true EVERY tab is rendered in expanded pill form (icon + label),
    // not just the active one. Useful for multi-select strips where each
    // tab is a checkbox and you want their widths to stay consistent.
    property bool forceExpanded: false

    // Visual config — defaults match the bar style.
    property color activeBackground: Appearance.colors.colSecondaryContainer
    property color activeForeground: Appearance.m3colors.m3onSecondaryContainer
    property color inactiveForeground: Appearance.colors.colOnLayer0
    property color hoverBackground: Appearance.colors.colLayer1Hover
    property int animDuration: 280

    readonly property int activeIdx: {
        for (let i = 0; i < tabs.length; i++)
            if (tabs[i].id === current) return i
        return 0
    }

    implicitHeight: 32
    implicitWidth: tabsRow.implicitWidth + 6

    // ── Sliding indicator pill (single-select mode only) ──────────
    Rectangle {
        id: slidingIndicator
        z: 0
        visible: !root.multiSelect
        readonly property Item activeBtn: tabsRow.children[root.activeIdx] ?? null
        readonly property real inset: 3
        x: activeBtn ? tabsRow.x + activeBtn.x + inset : 0
        y: tabsRow.y + inset
        width:  activeBtn ? activeBtn.width  - inset * 2 : 0
        height: parent.height - inset * 2
        radius: height / 2
        color: root.activeBackground
        Behavior on x     { NumberAnimation { duration: root.animDuration; easing.type: Easing.InOutCubic } }
        Behavior on width { NumberAnimation { duration: root.animDuration; easing.type: Easing.InOutCubic } }
        Behavior on color { ColorAnimation  { duration: 200 } }
    }

    Row {
        id: tabsRow
        z: 1
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: root.leftAligned ? undefined : parent.horizontalCenter
        anchors.left: root.leftAligned ? parent.left : undefined
        anchors.leftMargin: 3
        // Small breathing room between tiles instead of flush stacking.
        // Adjusted for tighter spacing.
        spacing: 6

        Repeater {
            model: root.tabs
            delegate: Item {
                required property var modelData
                required property int index
                readonly property bool active: root.isActive(modelData.id)
                // Only the active tab WITH a non-empty label expands into
                // a pill. An active-but-textless tab stays a centered icon
                // circle — otherwise the asymmetric pill padding shoves the
                // lone icon off the highlight's center.
                readonly property bool expanded:
                    !root.iconOnly
                    && (active || root.forceExpanded)
                    && modelData.label !== undefined
                    && String(modelData.label).length > 0

                implicitHeight: root.height
                // Symmetric — the indicator pill is now correctly aligned,
                // so equal padding gives an evenly-spaced icon+label.
                readonly property int leftPad: 8
                readonly property int rightPad: 8

                // Width includes symmetric external padding
                implicitWidth: expanded
                    ? btnRow.implicitWidth + leftPad + rightPad
                    : root.height
                Behavior on implicitWidth {
                    NumberAnimation { duration: root.animDuration; easing.type: Easing.InOutCubic }
                }

                HoverHandler { id: pillHov }
                TapHandler { onTapped: root.tabSelected(modelData.id) }

                // Icon-only mode loses the inline label — surface it as
                // a hover tooltip so the tabs stay identifiable.
                Loader {
                    anchors.fill: parent
                    active: root.iconOnly && String(modelData.label ?? "").length > 0
                    sourceComponent: StyledToolTip {
                        extraVisibleCondition: pillHov.hovered
                        text: modelData.label
                    }
                }

                // Multi-select needs its own per-tab static background since
                // the sliding indicator is hidden in that mode.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: height / 2
                    visible: root.multiSelect && parent.active
                    color: root.activeBackground
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                // Hover highlight — fills the whole delegate area.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: height / 2
                    color: pillHov.hovered && !parent.active ? root.hoverBackground : ColorUtils.transparentize(root.hoverBackground)
                    Behavior on color { ColorAnimation { duration: 160 } }
                }

                Row {
                    id: btnRow
                    // Always centered. The delegate's implicitWidth already
                    // reserves leftPad+rightPad of slack around this row, so
                    // centering looks identical to left/right anchoring —
                    // WITHOUT the runtime anchor-switching (left/right ⇄
                    // horizontalCenter) that, on the tab which starts
                    // expanded then collapses, could leave its icon
                    // mispositioned or zero-sized.
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.icon
                        // Smaller only when sharing the pill with a label;
                        // an icon-only tab (active or not) uses the normal
                        // size so all the circles match.
                        iconSize: parent.parent.expanded
                            ? Appearance.font.pixelSize.small
                            : Appearance.font.pixelSize.normal
                        fill: parent.parent.active ? 1 : 0
                        color: parent.parent.active ? root.activeForeground : root.inactiveForeground
                        Behavior on color { ColorAnimation { duration: 220 } }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: parent.parent.expanded
                        text: modelData.label ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: parent.parent.active ? root.activeForeground : root.inactiveForeground
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }
            }
        }
    }
}
