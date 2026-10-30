pragma ComponentBehavior: Bound
pragma Singleton
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Qt.labs.synchronizer
import Quickshell

Singleton {
    id: root

    enum Action {
        Copy,
        Edit,
        Search,
        CharRecognition,
        Record,
        RecordWithSound,
        AttachToAi
    }

    // the same values as the enum above, as a plain object: quickshell does not expose a singleton's
    // enum at runtime (ScreenshotAction.Action came back undefined and every snip threw)
    readonly property var actions: ({ "Copy": 0, "Edit": 1, "Search": 2, "CharRecognition": 3, "Record": 4, "RecordWithSound": 5, "AttachToAi": 6 })

    property string imageSearchEngineBaseUrl: Config.options.search.imageSearch.imageSearchEngineBaseUrl
    property string fileUploadApiEndpoint: "https://uguu.se/upload"

    function getCommand(x, y, width, height, screenshotPath, action, saveDir = "") {
        // Set command for action
        const rx = Math.round(x);
        const ry = Math.round(y);
        const rw = Math.round(width);
        const rh = Math.round(height);
        // tinct image crop SRC GEOMETRY DST; DST "-" is PNG on stdout.
        const cropBase = `"$HOME/.local/bin/tinct" image crop '${StringUtils.shellSingleQuoteEscape(screenshotPath)}' `
            + `${rw}x${rh}+${Math.max(0, rx)}+${Math.max(0, ry)}`
        const cropToStdout = `${cropBase} -`
        const gifFlag = Persistent.states.snip.gif ? " --gif" : "";
        const cropInPlace = `${cropBase} '${StringUtils.shellSingleQuoteEscape(screenshotPath)}'`
        const cleanup = `rm '${StringUtils.shellSingleQuoteEscape(screenshotPath)}'`
        const slurpRegion = `${rx},${ry} ${rw}x${rh}`
        const uploadAndGetUrl = (filePath) => {
            return `curl -sF files[]=@'${StringUtils.shellSingleQuoteEscape(filePath)}' ${root.fileUploadApiEndpoint} | jq -r '.files[0].url'`
        }
        const annotationCommand = `${Config.options.regionSelector.annotation.useSatty ? "satty" : "swappy"} -f -`;
        switch (action) {
            case ScreenshotAction.actions.Copy:
                if (saveDir === "") {
                    // Not saving — just copy to clipboard. `--type image/png`
                    // so wl-copy never has to guess the MIME type. A trace is
                    // left at /tmp/quickshell-snip-copy.log for debugging.
                    return ["bash", "-c",
                        `exec 2>/tmp/quickshell-snip-copy.log; set -x; `
                        + `${cropToStdout} | wl-copy --type image/png && ${cleanup}`]
                    break;
                }
                // Save + copy. Write the crop to the file first, then copy
                // from that file — deterministic, unlike `tee >(wl-copy)`
                // (bash does not wait for the process substitution, so
                // wl-copy can be killed before it has read the image).
                return [
                    "bash", "-c",
                    `exec 2>/tmp/quickshell-snip-copy.log; set -x; \
                    mkdir -p '${StringUtils.shellSingleQuoteEscape(saveDir)}' && \
                    saveFileName="screenshot-$(date '+%Y-%m-%d_%H.%M.%S').png" && \
                    savePath="${saveDir}/$saveFileName" && \
                    ${cropBase} "$savePath" && \
                    wl-copy --type image/png < "$savePath" && \
                    ${cleanup}`
                ]

                break;
            case ScreenshotAction.actions.Edit:
                // Crop to a stable file, then ask Quickshell's native editor
                // to open it via IPC. The editor's Save merges + writes back.
                const editPath = `/tmp/quickshell-snip-${Date.now()}.png`
                return ["bash", "-c",
                    `${cropBase} '${editPath}' && ` +
                    `qs -c ii ipc call screenshotEditor open '${editPath}' && ` +
                    `${cleanup}`]
                break;
            case ScreenshotAction.actions.Search:
                return ["bash", "-c", `${cropInPlace} && xdg-open "${root.imageSearchEngineBaseUrl}$(${uploadAndGetUrl(screenshotPath)})" && ${cleanup}`]
                break;
            case ScreenshotAction.actions.CharRecognition:
                return ["bash", "-c", `${cropInPlace} && tesseract '${StringUtils.shellSingleQuoteEscape(screenshotPath)}' stdout -l $(tesseract --list-langs | awk 'NR>1{print $1}' | tr '\\n' '+' | sed 's/\\+$/\\n/') | wl-copy && ${cleanup}`]
                break;
            case ScreenshotAction.actions.Record:
                return ["bash", "-c", `${Directories.recordScriptPath} --region '${slurpRegion}'${gifFlag}`]
                break;
            case ScreenshotAction.actions.RecordWithSound:
                return ["bash", "-c", `${Directories.recordScriptPath} --region '${slurpRegion}' --sound${gifFlag}`]
                break;
            case ScreenshotAction.actions.AttachToAi:
                const attachPath = `/tmp/quickshell-ai-snip-${Date.now()}.png`
                return ["bash", "-c",
                    `${cropBase} '${attachPath}' && ` +
                    `qs -c ii ipc call ai attachFile '${attachPath}' && ` +
                    `${cleanup}`]
                break;
            default:
                console.warn("[Region Selector] Unknown snip action, skipping snip.");
                return;
        }
    }
}
