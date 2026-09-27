// Reusable list-row with the "accent bar slides in on hover" treatment.
// Used by the cheatsheet outline + FolderTree (and reusable elsewhere).
//
// On hover OR when `active` is true:
//   • Left vertical accent bar grows from 0 → 3 px
//   • Background fades to a soft secondaryContainer
//   • Text/icon shift right by ~4 px and shift to onSecondaryContainer
//
// Properties:
//   icon         — Material symbol name (optional)
//   trailingIcon — Material symbol name shown on the right (optional)
//   label        — main row text
//   active       — selected / current state (forces accent always-on)
//   depth        — indent level (0 = no indent, each step adds 12 px)
//   dimInactive  — fade label/icon at rest (good for hierarchical lists)
//   accentColor  — bar / hover-text color (default m3primary)
//
// Signal:
//   triggered() — fires on tap
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

Rectangle {
    id: root

    property string icon: ""
    property string trailingIcon: ""
    property string label: ""
    property bool active: false
    property int depth: 0
    property bool dimInactive: false
    property color accentColor: Appearance.m3colors.m3primary

    signal triggered()

    readonly property bool _highlight: active || hov.hovered

    implicitHeight: 30
    implicitWidth: 200
    radius: Appearance.rounding.small
    color: _highlight
        ? Qt.alpha(Appearance.colors.colSecondaryContainer, active ? 0.85 : 0.55)
        : ColorUtils.transparentize(Qt.alpha(Appearance.colors.colSecondaryContainer, active ? 0.85 : 0.55))
    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

    HoverHandler { id: hov }
    TapHandler { onTapped: root.triggered() }

    // ── Vertical accent bar — sits INSIDE the row with a small inset
    //     from the left edge, slides in on highlight.
    Rectangle {
        anchors {
            left: parent.left
            top: parent.top; bottom: parent.bottom
            leftMargin: 4
            topMargin: 6; bottomMargin: 6
        }
        width: root._highlight ? 3 : 0
        radius: 1.5
        color: root.accentColor
        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    // ── Content row ────────────────────────────────────────────────
    Item {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            // Always reserve room for the bar (4 inset + 3 bar + 5 gap = 12),
            // then add depth indentation and a subtle hover nudge.
            leftMargin: 12 + (root._highlight ? 4 : 0) + root.depth * 12
            rightMargin: 8
        }
        implicitHeight: rowItems.implicitHeight
        height: rowItems.implicitHeight
        Behavior on anchors.leftMargin { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Row {
            id: rowItems
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.icon.length > 0
                text: root.icon
                iconSize: Appearance.font.pixelSize.small
                color: root._highlight
                    ? Appearance.m3colors.m3onSecondaryContainer
                    : (root.dimInactive
                        ? Qt.alpha(Appearance.colors.colOnLayer1, 0.6)
                        : Appearance.colors.colSubtext)
                Behavior on color { ColorAnimation { duration: 160 } }
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: root.active ? Font.Medium : Font.Normal
                color: root._highlight
                    ? Appearance.m3colors.m3onSecondaryContainer
                    : (root.dimInactive
                        ? Qt.alpha(Appearance.colors.colOnLayer1, 0.7)
                        : Appearance.colors.colOnLayer1)
                Behavior on color { ColorAnimation { duration: 160 } }
            }
        }

        MaterialSymbol {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.trailingIcon.length > 0
            text: root.trailingIcon
            iconSize: Appearance.font.pixelSize.small
            color: root._highlight
                ? Appearance.m3colors.m3onSecondaryContainer
                : Appearance.colors.colSubtext
            Behavior on color { ColorAnimation { duration: 160 } }
        }
    }
}
