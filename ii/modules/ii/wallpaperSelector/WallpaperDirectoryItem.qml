import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Io

MouseArea {
    id: root
    required property var fileModelData
    property bool isDirectory: fileModelData.fileIsDir
    // Animated → cheap ffmpeg poster.
    property bool isVideo: !isDirectory
        && /\.(mp4|webm|mkv|avi|mov|m4v|gif)$/i.test(fileModelData.fileName ?? "")
    property bool useThumbnail: !isVideo && Images.isValidImageByName(fileModelData.fileName)

    property alias colBackground: background.color
    property alias colText: wallpaperItemName.color
    property alias radius: background.radius
    property alias margins: background.anchors.margins
    property alias padding: wallpaperItemColumnLayout.anchors.margins
    margins: Appearance.sizes.wallpaperSelectorItemMargins
    padding: Appearance.sizes.wallpaperSelectorItemPadding

    signal activated()
    // Right-click → request the context menu (coords are item-local).
    signal contextRequested(real mx, real my)
    // Ctrl+click → toggle multi-selection.
    signal selectToggled()
    property bool selected: false

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton)
            root.contextRequested(mouse.x, mouse.y)
        else if (mouse.modifiers & Qt.ControlModifier)
            root.selectToggled()
        else
            root.activated()
    }

    Rectangle {
        id: background
        anchors.fill: parent
        radius: Appearance.rounding.normal
        border.width: root.selected ? 3 : 0
        border.color: Appearance.m3colors.m3primary
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // Multi-select checkmark badge.
        Rectangle {
            z: 5
            visible: root.selected
            anchors { top: parent.top; right: parent.right; margins: 7 }
            width: 22; height: 22; radius: 11
            color: Appearance.m3colors.m3primary
            border.width: 2; border.color: Appearance.colors.colLayer0
            MaterialSymbol {
                anchors.centerIn: parent
                text: "check"; iconSize: 14
                color: Appearance.colors.colOnPrimary
            }
        }

        ColumnLayout {
            id: wallpaperItemColumnLayout
            anchors.fill: parent
            spacing: 4

            Item {
                id: wallpaperItemImageContainer
                Layout.fillHeight: true
                Layout.fillWidth: true

                Loader {
                    id: thumbnailShadowLoader
                    active: thumbnailImageLoader.active && thumbnailImageLoader.item.status === Image.Ready
                    anchors.fill: thumbnailImageLoader
                    sourceComponent: StyledRectangularShadow {
                        target: thumbnailImageLoader
                        anchors.fill: undefined
                        radius: Appearance.rounding.small
                    }
                }

                Loader {
                    id: thumbnailImageLoader
                    anchors.fill: parent
                    active: root.useThumbnail
                    sourceComponent: ThumbnailImage {
                        id: thumbnailImage
                        // Self-heal for static images only; animated formats
                        // are handled by videoThumbLoader below.
                        generateThumbnail: {
                            const p = (fileModelData.filePath || "").toLowerCase()
                            return !p.match(/\.(gif|mp4|webm|m4v|mkv|mov|avi)(\?|$)/)
                        }
                        sourcePath: fileModelData.filePath

                        cache: false
                        fillMode: Image.PreserveAspectCrop
                        clip: true
                        sourceSize.width: wallpaperItemColumnLayout.width
                        sourceSize.height: wallpaperItemColumnLayout.height - wallpaperItemColumnLayout.spacing - wallpaperItemName.height

                        Connections {
                            target: Wallpapers
                            function onThumbnailGenerated(directory) {
                                if (thumbnailImage.status !== Image.Error) return;
                                if (FileUtils.parentDirectory(thumbnailImage.sourcePath) !== FileUtils.trimFileProtocol(directory)) return;
                                thumbnailImage.source = "";
                                thumbnailImage.source = thumbnailImage.thumbnailPath;
                            }
                            function onThumbnailGeneratedFile(filePath) {
                                if (thumbnailImage.status !== Image.Error) return;
                                if (Qt.resolvedUrl(thumbnailImage.sourcePath) !== Qt.resolvedUrl(filePath)) return;
                                thumbnailImage.source = "";
                                thumbnailImage.source = thumbnailImage.thumbnailPath;
                            }
                        }

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: wallpaperItemImageContainer.width
                                height: wallpaperItemImageContainer.height
                                radius: Appearance.rounding.small
                            }
                        }
                    }
                }

                Loader {
                    id: iconLoader
                    active: !root.useThumbnail && !root.isVideo
                    anchors.fill: parent
                    sourceComponent: DirectoryIcon {
                        fileModelData: root.fileModelData
                        sourceSize.width: wallpaperItemColumnLayout.width
                        sourceSize.height: wallpaperItemColumnLayout.height - wallpaperItemColumnLayout.spacing - wallpaperItemName.height
                    }
                }

                // ── Video wallpaper tile ─────────────────────────────────
                // ffmpeg pulls a frame ~0.5s in, cached by path hash so the
                // grid only extracts each video once. A ▶ badge marks it.
                Loader {
                    id: videoThumbLoader
                    active: root.isVideo
                    anchors.fill: parent
                    sourceComponent: Item {
                        id: vThumb
                        readonly property string videoSrc: FileUtils.trimFileProtocol(root.fileModelData.filePath)
                        readonly property string thumbDir: FileUtils.trimFileProtocol(Directories.home)
                            + "/.cache/quickshell/wallpaperSelector/videoThumbs"
                        readonly property string thumbPath: thumbDir + "/" + Qt.md5(videoSrc) + ".jpg"

                        Process {
                            id: vThumbProc
                            running: true
                            command: ["bash", "-c",
                                `mkdir -p '${vThumb.thumbDir}' && `
                                + `{ [ -s '${vThumb.thumbPath}' ] || `
                                + `ffmpeg -y -ss 0.5 -i '${vThumb.videoSrc.replace(/'/g, "'\\''")}' `
                                + `-frames:v 1 -vf scale=640:-1 '${vThumb.thumbPath}' >/dev/null 2>&1; }`]
                            onExited: vThumbImage.source = "file://" + vThumb.thumbPath
                        }

                        Image {
                            id: vThumbImage
                            anchors.fill: parent
                            cache: false
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            clip: true
                            sourceSize.width: wallpaperItemColumnLayout.width
                            sourceSize.height: wallpaperItemColumnLayout.height
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: wallpaperItemImageContainer.width
                                    height: wallpaperItemImageContainer.height
                                    radius: Appearance.rounding.small
                                }
                            }
                        }
                        // Placeholder while the frame is being extracted
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: vThumbImage.status !== Image.Ready
                            text: "movie"
                            iconSize: 42
                            color: root.colText
                            opacity: 0.5
                        }
                        // ▶ badge
                        Rectangle {
                            anchors.centerIn: parent
                            width: 34; height: 34; radius: 17
                            visible: vThumbImage.status === Image.Ready
                            color: ColorUtils.transparentize("#000000", 0.35)
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "play_arrow"
                                iconSize: 22
                                fill: 1
                                color: "#ffffff"
                            }
                        }
                    }
                }
            }

            StyledText {
                id: wallpaperItemName
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10

                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                text: fileModelData.fileName
            }
        }
    }
}
