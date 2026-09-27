pragma Singleton

import Quickshell

/// Names from other people's vocabularies mapped onto Material Symbols: the
/// freedesktop icon names BlueZ reports, and the numeric condition codes the
/// weather API returns.
Singleton {
    id: root

    /// BlueZ reports a freedesktop icon name per device. Matched on substrings
    /// because the names vary by adapter and by device ("audio-headset",
    /// "audio-card", "input-mouse"), and a table of exact names would miss
    /// whatever the next device calls itself.
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

    /// Weather condition codes, grouped by what the weather actually is rather
    /// than listed one by one: the codes come in runs (light/moderate/heavy of
    /// the same thing) that all deserve the same symbol, and fifty separate
    /// entries hid that.
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

    /// Falls back to a plain cloud: an unknown code is still weather, and a
    /// missing symbol name renders as nothing at all.
    function getWeatherIcon(code): string {
        return root.weatherIconMap[String(code)] ?? "cloud";
    }
}
