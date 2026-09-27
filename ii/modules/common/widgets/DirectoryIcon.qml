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

    /// Every lookup passes a fallback name. Without one a theme that lacks the
    /// requested icon hands back an empty path and the tile renders as blank
    /// space, which is what an uninstalled icon theme looks like: the XDG
    /// folders resolve through their own fallbacks while every ordinary folder
    /// comes back empty.
    function themed(name, fallback) {
        return Quickshell.iconPath(name, fallback);
    }

    source: {
        if (!root.isDir)
            return root.themed("application-x-zerosize", "text-x-generic");

        // A folder icon named after the folder, for every directory and not
        // just the handful of XDG ones. Themes ship a lot of these — Reversal
        // has 192 (folder-android, folder-code, folder-blender…) — and looking
        // them up only for XDG paths left almost all of that artwork unused.
        // Spaces become dashes, which is the convention themes follow.
        const stem = (root.fileModelData?.fileName ?? "")
            .toLowerCase().replace(/\s+/g, "-");
        return root.themed(`folder-${stem}`, "inode-directory");
    }

    onStatusChanged: {
        // Null with an empty source is "the theme returned nothing", which is a
        // different failure from Error ("found it, could not decode it").
        if (status === Image.Error || (status === Image.Null && source == ""))
            source = root.themed("folder", "unknown");
    }

    /// What kind of file it is, for anything that is not a directory.
    Process {
        running: !root.isDir
        // `file` follows symlinks, and a link into an absent automount makes it
        // block for the whole autofs timeout — measured at 15s and 30s here,
        // once per entry, which stalls any folder holding one. The timeout
        // turns that into a 1s miss and the generic icon.
        command: ["timeout", "1", "file", "--mime", "-b",
                  root.fileModelData?.filePath ?? ""]
        stdout: StdioCollector {
            onStreamFinished: {
                // No output means the timeout fired or `file` failed; leave
                // whatever the theme already resolved.
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
