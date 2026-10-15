import QtQuick
import QtTest

/// Test driver (loaded only with CAST_TEST): real synthetic mouse events
/// through Qt's event pipeline, so drags exercise the same MouseAreas a
/// user's pointer would.
TestCase {
    id: tc
    name: "castEditorDriver"
    when: false

    /// Press at (x, y) in `item`, move by (dx, dy) in steps, release.
    function drag(item, x, y, dx, dy) {
        mousePress(item, x, y, Qt.LeftButton);
        for (let i = 1; i <= 12; ++i)
            mouseMove(item, x + dx * i / 12, y + dy * i / 12, 5, Qt.LeftButton);
        mouseRelease(item, x + dx, y + dy, Qt.LeftButton);
    }
    function click(item, x, y, button) {
        mouseClick(item, x, y, button || Qt.LeftButton);
    }
    /// Middle-button drag by (dx, dy), in steps; returns nothing.
    function mdrag(item, x, y, dx, dy, steps) {
        steps = steps || 12;
        mousePress(item, x, y, Qt.MiddleButton);
        for (let i = 1; i <= steps; ++i)
            mouseMove(item, x + dx * i / steps, y + dy * i / steps, 5, Qt.MiddleButton);
        mouseRelease(item, x + dx, y + dy, Qt.MiddleButton);
    }
    /// Press, move, report, keep holding (for checks mid-drag).
    function mpress(item, x, y) { mousePress(item, x, y, Qt.MiddleButton); }
    function mmove(item, x, y) { mouseMove(item, x, y, 5, Qt.MiddleButton); }
    function mrelease(item, x, y) { mouseRelease(item, x, y, Qt.MiddleButton); }
    function hover(item, x, y) {
        mouseMove(item, x, y);
    }
}
