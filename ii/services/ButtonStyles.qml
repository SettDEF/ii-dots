pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

// Button styles as code: one QML file each, the shell's (assets/buttons) and your own
// (~/.config/illogical-impulse/buttons, the same name wins). A style draws one button; the shell
// sets icon, danger, toggled, hovered, pressed, iconFamily and the theme's colours, and the menus
// (HeaderIconButton, HeaderActionGroup) read its size, gap and pill. Any of its properties can be
// changed in the config without editing it: appearance.glass.decor.panelButtonVars
// ({ "size": 32, "lighten": 1.4 }). An edited style file loads again at once.
Singleton {
    id: root

    readonly property string builtinDir: Quickshell.shellPath("assets/buttons")
    readonly property string userDir: `${Quickshell.env("HOME")}/.config/illogical-impulse/buttons`
    readonly property var decor: Config.options.appearance.glass.decor
    // "pill" while the menus do not follow the title bars
    readonly property string currentId: decor.panels === true ? (decor.panelButtons || "vibrant") : "pill"
    readonly property var vars: decor.panelButtonVars ?? ({})

    // id → file path, yours over the shell's
    readonly property var styles: {
        const m = {};
        for (let i = 0; i < builtinFiles.count; i++) m[builtinFiles.get(i, "fileBaseName")] = builtinFiles.get(i, "filePath");
        for (let i = 0; i < userFiles.count; i++) m[userFiles.get(i, "fileBaseName")] = userFiles.get(i, "filePath");
        return m;
    }
    readonly property var ids: Object.keys(root.styles).sort()
    readonly property string currentPath: root.styles[root.currentId] ?? root.styles["vibrant"] ?? `${root.builtinDir}/vibrant.qml`
    // bumped when the style file changes, so its new code is compiled (Qt keeps components by URL)
    property int nonce: 0
    readonly property url currentUrl: `file://${root.currentPath}?v=${root.nonce}`

    FolderListModel {
        id: builtinFiles
        folder: "file://" + root.builtinDir
        nameFilters: ["*.qml"]
        showDirs: false
    }
    FolderListModel {
        id: userFiles
        folder: "file://" + root.userDir
        nameFilters: ["*.qml"]
        showDirs: false
    }
    FileView {
        path: root.currentPath
        watchChanges: true
        onFileChanged: root.nonce++
    }
}
