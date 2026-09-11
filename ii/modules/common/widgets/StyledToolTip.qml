import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ToolTip {
    id: root
    property bool extraVisibleCondition: true
    property bool alternativeVisibleCondition: false

    // Hover source, in priority order:
    //   1. the parent's own `hovered` property — buttons, switches, anything
    //      derived from Control already has one;
    //   2. a HoverHandler we attach to the parent ourselves, for plain Items
    //      and Rectangles that have no such property.
    //
    // The old condition was `parent.hovered === undefined || parent?.hovered`,
    // i.e. it treated an UNKNOWN hover state as "show". Any tooltip on a plain
    // Rectangle was therefore permanently on screen — several were, and the
    // fix kept being applied caller-by-caller instead of here. Unknown hover
    // now means hidden, and the attached handler means such parents still get
    // a working tooltip rather than none at all.
    // The probe is a declared Component, NOT Qt.createQmlObject. createQmlObject
    // compiles a QML *string* at runtime, and this runs for every tooltip whose
    // parent has no `hovered` — 109 instances repo-wide, including the search
    // result delegate, which is rebuilt on every keystroke. That turned each
    // keypress in the overview into a burst of QML compiles. A Component is
    // compiled once when this file loads; createObject() then just instantiates.
    property var hoverProbe: null
    Component {
        id: hoverProbeComponent
        HoverHandler {}
    }

    // A finger never hovers, so on a touch screen every one of these — 130 of
    // them, most on icon-only buttons whose ONLY label this is — could never
    // appear at all. A long press shows it instead.
    //
    // Same Component-not-createQmlObject rule as above, and passive in the
    // same way: DragThreshold means it never takes an exclusive grab, so the
    // button underneath still receives its own press.
    property var touchProbe: null
    Component {
        id: touchProbeComponent
        TapHandler {
            acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Stylus
            gesturePolicy: TapHandler.DragThreshold
            longPressThreshold: 0.5
        }
    }
    readonly property bool touchHeld: touchProbe ? touchProbe.pressed : false

    Component.onCompleted: {
        if (parent && parent.hovered === undefined)
            hoverProbe = hoverProbeComponent.createObject(parent);
        if (parent)
            touchProbe = touchProbeComponent.createObject(parent);
    }
    // Objects parented to the tooltip's PARENT outlive the tooltip, so without
    // this every rebuilt delegate leaves a handler behind on a surviving item.
    Component.onDestruction: {
        if (hoverProbe) {
            hoverProbe.destroy();
            hoverProbe = null;
        }
        if (touchProbe) {
            touchProbe.destroy();
            touchProbe = null;
        }
    }

    readonly property bool parentHovered: hoverProbe ? hoverProbe.hovered
        : (parent && parent.hovered !== undefined ? parent.hovered === true : false)

    readonly property bool internalVisibleCondition:
        (extraVisibleCondition && (parentHovered || root.touchHeld))
        || alternativeVisibleCondition
    verticalPadding: 5
    horizontalPadding: 10
    background: null
    font {
        family: Appearance.font.family.main
        variableAxes: Appearance.font.variableAxes.main
        pixelSize: Appearance?.font.pixelSize.smaller ?? 14
        hintingPreference: Font.PreferNoHinting // Prevent shaky text
    }

    delay: 0
    visible: internalVisibleCondition
    
    contentItem: StyledToolTipContent {
        id: contentItem
        font: root.font
        text: root.text
        shown: root.internalVisibleCondition
        horizontalPadding: root.horizontalPadding
        verticalPadding: root.verticalPadding
    }
}

