import QtQuick
import QtQuick.Layouts

/**
 * RowLayout that auto-aligns all immediate child Items to the same
 * height — specifically, the implicit height of the tallest child.
 * Keeps rows of mixed-content cards flush along their bottom edge
 * without having to set `Layout.fillHeight: true` on every cell.
 *
 * Children should still set `Layout.fillWidth` or `Layout.preferredWidth`
 * for horizontal sizing as usual.
 *
 * Mechanism: RowLayout's intrinsic implicitHeight is already the max of
 * its children's implicit heights. Setting `Layout.fillHeight: true`
 * on each child stretches it to that row height → visually equal.
 */
RowLayout {
    id: root

    onChildrenChanged: Qt.callLater(_equalize)
    Component.onCompleted: _equalize()

    function _equalize() {
        for (let i = 0; i < children.length; i++) {
            const c = children[i]
            if (c && c.Layout) c.Layout.fillHeight = true
        }
    }
}
