pragma Singleton
pragma ComponentBehavior: Bound

// Wallpaper-effect variables, shared by WallTune (picks effect) and the
// WallEffectPanel popup (tunes it). Stored in background.effectParams (JSON
// keyed by effect path); Background merges the map into EffectRenderer.

import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property string currentEffect: Config.options.background.effect ?? ""
    readonly property var currentFx: AppDisplay.effectByPath(root.currentEffect)
    readonly property var currentParams: root.currentFx?.params ?? []
    readonly property bool hasVariables: root.currentParams.length > 0

    function effectParam(effectPath, param) {
        try {
            const all = JSON.parse(Config.options.background.effectParams || "{}");
            const one = all[effectPath];
            if (one && one[param.id] !== undefined) return one[param.id];
        } catch (e) {}
        return param.value;
    }

    function setEffectParam(effectPath, id, value) {
        let all = {};
        try { all = JSON.parse(Config.options.background.effectParams || "{}"); } catch (e) {}
        const one = Object.assign({}, all[effectPath] ?? {});
        one[id] = value;
        all[effectPath] = one;
        Config.options.background.effectParams = JSON.stringify(all);
    }

    function resetEffectParams(effectPath) {
        let all = {};
        try { all = JSON.parse(Config.options.background.effectParams || "{}"); } catch (e) {}
        delete all[effectPath];
        Config.options.background.effectParams = JSON.stringify(all);
    }
}
