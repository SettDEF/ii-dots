import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

// From https://github.com/caelestia-dots/shell with modifications.
// License: GPLv3

Image {
    id: root
    required property var fileModelData
    asynchronous: true
    fillMode: Image.PreserveAspectFit

    // Every lookup gets a fallback name. Without one, a theme that lacks the
    // requested icon returns an empty path and the tile renders as blank space
    // — which is what happens here whenever the configured icon theme is not
    // actually installed: the XDG folders resolve through their own fallbacks
    // while every ordinary folder came back empty.
    source: {
        if (!fileModelData.fileIsDir)
            return Quickshell.iconPath("application-x-zerosize", "text-x-generic");

        if ([Directories.documents, Directories.downloads, Directories.music, Directories.pictures, Directories.videos].some(dir => FileUtils.trimFileProtocol(dir) === fileModelData.filePath))
            return Quickshell.iconPath(`folder-${fileModelData.fileName.toLowerCase()}`, "inode-directory");

        return Quickshell.iconPath("inode-directory", "folder");
    }

    onStatusChanged: {
        // Null covers "the theme returned an empty path", which is a different
        // failure from Error ("the file was there but would not decode").
        if (status === Image.Error || (status === Image.Null && source == ""))
            source = Quickshell.iconPath("folder", "unknown");
    }

    Process {
        running: !fileModelData.fileIsDir
        // `file` follows symlinks. A link into an absent automount (a removable
        // or network mount that is not attached) makes it hang for the full
        // autofs timeout — measured at 15s and 30s here, once per entry, which
        // stalls every folder view that contains one. The cap turns that into a
        // 1s miss and the generic icon below.
        command: ["timeout", "1", "file", "--mime", "-b", fileModelData.filePath]
        stdout: StdioCollector {
            onStreamFinished: {
                // Empty output means the cap fired (or `file` failed) — keep
                // whatever icon `source` already resolved to.
                if (text.trim().length === 0)
                    return;
                const mime = text.split(";")[0].replace("/", "-");
                root.source = Images.validImageTypes.some(t => mime === `image-${t}`) ? fileModelData.fileUrl : Quickshell.iconPath(mime, "image-missing");
            }
        }
    }
}
