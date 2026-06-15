import QtQuick

/**
 * Bottom-edge dark gradient + caption text. Used by wallpaper / theme
 * thumbnails to overlay a filename without obscuring the image. Anchor it
 * to the bottom of the parent (left/right/bottom) and supply `text`.
 *
 * Properties:
 *   - text:        caption text
 *   - barHeight:   gradient strip height (default 30)
 *   - radius:      bottom-corner rounding (matches host card)
 *   - elide:       text elide mode (default ElideLeft for filenames)
 */
Rectangle {
    id: root

    property string text: ""
    property real   barHeight: 30
    property int    elide: Text.ElideLeft

    height: barHeight
    color: "transparent"
    gradient: Gradient {
        GradientStop { position: 0; color: "transparent" }
        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.55) }
    }

    Text {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 8
            rightMargin: 8
            bottomMargin: 4
        }
        text: root.text
        color: "white"
        opacity: 0.85
        elide: root.elide
        font.pixelSize: 11
    }
}
