// A collapsible card: header row with icon, title, optional right-hand summary
// and a chevron; content revealed below.
//
// Used wherever a panel has settings that most people never touch — the point
// is that the common controls stay visible and uncluttered while the rest is
// one tap away, rather than a wall of sliders.
//
// Content is lazy: it is only constructed once the section has been opened, so
// a panel with several collapsed sections does not pay for any of them.
import qs.modules.common
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: sec

    property string icon: "tune"
    property string title: ""
    /// Shown right-aligned in the header — a value summary, so the section
    /// still tells you something while closed.
    property string summary: ""
    property bool expanded: false
    /// Set by the owner to keep one section's state across a reload.
    property alias contentComponent: contentLoader.sourceComponent

    Layout.fillWidth: true
    // NOT animated here, deliberately. Every container this sits in already
    // animates its own height — the settings panel does, and so does the
    // Bluetooth device card. Animating this one too means two Behaviors
    // chasing each other: each frame of the inner tween moves the outer
    // animation's target, the layout re-runs, and the layer-shell window
    // resizes ONCE PER FRAME, which the compositor has to honour. That is what
    // made the popup feel like it was dragging.
    //
    // Stepping the height instead lets the parent's existing Behavior see one
    // clean target change and interpolate it smoothly — the expansion still
    // animates, with a single tween and one resize instead of sixty.
    implicitHeight: col.implicitHeight + 20
    clip: true
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: sec.icon
                iconSize: 17
                color: sec.expanded ? Appearance.colors.colPrimary
                                    : Appearance.colors.colSubtext
                Behavior on color { ColorAnimation { duration: 140 } }
            }
            StyledText {
                Layout.fillWidth: true
                text: sec.title
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                visible: sec.summary.length > 0 && !sec.expanded
                text: sec.summary
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            MaterialSymbol {
                text: "expand_more"
                iconSize: 18
                color: Appearance.colors.colSubtext
                rotation: sec.expanded ? 180 : 0
                Behavior on rotation {
                    NumberAnimation { duration: Appearance.animDur(160); easing.type: Easing.OutCubic }
                }
            }
        }

        Loader {
            id: contentLoader
            Layout.fillWidth: true
            // Stays loaded once opened: rebuilding on every collapse would
            // reset scroll positions and drop any in-flight edit.
            active: sec.expanded || contentLoader.item !== null
            visible: sec.expanded
            opacity: sec.expanded ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Appearance.animDur(140) } }
        }
    }

    // Whole header is the hit target, not just the chevron.
    MouseArea {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 38
        cursorShape: Qt.PointingHandCursor
        onClicked: sec.expanded = !sec.expanded
    }
}
