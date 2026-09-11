pragma Singleton
pragma ComponentBehavior: Bound

// Maps a bank-statement counterparty to an icon.
//
// Statement text is not a brand name — you get "PAYPAL *NETFLIX", "REWE SAGT
// DANKE 12345", "AMZN Mktp DE M4X8". So matching is substring-on-lowercase
// rather than exact, and the first hit wins.
//
// Two outputs per merchant: `icons` are icon-theme names to try (Papirus ships
// ~8000 app icons, most brands among them), and `symbol` is the Material
// Symbol to fall back to when none resolve. BrandIcon walks that chain.

import Quickshell

Singleton {
    id: root

    // Ordered: first match wins, so put specific before generic.
    readonly property var merchants: [
        { match: ["netflix"],                 icons: ["netflix-desktop", "netflix"],           symbol: "movie" },
        { match: ["spotify"],                 icons: ["spotify-client", "spotify"],            symbol: "music_note" },
        { match: ["youtube", "google *yout"], icons: ["youtube", "youtube-music-desktop-app"], symbol: "smart_display" },
        { match: ["amazon", "amzn"],          icons: ["amazon-store", "amazon"],               symbol: "shopping_bag" },
        { match: ["steam"],                   icons: ["steam-icon", "steam"],                  symbol: "sports_esports" },
        { match: ["paypal"],                  icons: ["paypal"],                               symbol: "account_balance_wallet" },
        { match: ["github"],                  icons: ["github", "github-desktop"],             symbol: "code" },
        { match: ["openai", "chatgpt"],       icons: ["openai"],                               symbol: "smart_toy" },
        { match: ["anthropic", "claude"],     icons: ["anthropic", "claude"],                  symbol: "smart_toy" },
        { match: ["adobe"],                   icons: ["adobe"],                                symbol: "brush" },
        { match: ["apple", "itunes"],         icons: ["apple", "apple-logo"],                  symbol: "devices" },
        { match: ["microsoft", "xbox"],       icons: ["microsoft", "xbox"],                    symbol: "window" },
        { match: ["nintendo"],                icons: ["nintendo-switch", "nintendo"],          symbol: "sports_esports" },
        { match: ["playstation"],             icons: ["playstation", "psx"],                   symbol: "sports_esports" },
        { match: ["patreon"],                 icons: ["patreon"],                              symbol: "volunteer_activism" },
        { match: ["uber"],                    icons: ["uber"],                                 symbol: "local_taxi" },
        { match: ["lieferando", "lieferdi"],  icons: ["lieferando"],                           symbol: "delivery_dining" },
        { match: ["ikea"],                    icons: ["ikea"],                                 symbol: "chair" },
        { match: ["vodafone"],                icons: ["vodafone"],                             symbol: "signal_cellular_alt" },
        { match: ["telekom", "t-mobile"],     icons: ["telekom"],                              symbol: "signal_cellular_alt" },
        { match: ["deutsche bahn", "db vert", "bahn"], icons: ["deutschebahn", "db"],          symbol: "train" },
        { match: ["shell", "aral", "esso", "tankstelle"], icons: [],                           symbol: "local_gas_station" },
        { match: ["rewe"],                    icons: ["rewe"],                                 symbol: "local_grocery_store" },
        { match: ["edeka"],                   icons: ["edeka"],                                symbol: "local_grocery_store" },
        { match: ["aldi", "lidl", "penny", "netto", "kaufland"], icons: [],                    symbol: "local_grocery_store" },
        { match: ["dm-", "rossmann"],         icons: [],                                       symbol: "soap" },
        { match: ["apotheke"],                icons: [],                                       symbol: "medication" },
        { match: ["mcdonald", "burger king"], icons: [],                                       symbol: "lunch_dining" },
        { match: ["bakery", "bäckerei", "backerei"], icons: [],                                symbol: "bakery_dining" },
        { match: ["hausverwaltung", "miete", "vermiet"], icons: [],                            symbol: "home" },
        { match: ["versicherung", "allianz"], icons: [],                                       symbol: "shield" },
        { match: ["stadtwerke", "strom", "energie"], icons: [],                                symbol: "bolt" },
        { match: ["gehalt", "lohn", "salary", "arbeitgeber"], icons: [],                       symbol: "payments" },
    ]

    // Fallback when the counterparty is unknown but the category is not.
    readonly property var categorySymbols: ({
        "groceries":     "local_grocery_store",
        "subscriptions": "autorenew",
        "bills":         "receipt_long",
        "insurance":     "shield",
        "rent":          "home",
        "transport":     "directions_transit",
        "shopping":      "shopping_bag",
        "games":         "sports_esports",
        "eating-out":    "restaurant",
        "health":        "medication",
        "income":        "payments",
        "other":         "receipt"
    })

    function entryFor(counterparty) {
        const hay = (counterparty ?? "").toLowerCase();
        if (hay.length === 0) return null;
        for (const m of root.merchants) {
            for (const needle of m.match) {
                if (hay.includes(needle)) return m;
            }
        }
        return null;
    }

    /// Icon-theme names worth trying for this counterparty, best first.
    function iconNamesFor(counterparty) {
        const e = root.entryFor(counterparty);
        return e ? e.icons : [];
    }

    /// Material Symbol to draw when no themed icon resolves. Falls back through
    /// merchant → category → a generic receipt, so this never returns empty.
    function symbolFor(counterparty, category) {
        const e = root.entryFor(counterparty);
        if (e) return e.symbol;
        return root.categorySymbols[category] ?? "receipt";
    }
}
