// Per-tab lazy loader. The active tab loads immediately and synchronously;
// inactive tabs hydrate after `prewarmDelay` so a switch is instant. Once
// hydrated, a tab stays loaded for the lifetime of its parent.
//
// Designed to drop into SwipeView, StackLayout, or anywhere you need
// per-page lazy mounting:
//
//   SwipeView {
//       TabLoader {
//           active: SwipeView.isCurrentItem    // or: parent.currentIndex === N
//           sourceComponent: HeavyPage {}      // inline OR explicit Component
//       }
//   }
import QtQuick

Item {
    id: root

    property bool active: false
    property int prewarmDelay: 250
    property bool prewarmEnabled: true
    property Component sourceComponent: null

    readonly property Item item: loader.item
    readonly property int status: loader.status

    // Mirror the loaded item's intrinsic size so SwipeView / Layout can
    // size us correctly even before hydration.
    implicitWidth:  loader.item ? loader.item.implicitWidth  : 0
    implicitHeight: loader.item ? loader.item.implicitHeight : 0

    property bool _hydrated: false

    onActiveChanged: if (active) _hydrated = true

    Component.onCompleted: {
        if (active) {
            _hydrated = true
        } else if (prewarmEnabled) {
            prewarmTimer.restart()
        }
    }

    Timer {
        id: prewarmTimer
        interval: root.prewarmDelay
        repeat: false
        onTriggered: if (!root._hydrated) root._hydrated = true
    }

    Loader {
        id: loader
        anchors.fill: parent
        active: root._hydrated
        asynchronous: !root.active   // active tab loads synchronously
        sourceComponent: root.sourceComponent
        visible: status === Loader.Ready
    }
}
