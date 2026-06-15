import QtQuick
import qs.services

/**
 * Passive input-device probe. Drop into any always-visible surface (the
 * bar, the dock) to update `InputMode` whenever a pointer interacts with
 * that area.
 *
 * - HoverHandler is non-blocking by definition; it doesn't consume events.
 * - TapHandler uses DragThreshold + listens only on press, so it never
 *   actually fires a tap — clicks pass through to whatever is below.
 *
 * Performance: zero work while idle. One assignment per pointer event,
 * gated behind a string-equality check inside the singleton.
 */
Item {
    id: root
    anchors.fill: parent
    // Sit on top so we see events before sibling MouseAreas. The handlers
    // below are passive (HoverHandler is non-blocking, TapHandler uses
    // DragThreshold and never fires onTapped), so clicks still pass through.
    z: 999

    HoverHandler {
        acceptedDevices: PointerDevice.AllDevices
        onPointChanged: {
            if (point && point.device) InputMode.reportDevice(point.device)
        }
    }

    TapHandler {
        acceptedDevices: PointerDevice.AllDevices
        gesturePolicy: TapHandler.DragThreshold
        onPressedChanged: {
            if (pressed && point && point.device)
                InputMode.reportDevice(point.device)
        }
    }
}
