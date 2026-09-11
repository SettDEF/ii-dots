import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.utils
import qs.modules.common.widgets
import QtQml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Button {
    id: root
    property var imageData
    property var rowHeight
    property bool manualDownload: false
    property string previewDownloadPath
    property string downloadPath
    property string nsfwPath
    property string fileName: decodeURIComponent((imageData.file_url).substring((imageData.file_url).lastIndexOf('/') + 1))
    property string filePath: `${root.previewDownloadPath}/${root.fileName}`
    property int maxTagStringLineLength: 50
    property real imageRadius: Appearance.rounding.small

    // ── Progressive quality ─────────────────────────────────────────────
    // preview_url is a thumbnail — 150-300px on most boorus. Stretched to a
    // row this tall it is visibly mush, and nothing ever asked for anything
    // sharper. sample_url is already populated for every provider by
    // Booru.qml, so the crisp copy was one binding away.
    //
    // The thumbnail still loads first, because it is small and arrives almost
    // immediately; the sample decodes in the background and fades in over it.
    // Nothing pops, and a slow sample never leaves an empty box.
    property Item viewport: null

    // Providers on the manualDownload list are fetched to disk precisely
    // because they refuse hotlinking. Asking them for a sample over the
    // network just produces a failed request per image.
    readonly property string hqUrl: root.imageData.sample_url ?? ""
    readonly property bool hqEligible: !root.manualDownload
        && root.hqUrl.length > 0
        && root.hqUrl !== root.imageData.preview_url

    // Half a screen of margin either side, so scrolling reveals sharp images
    // rather than a row of thumbnails that sharpen after they land.
    readonly property real hqPreloadMargin: root.viewport ? root.viewport.height * 0.5 : 0
    readonly property bool inView: {
        if (!root.viewport) return false;
        // Reading contentY is what makes this re-evaluate while scrolling:
        // mapToItem is a function call, not a dependency, so the binding would
        // otherwise be computed once and go stale the moment the list moved.
        const scrollTick = root.viewport.contentY;
        const pos = root.mapToItem(root.viewport, 0, 0);
        if (!pos) return false;
        return (pos.y + root.height) > -root.hqPreloadMargin
            && pos.y < (root.viewport.height + root.hqPreloadMargin);
    }

    // Coming into view arms a short settle rather than firing at once, so
    // flinging through a page does not queue a full-size fetch for every row
    // that swept past. Hovering skips the wait entirely — see hqActive.
    property bool hqSettled: false
    Timer {
        id: hqSettleTimer
        interval: 140
        onTriggered: root.hqSettled = true
    }
    onInViewChanged: {
        if (root.inView && root.hqEligible) hqSettleTimer.restart();
        else if (!root.inView) hqSettleTimer.stop();
    }
    // onInViewChanged does not fire for a delegate that is already on screen
    // when it is built, which is most of the first page.
    Component.onCompleted: if (root.inView && root.hqEligible) hqSettleTimer.restart()

    // Once loaded it stays loaded. Dropping the source on scroll-away would
    // re-fetch it the moment it came back.
    readonly property bool hqActive: root.hqEligible && (root.hqSettled || root.hovered)

    // The menu was built inline in the ⋮ button's onClicked, which meant it was
    // the ONLY way to reach it — right-clicking the image, the obvious gesture,
    // did nothing. Lifted onto root so the button and the right-click open the
    // same list rather than two that drift apart.
    function contextMenuItems() {
        return [
            { icon: "open_in_new", label: Translation.tr("Open file link"),
              onTriggered: () => root.openWithoutWarp(root.imageData.file_url) },
            ...(root.imageData.source && root.imageData.source.length > 0 ? [{
                icon: "link",
                label: Translation.tr("Go to source (%1)").arg(StringUtils.getDomain(root.imageData.source)),
                onTriggered: () => root.openWithoutWarp(root.imageData.source)
            }] : []),
            { icon: "download", label: Translation.tr("Download"), onTriggered: () => {
                const targetDir = root.imageData.is_nsfw ? root.nsfwPath : root.downloadPath;
                const target = `${targetDir}/${root.fileName}`;
                // The old command reported the SFW path in its notification even
                // when the file had gone to the NSFW folder, because it built the
                // message from downloadPath rather than the directory it used.
                Quickshell.execDetached(["bash", "-c",
                    FileUtils.fetchToFileCommand(root.imageData.file_url, target)
                    + ` && notify-send ${FileUtils.shQuote(Translation.tr("Download complete"))} `
                    + `${FileUtils.shQuote(target)} -a 'Shell'`
                ])
            }}
        ];
    }

    // Opening a link warps the cursor to the new window; no_warps suppresses
    // that for the duration. Both menu entries need it, so it lives here once.
    function openWithoutWarp(url) {
        if (!url || url.length === 0) return;
        HyprDispatch.run("keyword cursor:no_warps true");
        Qt.openUrlExternally(url);
        HyprDispatch.run("keyword cursor:no_warps false");
    }

    function openContextMenu(anchorItem, x, y) {
        const host = ObjectUtils.findAncestorWith(root, "showContextMenu");
        if (!host) return;
        host.showContextMenu(anchorItem, x, y, root.contextMenuItems());
    }

    // Right-click anywhere on the image. gesturePolicy keeps it from taking an
    // exclusive grab, so the Button underneath still gets its own press.
    TapHandler {
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: (eventPoint) => root.openContextMenu(root, eventPoint.position.x, eventPoint.position.y)
    }

    ImageDownloaderProcess {
        id: imageDownloader
        running: root.manualDownload
        filePath: root.filePath
        sourceUrl: root.imageData.preview_url ?? root.imageData.sample_url
        onDone: (path, width, height) => {
            imageObject.source = ""
            imageObject.source = path
            if (!modelData.width || !modelData.height) {
                modelData.width = width
                modelData.height = height
                modelData.aspect_ratio = width / height
            }
        }
    }

    StyledToolTip {
        text: `${StringUtils.wordWrap(root.imageData.tags, root.maxTagStringLineLength)}`
    }

    padding: 0
    implicitWidth: root.rowHeight * modelData.aspect_ratio
    implicitHeight: root.rowHeight

    background: Rectangle {
        implicitWidth: root.rowHeight * modelData.aspect_ratio
        implicitHeight: root.rowHeight
        radius: imageRadius
        color: Appearance.colors.colLayer2
    }

    contentItem: Item {
        anchors.fill: parent

        StyledImage {
            id: imageObject
            anchors.fill: parent
            width: root.rowHeight * modelData.aspect_ratio
            height: root.rowHeight
            fillMode: Image.PreserveAspectFit
            source: modelData.preview_url
            sourceSize.width: root.rowHeight * modelData.aspect_ratio
            sourceSize.height: root.rowHeight

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: root.rowHeight * modelData.aspect_ratio
                    height: root.rowHeight
                    radius: imageRadius
                }
            }
        }

        // The sharp copy, drawn on top. StyledImage already holds opacity at 0
        // until status is Ready and fades in, so the swap needs no extra state
        // — and retainWhileLoading keeps this from blinking on re-decode.
        StyledImage {
            id: hqImageObject
            anchors.fill: parent
            width: root.rowHeight * modelData.aspect_ratio
            height: root.rowHeight
            fillMode: Image.PreserveAspectFit
            source: root.hqActive ? root.hqUrl : ""
            // Decode near the size actually drawn instead of at full
            // resolution: a booru original can be 4000px on a side, and
            // decoding a screenful of those is how you eat a gigabyte.
            // Height alone keeps the aspect ratio.
            sourceSize.height: Math.min(Math.ceil(root.rowHeight * 2), 2048)

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: root.rowHeight * modelData.aspect_ratio
                    height: root.rowHeight
                    radius: imageRadius
                }
            }
        }

        RippleButton {
            id: menuButton
            anchors.top: parent.top
            anchors.right: parent.right
            property real buttonSize: 30
            anchors.margins: Math.max(root.imageRadius - buttonSize / 2, 8)
            implicitHeight: buttonSize
            implicitWidth: buttonSize

            buttonRadius: Appearance.rounding.full
            colBackground: ColorUtils.transparentize(Appearance.m3colors.m3surface, 0.3)
            colBackgroundHover: ColorUtils.transparentize(ColorUtils.mix(Appearance.m3colors.m3surface, Appearance.m3colors.m3onSurface, 0.8), 0.2)
            colRipple: ColorUtils.transparentize(ColorUtils.mix(Appearance.m3colors.m3surface, Appearance.m3colors.m3onSurface, 0.6), 0.1)

            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.m3colors.m3onSurface
                text: "more_vert"
            }

            onClicked: root.openContextMenu(menuButton, 0, menuButton.height)
        }
    }
}