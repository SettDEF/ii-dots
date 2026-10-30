pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Automatically reloads generated material colors.
 * It is necessary to run reapplyTheme() on startup because Singletons are lazily loaded.
 */
Singleton {
    id: root
    property string filePath: Directories.generatedMaterialThemePath

    function reapplyTheme() {
        root.lastApplied = ""   // asked for on purpose: applied even when the text is the same
        themeFileView.reload()
        termFileView.reload()
    }

    // the text last applied: the file watcher and the reload message both arrive for one switch
    property string lastApplied: ""
    function applyColors(fileContent) {
        if (fileContent === root.lastApplied) return
        root.lastApplied = fileContent
        const t0 = Date.now()
        const json = JSON.parse(fileContent)
        let changed = 0
        for (const key in json) {
            if (json.hasOwnProperty(key)) {
                // Convert snake_case to CamelCase
                const camelCaseKey = key.replace(/_([a-z])/g, (g) => g[1].toUpperCase())
                const m3Key = `m3${camelCaseKey}`
                // only colours the shell has, and only when they changed: each set re-runs every
                // binding that reads it (tinct's 128 shades have no place here)
                if (!(m3Key in Appearance.m3colors)) continue
                if (Qt.colorEqual(Appearance.m3colors[m3Key], json[key])) continue
                Appearance.m3colors[m3Key] = json[key]
                changed++
            }
        }
        console.info(`[MaterialThemeLoader] ${changed} colours in ${Date.now() - t0} ms`)

        Appearance.m3colors.darkmode = (Appearance.m3colors.m3background.hslLightness < 0.5)
    }

    function resetFilePathNextTime() {
        resetFilePathNextWallpaperChange.enabled = true
    }

    Connections {
        id: resetFilePathNextWallpaperChange
        enabled: false
        target: Config.options.background
        function onWallpaperPathChanged() {
            root.filePath = ""
            root.filePath = Directories.generatedMaterialThemePath
            resetFilePathNextWallpaperChange.enabled = false
        }
    }

    IpcHandler {
        target: "materialTheme"
        // read the file again (an atomic move the watcher missed); the same text is not applied twice
        function reload(): void {
            themeFileView.reload()
        }
    }

    FileView {
        id: themeFileView
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onFileChanged: {
            this.reload()
        }
        onLoadedChanged: {
            if (loaded) {
                const fileContent = themeFileView.text()
                root.applyColors(fileContent)
            }
        }
        onLoadFailed: root.resetFilePathNextTime();
    }

    // The theme's own hues (Catppuccin's red, Dracula's green …), from tinct's terminal colours:
    // colorN lines become m3colors.termN. Missing file: the defaults stay.
    FileView {
        id: termFileView
        path: Qt.resolvedUrl(Directories.generatedTerminalThemePath)
        watchChanges: true
        onFileChanged: this.reload()
        function apply() {
            for (const line of termFileView.text().split("\n")) {
                const m = /^color(\d+)\s+(#[0-9a-fA-F]{6})/.exec(line);
                if (m && +m[1] < 16) Appearance.m3colors[`term${m[1]}`] = m[2];
            }
        }
        onLoaded: apply()
        Component.onCompleted: if (loaded) apply()
    }
}
