import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Thumbnail image. It currently generates to the right place at the right size, but does not handle metadata/maintenance on modification.
 * See Freedesktop's spec: https://specifications.freedesktop.org/thumbnail-spec/thumbnail-spec-latest.html
 */
StyledImage {
    id: root

    property bool generateThumbnail: true
    required property string sourcePath
    property string thumbnailSizeName: Images.thumbnailSizeNameForDimensions(sourceSize.width, sourceSize.height)
    property string thumbnailPath: {
        if (sourcePath.length == 0) return;
        const resolvedUrlWithoutFileProtocol = FileUtils.trimFileProtocol(`${Qt.resolvedUrl(sourcePath)}`);
        const encodedUrlWithoutFileProtocol = resolvedUrlWithoutFileProtocol.split("/").map(part => encodeURIComponent(part)).join("/");
        const md5Hash = Qt.md5(`file://${encodedUrlWithoutFileProtocol}`);
        return `${Directories.genericCache}/thumbnails/${thumbnailSizeName}/${md5Hash}.png`;
    }
    source: thumbnailPath

    asynchronous: true
    smooth: true
    mipmap: false

    opacity: status === Image.Ready ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    onSourceSizeChanged: {
        if (!root.generateThumbnail) return;
        // Don't kill an in-flight run: sourceSizeChanged can fire repeatedly
        // while a slow (video) generation is still working, and restarting it
        // every time means it never finishes → endless respawn, pegged CPU.
        if (thumbnailGeneration.running) return;
        thumbnailGeneration.running = true;
    }
    // Guard: same lifecycle race as CliphistImage — Repeater item is gone,
    // but the magick process can still emit `finished` and crash V4 GC.
    property bool _gone: false
    Component.onDestruction: {
        root._gone = true;
        thumbnailGeneration.running = false;
    }

    Process {
        id: thumbnailGeneration
        command: {
            const maxSize = Images.thumbnailSizes[root.thumbnailSizeName];
            const src     = root.sourcePath;
            const dst     = FileUtils.trimFileProtocol(root.thumbnailPath);
            // Prefer vipsthumbnail: same speed as magick, ~30 MB peak, no
            // thread fanout. Fall back to magick (capped) only if vips
            // isn't installed or fails. Exit 1 on regen so the Image reloads.
            // vipsthumbnail/magick can't decode video — without an ffmpeg
            // step the thumbnail never lands, and this Process re-runs every
            // time the tile re-lays out, pegging a core. Order: vips → magick
            // (images) → ffmpeg (video/anything else). If ALL fail, drop a
            // `.thumbfail` marker so we never retry that file (else infinite
            // respawn). `[ -s ]` guards against half-written 0-byte outputs.
            return ["bash", "-c",
                `dst='${dst}'; src='${src}'; max=${maxSize}; \\
                 [ -f "$dst" ] && exit 0; \\
                 [ -f "$dst.thumbfail" ] && exit 0; \\
                 case "\${src,,}" in \\
                   *.mp4|*.webm|*.mkv|*.mov|*.avi|*.m4v) \\
                     if command -v ffmpeg >/dev/null && \\
                        ffmpeg -nostdin -y -loglevel quiet -ss 1 -i "$src" \\
                          -frames:v 1 -vf "scale=\${max}:-2" "$dst" 2>/dev/null && [ -s "$dst" ]; then exit 1; fi; \\
                     : > "$dst.thumbfail" 2>/dev/null; exit 0 ;; \\
                 esac; \\
                 if command -v vipsthumbnail >/dev/null && \\
                    vipsthumbnail "$src" -s \${max}x\${max} -o "$dst" 2>/dev/null && [ -s "$dst" ]; then exit 1; fi; \\
                 export MAGICK_THREAD_LIMIT=1 MAGICK_MEMORY_LIMIT=256MiB MAGICK_MAP_LIMIT=512MiB OMP_NUM_THREADS=1; \\
                 if magick "$src" -resize \${max}x\${max} "$dst" 2>/dev/null && [ -s "$dst" ]; then exit 1; fi; \\
                 : > "$dst.thumbfail" 2>/dev/null; exit 0`
            ]
        }
        onExited: (exitCode, exitStatus) => {
            if (root._gone) return;
            if (exitCode === 1) { // Force reload if thumbnail had to be generated
                root.source = "";
                root.source = root.thumbnailPath; // Force reload
            }
        }
    }
}
