pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * Manages a HyprlandFocusGrab that's to be shared by all windows.
 * "Persistent" is for windows that should always be included but not closed on dismiss, like bar and onscreen keyboard.
 * "Dismissable" is for stuff like sidebars
 */ 
Singleton {
    id: root

    signal dismissed()

    property list<var> persistent: []
    property list<var> dismissable: []

    function dismiss() {
        root.dismissable = [];
        root.dismissed();
    }

    Component.onCompleted: {
        console.log("[GlobalFocusGrab] Initialized");
    }

    // Release the Hyprland focus grab cleanly when Quickshell tears down
    // (every config reload). Without this, an active grab is left dangling
    // — Hyprland keeps a grab on now-destroyed windows, so keyboard and
    // click input go nowhere and you can't type until focus is forced back.
    Component.onDestruction: {
        root.dismissable = [];
        root.persistent = [];
        grab.active = false;
    }

    function addPersistent(window) {
        if (root.persistent.indexOf(window) === -1) {
            const list = [...root.persistent];
            list.push(window);
            root.persistent = list;
        }
    }

    function removePersistent(window) {
        var index = root.persistent.indexOf(window);
        if (index !== -1) {
            const list = [...root.persistent];
            list.splice(index, 1);
            root.persistent = list;
        }
    }

    function addDismissable(window) {
        if (root.dismissable.indexOf(window) === -1) {
            const list = [...root.dismissable];
            list.push(window);
            root.dismissable = list;
        }
    }

    function removeDismissable(window) {
        var index = root.dismissable.indexOf(window);
        if (index !== -1) {
            const list = [...root.dismissable];
            list.splice(index, 1);
            root.dismissable = list;
        }
    }

    HyprlandFocusGrab {
        id: grab
        windows: [...root.persistent, ...root.dismissable]
        active: root.dismissable.length > 0
        onCleared: () => {
            root.dismiss();
        }
    }

}
