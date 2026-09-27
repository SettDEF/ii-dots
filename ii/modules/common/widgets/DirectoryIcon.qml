import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/// The icon for one entry in a file listing: a themed folder icon for a
/// directory, the picture itself for an image, a themed MIME icon otherwise.
Image {
    id: root
    required property var fileModelData

    readonly property bool isDir: root.fileModelData?.fileIsDir ?? false

    asynchronous: true
    fillMode: Image.PreserveAspectFit

    /// Always pass a fallback: a theme missing the icon returns an empty path
    /// and the tile renders blank.
    function themed(name, fallback) {
        return Quickshell.iconPath(name, fallback);
    }

    source: {
        if (!root.isDir)
            return root.themed("application-x-zerosize", "text-x-generic");

        // Themes ship per-name folder icons (Reversal has 192), not just the
        // XDG ones. Spaces become dashes, which is the naming convention.
        const stem = (root.fileModelData?.fileName ?? "")
            .toLowerCase().replace(/\s+/g, "-");
        return root.themed(`folder-${stem}`, "inode-directory");
    }

    onStatusChanged: {
        // Null + empty source is "theme returned nothing"; Error is "would not decode".
        if (status === Image.Error || (status === Image.Null && source == ""))
            source = root.themed("folder", "unknown");
    }

    /// What kind of file it is, for anything that is not a directory.
    Process {
        running: !root.isDir
        // `file` follows symlinks; one into an absent automount blocks for the
        // autofs timeout (15-30s here) per entry. The cap makes that a 1s miss.
        command: ["timeout", "1", "file", "--mime", "-b",
                  root.fileModelData?.filePath ?? ""]
        stdout: StdioCollector {
            onStreamFinished: {
                // No output = timeout or failure; keep what the theme resolved.
                const out = text.trim();
                if (out.length === 0) return;

                const mime = out.split(";")[0].replace("/", "-");
                const isImage = Images.validImageTypes.some(t => mime === `image-${t}`);
                root.source = isImage ? root.fileModelData.fileUrl
                                      : root.themed(mime, "image-missing");
            }
        }
    }
}
