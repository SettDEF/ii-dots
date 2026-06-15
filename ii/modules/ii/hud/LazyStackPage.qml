import QtQuick

/**
 * A StackLayout page that builds its content only after it's first shown,
 * then keeps it (instant on return). Heavy tabs that are never opened are
 * never instantiated.
 *
 * Usage — wrap the page body in a Component child:
 *   LazyStackPage {
 *       Component { Item { ...page body... } }
 *   }
 *
 * The trigger is the StackLayout setting `visible` on the current child —
 * no page-index plumbing needed.
 */
Item {
    id: page
    default property Component content

    // Latches true the first time the StackLayout shows this page.
    property bool seen: false
    onVisibleChanged: if (visible) page.seen = true
    Component.onCompleted: if (visible) page.seen = true

    implicitHeight: contentLoader.item ? contentLoader.item.implicitHeight : 0

    Loader {
        id: contentLoader
        anchors { left: parent.left; right: parent.right; top: parent.top }
        active: page.seen
        sourceComponent: page.content
    }
}
