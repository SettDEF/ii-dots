// One level of a context menu, which instantiates ITSELF for its child level —
// so menus nest to any depth. The recursion terminates because the child lives
// behind a Loader that is only activated when a row carrying `submenu` is
// hovered; without that guard a self-referencing component would recurse
// forever at creation.
//
// Positioning: the root level sits at the cursor (originW === 0); every deeper
// level flanks its parent, flipping to the parent's left when there is no room
// on the right, and clamps vertically. `bounds` is the full-screen Item, so
// bounds.width / bounds.height are the usable monitor dimensions.
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: mp

    required property var items
    required property Item bounds
    property real originX: 0
    property real originW: 0
    property real desiredY: 0
    property int panelWidth: 226
    property bool shown: true
    // function() — tears down the whole menu stack after an item fires.
    property var dismissAll: null

    // Child level state.
    property var childItems: []
    property real childY: 0
    property bool childOpen: false

    width: panelWidth
    implicitHeight: mpCol.implicitHeight + 10
    height: implicitHeight
    x: originW === 0
        ? Math.max(6, Math.min(originX, bounds.width - width - 6))
        : ((originX + originW + 4 + width <= bounds.width - 6)
            ? originX + originW + 4
            : Math.max(6, originX - width - 4))
    y: Math.max(6, Math.min(desiredY, bounds.height - height - 6))
    radius: Appearance.rounding.small
    // OPAQUE on purpose. colLayer1 is not a plain colour: it comes from
    // solveOverlayColor(), which returns rgba(..., 1 - contentTransparency) —
    // a deliberately translucent film that only resolves to the intended
    // shade once it is composited over colLayer0 inside a panel. A context
    // menu floats over whatever happens to be beneath it, so that alpha shows
    // straight through, and over a photo the menu became unreadable.
    //
    // colLayer1Base (m3surfaceContainerLow) is the opaque colour that
    // solveOverlayColor is solving FOR, so this is the same shade the theme
    // intends — just without the film. It retints with the wallpaper like
    // every other role.
    color: Appearance.colors.colLayer1Base
    border.width: 1
    // colLayer0Border is mixed from colLayer0, which carries the background
    // alpha, so it inherited the same problem along the panel's edge.
    border.color: ColorUtils.mix(Appearance.m3colors.m3outlineVariant,
                                 Appearance.colors.colLayer1Base, 0.4)

    // A Behavior does not run on a property's INITIAL binding, so a panel born
    // with shown === true was simply at full opacity on frame one and the fade
    // never ran. Opening a beat later is what makes it an animation.
    property bool entered: false
    Component.onCompleted: mp.entered = true

    readonly property bool visualOpen: mp.shown && mp.entered
    opacity: visualOpen ? 1 : 0
    scale: visualOpen ? 1 : 0.93

    // Grow from the corner nearest the cursor. A fixed top-left origin makes
    // a menu that flipped to fit expand away from the click that summoned it.
    transformOrigin: {
        const flippedLeft = mp.originW !== 0 && mp.x < mp.originX;
        const flippedUp = mp.y < mp.desiredY - 1;
        if (flippedLeft) return flippedUp ? Item.BottomRight : Item.TopRight;
        return flippedUp ? Item.BottomLeft : Item.TopLeft;
    }

    Behavior on opacity { NumberAnimation { duration: 110 } }
    Behavior on scale  { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

    // A child is parented to `bounds`, so nothing else takes it down with us.
    onShownChanged: if (!shown) mp._closeChild()

    ColumnLayout {
        id: mpCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 5 }
        spacing: 1

        Repeater {
            model: mp.items
            delegate: Rectangle {
                id: row
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: modelData.separator ? 7 : 32
                radius: 6
                color: (rowMa.containsMouse && !modelData.separator && modelData.slider !== true)
                    ? (modelData.danger
                       ? ColorUtils.transparentize(Appearance.m3colors.m3error, 0.84)
                       : Appearance.colors.colLayer2)
                    : "transparent"

                Rectangle {
                    visible: row.modelData.separator === true
                    anchors.verticalCenter: parent.verticalCenter
                    anchors { left: parent.left; right: parent.right; leftMargin: 8; rightMargin: 8 }
                    height: 1
                    color: Appearance.colors.colLayer0Border
                }

                // A range, rather than a list of presets. Lives inside the
                // menu so the value keeps applying while you drag — which
                // also means whatever the menu holds open stays open.
                RowLayout {
                    visible: row.modelData.slider === true
                    anchors { fill: parent; leftMargin: 9; rightMargin: 11 }
                    spacing: 9
                    MaterialSymbol {
                        text: row.modelData.icon ?? ""
                        iconSize: 17
                        color: row.modelData.iconColor ?? Appearance.colors.colOnLayer1
                    }
                    StyledSlider {
                        id: rowSlider
                        Layout.fillWidth: true
                        value: row.modelData.value ?? 0
                        onValueChanged: {
                            const fn = row.modelData.onMoved;
                            if (fn && pressed) fn(value);
                        }
                    }
                    StyledText {
                        Layout.preferredWidth: 34
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(rowSlider.value * 100) + "%"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colSubtext
                    }
                }

                RowLayout {
                    visible: !row.modelData.separator && row.modelData.slider !== true
                    anchors { fill: parent; leftMargin: 9; rightMargin: 11 }
                    spacing: 9
                    MaterialSymbol {
                        text: row.modelData.icon ?? ""
                        iconSize: 17
                        color: row.modelData.iconColor
                            ?? (row.modelData.danger ? Appearance.m3colors.m3error
                                                     : Appearance.colors.colOnLayer1)
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.label ?? ""
                        font.pixelSize: Appearance.font.pixelSize.small
                        elide: Text.ElideRight
                        color: row.modelData.danger
                            ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                    }
                    MaterialSymbol {
                        visible: !!row.modelData.submenu
                        text: "chevron_right"
                        iconSize: 17
                        color: Appearance.colors.colOnLayer1
                    }
                }

                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    enabled: !row.modelData.separator && row.modelData.slider !== true
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Hovering a parent row opens its child; hovering any other
                    // row closes it, so one branch is open at a time.
                    onEntered: {
                        if (row.modelData.submenu)
                            mp._openChild(row.modelData.submenu, row.mapToItem(mp.bounds, 0, 0).y)
                        else
                            mp._closeChild()
                    }
                    onClicked: {
                        if (row.modelData.submenu) {
                            mp._openChild(row.modelData.submenu, row.mapToItem(mp.bounds, 0, 0).y)
                            return
                        }
                        // Act, THEN dismiss. Dismissing first tears down
                        // whatever the menu was holding open on the handler's
                        // behalf — the dock's per-app volume died exactly
                        // here: closing unbound the PwObjectTracker, and a
                        // write to an untracked PipeWire node is silently
                        // discarded, so every preset did nothing at all.
                        const fn = row.modelData.onTriggered
                        if (fn) fn()
                        if (mp.dismissAll) mp.dismissAll()
                    }
                }
            }
        }
    }

    // The recursion. Loaded by URL rather than as a component literal: QML
    // resolves component literals statically and rejects a type that contains
    // itself ("instantiated recursively"), even behind an inactive Loader.
    // setSource() defers resolution to runtime, and childOpen bounds the depth
    // to however far the user has actually hovered.
    //
    // Parented to `bounds` so a deep child is never clipped by an ancestor's
    // rectangle.
    Loader {
        id: childLoader
        parent: mp.bounds
        z: mp.z + 1
    }

    function _openChild(items, yInRoot) {
        mp.childItems = items
        mp.childY = yInRoot
        mp.childOpen = true
        childLoader.setSource("PopupMenuPanel.qml", {
            items: items,
            bounds: mp.bounds,
            originX: mp.x,
            originW: mp.width,
            desiredY: yInRoot - 5,
            panelWidth: mp.panelWidth,
            dismissAll: mp.dismissAll
        })
    }
    function _closeChild() {
        mp.childOpen = false
        childLoader.source = ""
    }
}
