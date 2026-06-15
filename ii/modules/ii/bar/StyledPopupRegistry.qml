pragma Singleton
import QtQuick

// Tracks which bar StyledPopup is currently the "hovered" one. When a new
// popup claims focus, the previous one (if any) drops its grace window
// so two tooltips never overlap on screen during cursor transitions.
QtObject {
    id: root
    property var current: null
    function claim(who) {
        if (current !== who) current = who
    }
}
