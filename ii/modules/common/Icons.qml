pragma Singleton

import Quickshell

/// Other people's vocabularies mapped onto Material Symbols: freedesktop icon
/// names from BlueZ, condition codes from the weather API.
Singleton {
    id: root

    /// Substrings, not exact names: they vary by adapter ("audio-headset",
    /// "audio-card", "input-mouse").
    function getBluetoothDeviceMaterialSymbol(systemIconName: string): string {
        const name = (systemIconName ?? "").toLowerCase();
        if (name.includes("headset") || name.includes("headphone")) return "headphones";
        if (name.includes("mouse")) return "mouse";
        if (name.includes("keyboard")) return "keyboard";
        if (name.includes("phone")) return "smartphone";
        if (name.includes("watch")) return "watch";
        if (name.includes("printer")) return "print";
        if (name.includes("camera")) return "photo_camera";
        if (name.includes("gaming") || name.includes("joystick")) return "sports_esports";
        if (name.includes("computer") || name.includes("laptop")) return "computer";
        if (name.includes("audio") || name.includes("speaker")) return "speaker";
        return "bluetooth";
    }

    /// Grouped by condition: the codes come in light/moderate/heavy runs that
    /// share a symbol.
    readonly property var weatherGroups: [
        { symbol: "clear_day",         codes: [113] },
        { symbol: "partly_cloudy_day", codes: [116] },
        { symbol: "cloud",             codes: [119, 122] },
        { symbol: "foggy",             codes: [143, 248, 260] },
        { symbol: "thunderstorm",      codes: [200, 386, 389, 392] },
        { symbol: "cloudy_snowing",    codes: [227, 320, 323, 326, 368] },
        { symbol: "snowing_heavy",     codes: [230, 329, 332, 338] },
        { symbol: "snowing",           codes: [335, 371, 395] },
        { symbol: "weather_hail",      codes: [302, 308, 359] },
        { symbol: "rainy",             codes: [176, 179, 182, 185, 263, 266, 281, 284,
                                               293, 296, 299, 305, 311, 314, 317, 350,
                                               353, 356, 362, 365, 374, 377] }
    ]

    readonly property var weatherIconMap: {
        const out = {};
        for (const group of root.weatherGroups)
            for (const code of group.codes) out[String(code)] = group.symbol;
        return out;
    }

    /// Falls back to a cloud: a missing symbol name renders as nothing.
    function getWeatherIcon(code): string {
        return root.weatherIconMap[String(code)] ?? "cloud";
    }
}
