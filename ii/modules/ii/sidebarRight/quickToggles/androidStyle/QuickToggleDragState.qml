pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root
    // Source of the drag — set when the user starts dragging a tile in edit mode.
    property bool active: false
    property int sourceTab: -1
    property int sourceIndex: -1
    property string sourceType: ""

    // Set by tab dots / drop targets while the drag pointer is over them.
    // -2 = no target, -1 = drop on currently-shown unused tray, >=0 = drop on tab N.
    property int dropTab: -2

    // When a container in edit mode is hovered during a drag, it sets
    // these. -2 = no container hovered; otherwise the (tabIndex, parentIndex)
    // identifies the container in cfg.tabs[tabIndex].toggles[parentIndex].
    property int dropContainerTab: -2
    property int dropContainerIndex: -2

    function begin(tab, index, type) {
        sourceTab = tab
        sourceIndex = index
        sourceType = type
        dropTab = -2
        dropContainerTab = -2
        dropContainerIndex = -2
        active = true
    }
    function end() {
        active = false
        sourceTab = -1
        sourceIndex = -1
        sourceType = ""
        dropTab = -2
        dropContainerTab = -2
        dropContainerIndex = -2
    }
}
