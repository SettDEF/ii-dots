import qs.modules.common
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

MaterialShape { // App icon
    id: root
    property var appIcon: ""
    property var summary: ""
    property var urgency: NotificationUrgency.Normal
    property bool isUrgent: urgency === NotificationUrgency.Critical
    property var image: ""
    property real materialIconScale: 0.57
    property real appIconScale: 0.8
    property real smallAppIconScale: 0.49
    property real materialIconSize: implicitSize * materialIconScale
    property real appIconSize: implicitSize * appIconScale
    property real smallAppIconSize: implicitSize * smallAppIconScale

    implicitSize: 38 * scale
    property list<var> urgentShapes: [
        MaterialShape.Shape.VerySunny,
        MaterialShape.Shape.SoftBurst,
    ]
    shape: isUrgent ? urgentShapes[Math.floor(Math.random() * urgentShapes.length)] : MaterialShape.Shape.Circle

    // Don't paint a coloured backdrop circle behind a real app icon: most app
    // icons (KDE Connect, Telegram, Wove, …) already carry their own circular
    // background, so ours sitting behind theirs reads as two overlapping
    // circles (the crescent you see). Keep the backdrop only for the
    // Material-symbol glyph fallback, which needs the contrast, and for the
    // image case (where the artwork covers it anyway).
    // Transparent whenever there is real artwork -- an app icon OR an image.
    //
    // The image case used to keep the backdrop on the grounds that "the artwork
    // covers it anyway". That was only true while the image was punched into a
    // circle by an OpacityMask; with the mask gone, artwork that is a rounded
    // square (most icon themes, Reversal included) leaves the coloured circle
    // showing around its corners. The backdrop exists for the Material-symbol
    // fallback, which is a bare glyph and genuinely needs the contrast.
    color: (root.appIcon !== "" || root.image !== "")
        ? "transparent"
        : (isUrgent ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer)
    Loader {
        id: materialSymbolLoader
        active: root.appIcon == ""
        anchors.fill: parent
        sourceComponent: MaterialSymbol {
            text: {
                const defaultIcon = NotificationUtils.findSuitableMaterialSymbol("")
                const guessedIcon = NotificationUtils.findSuitableMaterialSymbol(root.summary)
                return (root.urgency == NotificationUrgency.Critical && guessedIcon === defaultIcon) ?
                    "priority_high" : guessedIcon
            }
            anchors.fill: parent
            color: isUrgent ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
            iconSize: root.materialIconSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
    Loader {
        id: appIconLoader
        active: root.image == "" && root.appIcon != ""
        anchors.centerIn: parent
        sourceComponent: IconImage {
            id: appIconImage
            implicitSize: root.appIconSize
            asynchronous: true
            source: Quickshell.iconPath(root.appIcon, "image-missing")
        }
    }
    Loader {
        id: notifImageLoader
        active: root.image != ""
        anchors.fill: parent
        sourceComponent: Item {
            anchors.fill: parent
            Image {
                id: notifImage
                anchors.fill: parent
                readonly property int size: parent.width

                source: root.image
                fillMode: Image.PreserveAspectCrop
                cache: false
                antialiasing: true
                asynchronous: true

                width: size
                height: size
                sourceSize.width: size
                sourceSize.height: size

                // No mask. This used to be an OpacityMask with
                // radius: Appearance.rounding.full -- a FULL circle -- so every
                // notification image was punched into a circle and lost its
                // corners. Album art, screenshots and app artwork that is
                // already a rounded square all read as damaged. The image is
                // shown as authored; PreserveAspectCrop above still squares it.
            }
            Loader {
                id: notifImageAppIconLoader
                active: root.appIcon != ""
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                // Circular badge so the app icon reads as a corner badge over
                // the image — not a second icon overlapping it. The background
                // + border separate it cleanly from whatever's behind.
                sourceComponent: Rectangle {
                    implicitWidth: root.smallAppIconSize + 6
                    implicitHeight: root.smallAppIconSize + 6
                    radius: height / 2
                    color: Appearance.colors.colLayer0
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: root.smallAppIconSize
                        asynchronous: true
                        source: Quickshell.iconPath(root.appIcon, "image-missing")
                    }
                }
            }
        }
    }
}