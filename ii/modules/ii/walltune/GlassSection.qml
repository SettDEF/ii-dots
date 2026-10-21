pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Palette > Glass. Grouped cards: each card is one topic, rows inside share
 * one height, one icon column and one value column. Applied live by
 * services/Glass.qml.
 */
ColumnLayout {
    id: root
    spacing: 10

    readonly property var cfg: Config.options.appearance.glass
    property string openApp: ""
    property bool compositorOpen: false
    property bool decorStyleOpen: false
    property bool decorAppsOpen: false
    readonly property var roleModel: [
        { id: "surface", label: qsTr("Surface") }, { id: "low", label: qsTr("Low") },
        { id: "container", label: qsTr("Container") }, { id: "high", label: qsTr("High") },
        { id: "highest", label: qsTr("Highest") },
    ]

    /* --- building blocks ------------------------------------------------- */




    /// Icon · title (+ subtitle) · value · chevron or switch. One height.

    /// Title and value on one line, the slider under it.

    component Caption: StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.leftMargin: 4
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Medium
        color: Appearance.colors.colSubtext
    }

    function pct(v) { return Math.round(v * 100) + "%" }
    function appValue(id) {
        const st = Glass.appState(id);
        return st.on ? qsTr("On · %1").arg(root.pct(st.opacity)) : qsTr("Off");
    }
    readonly property int liveCount: {
        void root.cfg.apps;
        return Glass.apps.filter(a => Glass.appState(a.id).on).length;
    }

    /* --- main card -------------------------------------------------------- */

    PaletteCard {
        PaletteRow {
            glyph: "blur_on"
            title: qsTr("Glass")
            subtitle: !root.cfg.enable ? qsTr("Off")
                : (!Glass.active ? qsTr("Paused on battery")
                   : (root.liveCount === 1 ? qsTr("1 app see-through") : qsTr("%1 apps see-through").arg(root.liveCount)))
            lit: Glass.active
            trailing: "switch"
            isOn: root.cfg.enable
            onSwitched: root.cfg.enable = !root.cfg.enable
        }
        PaletteDivider {}
        PaletteSlider {
            title: qsTr("Strength, all apps")
            valueText: root.pct(root.cfg.strength)
            from: 0.3; to: 1; stepSize: 0.01
            value: root.cfg.strength
            onMoved: v => {
                root.cfg.strength = v;
                const next = Object.assign({}, root.cfg.apps ?? {});
                for (const a of Glass.apps)
                    next[a.id] = Object.assign(Glass.appState(a.id), { opacity: v });
                root.cfg.apps = next;
            }
        }
        PaletteDivider {}
        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: 10
            spacing: 6
            StyledText {
                text: qsTr("On battery")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
            }
            SegmentedButtons {
                Layout.fillWidth: true
                showCheck: false
                segmentHeight: 32
                colIndicator: Appearance.colors.colPrimary
                colActiveText: Appearance.colors.colOnPrimary
                currentId: root.cfg.battery
                onSelected: id => root.cfg.battery = id
                model: [
                    { id: "same",    label: qsTr("Same"),    icon: "bolt" },
                    { id: "lighter", label: qsTr("Lighter"), icon: "battery_saver" },
                    { id: "off",     label: qsTr("Off"),     icon: "block" },
                ]
            }
        }
    }

    PaletteCard {
        PaletteRow {
            glyph: "tune"
            title: qsTr("Compositor")
            subtitle: qsTr("Blur, noise, vibrancy, dim")
            value: qsTr("%1 px · %2×").arg(root.cfg.compositor.size).arg(Glass.lighter ? 1 : root.cfg.compositor.passes)
            lit: Glass.active
            onClicked: root.compositorOpen = true
        }
        PaletteDivider {}
        PaletteRow {
            glyph: "dock_to_bottom"
            title: qsTr("Shell surfaces")
            subtitle: qsTr("Bar, dock and panels")
            trailing: "switch"
            lit: Config.options.appearance.transparency.enable
            isOn: Config.options.appearance.transparency.enable
            onSwitched: Config.options.appearance.transparency.enable = !Config.options.appearance.transparency.enable
        }
        // The automatic amount follows the wallpaper and is often small, so the
        // switch alone barely showed. Manual amounts make the difference visible.
        PaletteDivider { visible: Config.options.appearance.transparency.enable }
        PaletteRow {
            visible: Config.options.appearance.transparency.enable
            glyph: "auto_mode"
            title: qsTr("Automatic amount")
            subtitle: qsTr("Follows the wallpaper")
            trailing: "switch"
            isOn: Config.options.appearance.transparency.automatic
            lit: isOn
            onSwitched: Config.options.appearance.transparency.automatic = !Config.options.appearance.transparency.automatic
        }
        PaletteSlider {
            visible: Config.options.appearance.transparency.enable
            title: qsTr("Background see-through")
            valueText: root.pct(Appearance.backgroundTransparency)
            from: 0; to: 0.7; stepSize: 0.01
            value: Appearance.backgroundTransparency
            onMoved: v => {
                Config.options.appearance.transparency.automatic = false;
                Config.options.appearance.transparency.backgroundTransparency = v;
            }
        }
        PaletteSlider {
            visible: Config.options.appearance.transparency.enable
            title: qsTr("Content see-through")
            valueText: root.pct(Appearance.contentTransparency)
            from: 0; to: 0.9; stepSize: 0.01
            value: Appearance.contentTransparency
            onMoved: v => {
                Config.options.appearance.transparency.automatic = false;
                Config.options.appearance.transparency.contentTransparency = v;
            }
        }
        Item { implicitHeight: 6; visible: Config.options.appearance.transparency.enable }
    }

    /* --- window title bars (ii-decor) --------------------------------------- */

    Component.onCompleted: Glass.checkDecor()

    PaletteCard {
        PaletteRow {
            glyph: "web_asset"
            title: qsTr("Window title bars")
            subtitle: Glass.decorLoaded ? qsTr("Dots on the %1, apps with their own bar skipped")
                                            .arg(root.cfg.decor.buttons === "left" ? qsTr("left") : qsTr("right"))
                                        : qsTr("Plugin not loaded yet")
            trailing: "switch"
            isOn: root.cfg.decor.enable
            lit: isOn && Glass.decorLoaded
            onSwitched: root.cfg.decor.enable = !root.cfg.decor.enable
        }
        PaletteDivider { visible: root.cfg.decor.enable }
        PaletteSlider {
            visible: root.cfg.decor.enable
            title: qsTr("Bar height"); valueText: root.cfg.decor.height + " px"
            from: 22; to: 40; stepSize: 1; value: root.cfg.decor.height
            onMoved: v => root.cfg.decor.height = Math.round(v)
        }
        PaletteDivider { visible: root.cfg.decor.enable }
        PaletteRow {
            visible: root.cfg.decor.enable
            glyph: "title"
            title: qsTr("Show window title")
            trailing: "switch"
            isOn: root.cfg.decor.title
            lit: isOn
            onSwitched: root.cfg.decor.title = !root.cfg.decor.title
        }
        PaletteDivider { visible: root.cfg.decor.enable }
        ColumnLayout {
            visible: root.cfg.decor.enable
            Layout.fillWidth: true
            Layout.margins: 10
            spacing: 6
            StyledText {
                text: qsTr("Buttons")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
            }
            SegmentedButtons {
                Layout.fillWidth: true
                showCheck: false
                segmentHeight: 32
                colIndicator: Appearance.colors.colPrimary
                colActiveText: Appearance.colors.colOnPrimary
                currentId: root.cfg.decor.buttons
                onSelected: id => root.cfg.decor.buttons = id
                model: [
                    { id: "left",  label: qsTr("Left"),  icon: "align_horizontal_left" },
                    { id: "right", label: qsTr("Right"), icon: "align_horizontal_right" },
                ]
            }
        }
        PaletteDivider { visible: root.cfg.decor.enable }
        PaletteRow {
            visible: root.cfg.decor.enable
            glyph: "format_paint"
            title: qsTr("Style")
            subtitle: qsTr("Colour, opacity, dots, title, icon, behaviour")
            value: ({ surface: qsTr("Surface"), low: qsTr("Low"), container: qsTr("Container"),
                      high: qsTr("High"), highest: qsTr("Highest") })[root.cfg.decor.barRole] ?? ""
            lit: true
            onClicked: root.decorStyleOpen = true
        }
        PaletteDivider { visible: root.cfg.decor.enable }
        PaletteRow {
            visible: root.cfg.decor.enable
            glyph: "palette"
            title: qsTr("Per-app title bars")
            subtitle: qsTr("Match the bar to an app's own toolbar")
            value: { const n = Object.keys(root.cfg.decor.perApp ?? {}).length; return n > 0 ? qsTr("%1 set").arg(n) : "" }
            lit: Object.keys(root.cfg.decor.perApp ?? {}).length > 0
            onClicked: root.decorAppsOpen = true
        }
    }

    /* --- apps -------------------------------------------------------------- */

    // Each group lists the apps that are on; the rest fold into one row.
    AppGlassGroup {
        title: qsTr("Real glass · text stays solid")
        glyph: "blur_on"
        apps: Glass.apps.filter(a => a.kind === "native" && a.id !== "websites")  // websites: inside tela-zen
        section: root
    }
    AppGlassGroup {
        title: qsTr("Whole window · text fades too")
        glyph: "select_window"
        apps: Glass.apps.filter(a => a.kind === "window")
        section: root
    }

    /* --- sheets -------------------------------------------------------------- */

    PanelSheet {
        open: root.compositorOpen
        title: qsTr("Compositor")
        subtitle: Glass.lighter ? qsTr("On battery: blur limited to 1 pass") : ""
        onClosed: root.compositorOpen = false

        PaletteCard {
            PaletteSlider {
                title: qsTr("Blur size"); valueText: root.cfg.compositor.size + " px"
                from: 1; to: 20; stepSize: 1; value: root.cfg.compositor.size
                onMoved: v => root.cfg.compositor.size = Math.round(v)
            }
            PaletteSlider {
                title: qsTr("Passes"); valueText: root.cfg.compositor.passes + "×"
                from: 1; to: 4; stepSize: 1; value: root.cfg.compositor.passes
                onMoved: v => root.cfg.compositor.passes = Math.round(v)
            }
            PaletteSlider {
                title: qsTr("Noise"); valueText: root.cfg.compositor.noise.toFixed(2)
                from: 0; to: 0.2; stepSize: 0.005; value: root.cfg.compositor.noise
                onMoved: v => root.cfg.compositor.noise = v
            }
            PaletteSlider {
                title: qsTr("Contrast"); valueText: root.cfg.compositor.contrast.toFixed(2)
                from: 0.5; to: 1.5; stepSize: 0.01; value: root.cfg.compositor.contrast
                onMoved: v => root.cfg.compositor.contrast = v
            }
            PaletteSlider {
                title: qsTr("Brightness"); valueText: root.cfg.compositor.brightness.toFixed(2)
                from: 0.5; to: 1.5; stepSize: 0.01; value: root.cfg.compositor.brightness
                onMoved: v => root.cfg.compositor.brightness = v
            }
            PaletteSlider {
                title: qsTr("Vibrancy"); valueText: root.cfg.compositor.vibrancy.toFixed(2)
                from: 0; to: 1; stepSize: 0.01; value: root.cfg.compositor.vibrancy
                onMoved: v => root.cfg.compositor.vibrancy = v
            }
            Item { implicitHeight: 6 }
        }
        PaletteCard {
            PaletteRow {
                glyph: "visibility"; title: qsTr("Xray")
                subtitle: qsTr("See through to the wallpaper, not the windows behind")
                trailing: "switch"; isOn: root.cfg.compositor.xray; lit: isOn
                onSwitched: root.cfg.compositor.xray = !root.cfg.compositor.xray
            }
            PaletteDivider {}
            PaletteRow {
                glyph: "menu_open"; title: qsTr("Blur popups and menus")
                trailing: "switch"; isOn: root.cfg.compositor.popups; lit: isOn
                onSwitched: root.cfg.compositor.popups = !root.cfg.compositor.popups
            }
            PaletteDivider {}
            PaletteRow {
                glyph: "brightness_6"; title: qsTr("Dim inactive windows")
                trailing: "switch"; isOn: root.cfg.compositor.dimInactive; lit: isOn
                onSwitched: root.cfg.compositor.dimInactive = !root.cfg.compositor.dimInactive
            }
            PaletteSlider {
                visible: root.cfg.compositor.dimInactive
                title: qsTr("Dim amount"); valueText: root.pct(root.cfg.compositor.dimStrength)
                from: 0; to: 0.4; stepSize: 0.01; value: root.cfg.compositor.dimStrength
                onMoved: v => root.cfg.compositor.dimStrength = v
            }
            Item { implicitHeight: 6 }
        }
    }

    PanelSheet {
        id: appSheet
        readonly property var a: Glass.app(root.openApp)
        readonly property var st: { void root.cfg.apps; return Glass.appState(root.openApp) }
        open: root.openApp.length > 0
        title: appSheet.a?.name ?? ""
        subtitle: appSheet.a?.kind === "window" ? qsTr("Whole window: text fades too")
                                                 : qsTr("Real glass: text stays solid")
        onClosed: root.openApp = ""

        PaletteCard {
            PaletteRow {
                glyph: appSheet.a?.icon ?? ""
                title: qsTr("See-through")
                subtitle: root.cfg.enable ? "" : qsTr("Glass is off: turn it on to see this")
                trailing: "switch"; isOn: appSheet.st.on; lit: isOn
                onSwitched: Glass.setApp(root.openApp, { on: !appSheet.st.on })
            }
            PaletteDivider {}
            PaletteSlider {
                title: qsTr("Opacity"); valueText: root.pct(appSheet.st.opacity)
                from: 0.3; to: 1; stepSize: 0.01; value: appSheet.st.opacity
                onMoved: v => Glass.setApp(root.openApp, { opacity: v })
            }
            PaletteDivider {}
            PaletteRow {
                visible: (appSheet.a?.cls ?? "").length > 0
                glyph: "blur_on"; title: qsTr("Blur behind")
                trailing: "switch"; isOn: appSheet.st.blur; lit: isOn
                onSwitched: Glass.setApp(root.openApp, { blur: !appSheet.st.blur })
            }
        }
        // tela-zen only: the pages it shows. Websites go see-through through the
        // tinct live userscript; kept as its own Glass app ("websites") so the
        // page opacity stays separate from the browser chrome's.
        PaletteCard {
            id: websitesCard
            visible: root.openApp === "zen"
            readonly property var ws: { void root.cfg.apps; return Glass.appState("websites") }
            PaletteRow {
                glyph: "public"
                title: qsTr("See-through websites")
                subtitle: qsTr("Page backgrounds, via the tinct live userscript")
                trailing: "switch"; isOn: websitesCard.ws.on; lit: isOn
                onSwitched: Glass.setApp("websites", { on: !websitesCard.ws.on })
            }
            PaletteDivider { visible: websitesCard.ws.on }
            PaletteSlider {
                visible: websitesCard.ws.on
                title: qsTr("Website opacity"); valueText: root.pct(websitesCard.ws.opacity)
                from: 0.3; to: 1; stepSize: 0.01; value: websitesCard.ws.opacity
                onMoved: v => Glass.setApp("websites", { opacity: v })
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: (appSheet.a?.note ?? "").length > 0
            text: appSheet.a?.note ?? ""
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
    }

    /* --- title bar sheets ------------------------------------------------ */

    PanelSheet {
        open: root.decorStyleOpen
        title: qsTr("Title bar style")
        onClosed: root.decorStyleOpen = false
        readonly property var d: root.cfg.decor

        // the shell's menus: whether they follow these title bars, and their button style
        // (a QML package: services/ButtonStyles.qml, your own in ~/.config/illogical-impulse/buttons)
        PaletteCard {
            ColumnLayout {
                Layout.fillWidth: true; Layout.margins: 10; spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    StyledText { Layout.fillWidth: true; text: qsTr("Menus follow the title bars"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer1 }
                    PaletteSwitch { checked: root.cfg.decor.panels; onToggled: root.cfg.decor.panels = !root.cfg.decor.panels }
                }
                StyledText { text: qsTr("Menu buttons"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer1 }
                SegmentedButtons {
                    Layout.fillWidth: true; showCheck: false; segmentHeight: 30
                    enabled: root.cfg.decor.panels
                    colIndicator: Appearance.colors.colPrimary; colActiveText: Appearance.colors.colOnPrimary
                    currentId: ButtonStyles.currentId; onSelected: id => root.cfg.decor.panelButtons = id
                    model: ButtonStyles.ids.map(id => ({ id: id, label: id.charAt(0).toUpperCase() + id.slice(1) }))
                }
            }
            PaletteSlider {
                readonly property var vars: root.cfg.decor.panelButtonVars ?? ({})
                title: qsTr("Menu button size"); valueText: (vars.size ?? 28) + " px"
                from: 16; to: 40; stepSize: 1; value: vars.size ?? 28
                onMoved: v => root.cfg.decor.panelButtonVars = Object.assign({}, vars, { size: Math.round(v) })
            }
        }
        PaletteCard {
            ColumnLayout {
                Layout.fillWidth: true; Layout.margins: 10; spacing: 6
                StyledText { text: qsTr("Look"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer1 }
                SegmentedButtons {
                    Layout.fillWidth: true; showCheck: false; segmentHeight: 30
                    colIndicator: Appearance.colors.colPrimary; colActiveText: Appearance.colors.colOnPrimary
                    currentId: root.cfg.decor.theme; onSelected: id => root.cfg.decor.theme = id
                    model: [{ id: "dots", label: qsTr("Dots") }, { id: "breeze", label: qsTr("Breeze") }]
                }
                StyledText { text: qsTr("Buttons"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer1 }
                SegmentedButtons {
                    Layout.fillWidth: true; showCheck: false; segmentHeight: 30
                    colIndicator: Appearance.colors.colPrimary; colActiveText: Appearance.colors.colOnPrimary
                    currentId: root.cfg.decor.layout; onSelected: id => root.cfg.decor.layout = id
                    model: [{ id: "macos", label: qsTr("Standard") }, { id: "macos-left", label: qsTr("Left") },
                            { id: "extended", label: qsTr("+ Pin, float") }]
                }
                StyledText { text: qsTr("Colours from"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer1 }
                SegmentedButtons {
                    Layout.fillWidth: true; showCheck: false; segmentHeight: 30
                    colIndicator: Appearance.colors.colPrimary; colActiveText: Appearance.colors.colOnPrimary
                    currentId: root.cfg.decor.colorSource; onSelected: id => root.cfg.decor.colorSource = id
                    model: [{ id: "app", label: qsTr("Each app") }, { id: "kde", label: qsTr("KDE scheme") },
                            { id: "shell", label: qsTr("Shell") }]
                }
            }
        }
        PaletteCard {
            ColumnLayout {
                Layout.fillWidth: true; Layout.margins: 10; spacing: 6
                StyledText { text: qsTr("Bar colour"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer1 }
                SegmentedButtons {
                    Layout.fillWidth: true; showCheck: false; segmentHeight: 30; model: root.roleModel
                    colIndicator: Appearance.colors.colPrimary; colActiveText: Appearance.colors.colOnPrimary
                    currentId: root.cfg.decor.barRole; onSelected: id => root.cfg.decor.barRole = id }
            }
            PaletteDivider {}
            PaletteRow {
                glyph: "blur_on"; title: qsTr("Follow Glass opacity")
                subtitle: qsTr("See-through at the Glass strength")
                trailing: "switch"; isOn: root.cfg.decor.barOpacity < 0; lit: isOn
                onSwitched: root.cfg.decor.barOpacity = root.cfg.decor.barOpacity < 0 ? 1 : -1
            }
            PaletteSlider {
                visible: root.cfg.decor.barOpacity >= 0
                title: qsTr("Bar opacity"); valueText: root.pct(root.cfg.decor.barOpacity)
                from: 0.3; to: 1; stepSize: 0.01; value: Math.max(0.3, root.cfg.decor.barOpacity)
                onMoved: v => root.cfg.decor.barOpacity = v
            }
            PaletteDivider {}
            PaletteRow {
                glyph: "horizontal_rule"; title: qsTr("Separator line")
                subtitle: qsTr("Thin line between bar and app")
                trailing: "switch"; isOn: root.cfg.decor.separator; lit: isOn
                onSwitched: root.cfg.decor.separator = !root.cfg.decor.separator
            }
            PaletteDivider {}
            PaletteRow {
                glyph: "blur_circular"; title: qsTr("Blur behind the bar")
                trailing: "switch"; isOn: root.cfg.decor.blur; lit: isOn
                onSwitched: root.cfg.decor.blur = !root.cfg.decor.blur
            }
        }
        PaletteCard {
            ColumnLayout {
                Layout.fillWidth: true; Layout.margins: 10; spacing: 6
                StyledText { text: qsTr("Dots"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer1 }
                SegmentedButtons {
                    Layout.fillWidth: true; showCheck: false; segmentHeight: 30
                    colIndicator: Appearance.colors.colPrimary; colActiveText: Appearance.colors.colOnPrimary
                    currentId: root.cfg.decor.dots; onSelected: id => root.cfg.decor.dots = id
                    model: [{ id: "theme", label: qsTr("Theme colours") }, { id: "macos", label: qsTr("Classic macOS") }]
                }
            }
            PaletteSlider {
                title: qsTr("Dot size"); valueText: root.cfg.decor.buttonSize + " px"
                from: 8; to: 18; stepSize: 1; value: root.cfg.decor.buttonSize
                onMoved: v => root.cfg.decor.buttonSize = Math.round(v)
            }
            PaletteSlider {
                title: qsTr("Dot spacing"); valueText: root.cfg.decor.buttonGap + " px"
                from: 2; to: 16; stepSize: 1; value: root.cfg.decor.buttonGap
                onMoved: v => root.cfg.decor.buttonGap = Math.round(v)
            }
            PaletteSlider {
                title: qsTr("Edge padding"); valueText: root.cfg.decor.padding + " px"
                from: 4; to: 24; stepSize: 1; value: root.cfg.decor.padding
                onMoved: v => root.cfg.decor.padding = Math.round(v)
            }
            Item { implicitHeight: 6 }
        }
        PaletteCard {
            PaletteSlider {
                title: qsTr("Title size"); valueText: root.cfg.decor.titleSize + " pt"
                from: 8; to: 16; stepSize: 1; value: root.cfg.decor.titleSize
                onMoved: v => root.cfg.decor.titleSize = Math.round(v)
            }
            PaletteRow {
                glyph: "format_bold"; title: qsTr("Bold title")
                trailing: "switch"; isOn: root.cfg.decor.titleBold; lit: isOn
                onSwitched: root.cfg.decor.titleBold = !root.cfg.decor.titleBold
            }
            PaletteDivider {}
            PaletteRow {
                glyph: "apps"; title: qsTr("App icon")
                subtitle: qsTr("Left of the title")
                trailing: "switch"; isOn: root.cfg.decor.icon; lit: isOn
                onSwitched: root.cfg.decor.icon = !root.cfg.decor.icon
            }
            PaletteSlider {
                visible: root.cfg.decor.icon
                title: qsTr("Icon size"); valueText: root.cfg.decor.iconSize + " px"
                from: 12; to: 24; stepSize: 1; value: root.cfg.decor.iconSize
                onMoved: v => root.cfg.decor.iconSize = Math.round(v)
            }
            Item { implicitHeight: 6 }
        }
        PaletteCard {
            PaletteRow {
                glyph: "fullscreen"; title: qsTr("Double-click maximizes")
                trailing: "switch"; isOn: root.cfg.decor.doubleClick; lit: isOn
                onSwitched: root.cfg.decor.doubleClick = !root.cfg.decor.doubleClick
            }
            PaletteDivider {}
            ColumnLayout {
                Layout.fillWidth: true; Layout.margins: 10; spacing: 6
                StyledText { text: qsTr("Minimize sends windows to"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer1 }
                SegmentedButtons {
                    Layout.fillWidth: true; showCheck: false; segmentHeight: 30
                    colIndicator: Appearance.colors.colPrimary; colActiveText: Appearance.colors.colOnPrimary
                    currentId: root.cfg.decor.minimizeTo; onSelected: id => root.cfg.decor.minimizeTo = id
                    model: [{ id: "special", label: qsTr("Scratchpad") }, { id: "hide", label: qsTr("Hidden") }]
                }
            }
        }
    }

    // Per-app title bars. Each entry in decor.perApp is { color, alpha, hidden,
    // title }; anything left out stays automatic (Glass._decorJson resolves it).
    // A bare string is the old shade-only form and still reads as { color }.
    function _perApp(cls) {
        const raw = (root.cfg.decor.perApp ?? {})[cls];
        return typeof raw === "string" ? { color: raw } : Object.assign({}, raw ?? {});
    }
    function _setPerApp(cls, key, value) {
        const next = Object.assign({}, root.cfg.decor.perApp ?? {});
        const o = root._perApp(cls);
        if (value === undefined) delete o[key]; else o[key] = value;
        if (Object.keys(o).length === 0) delete next[cls]; else next[cls] = o;
        root.cfg.decor.perApp = next;
    }

    PanelSheet {
        open: root.decorAppsOpen
        title: qsTr("Per-app title bars")
        subtitle: qsTr("Match each app's own look; anything you leave alone stays automatic")
        onClosed: root.decorAppsOpen = false

        Repeater {
            model: Glass._iconClasses.split("\n").filter(c => c.length > 0)
            delegate: PaletteCard {
                id: appCard
                required property string modelData
                readonly property var o: { void root.cfg.decor.perApp; return root._perApp(appCard.modelData) }
                readonly property string colorId: appCard.o.color === undefined ? "auto"
                    : (["auto", "app", "kde", "shell"].includes(appCard.o.color) ? appCard.o.color : "shade")
                readonly property bool customised: Object.keys(appCard.o).length > 0

                RowLayout {
                    Layout.fillWidth: true; Layout.margins: 10; Layout.bottomMargin: 0; spacing: 8
                    Image {
                        readonly property string png: Glass.decorIcons[appCard.modelData] ?? ""
                        visible: png.length > 0
                        source: png.length > 0 ? "file://" + png : ""
                        sourceSize: Qt.size(20, 20)
                        Layout.preferredWidth: 20; Layout.preferredHeight: 20
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: appCard.modelData
                        elide: Text.ElideMiddle
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        visible: appCard.customised
                        text: qsTr("Reset")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colPrimary
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                const next = Object.assign({}, root.cfg.decor.perApp ?? {});
                                delete next[appCard.modelData];
                                root.cfg.decor.perApp = next;
                            }
                        }
                    }
                }
                PaletteRow {
                    glyph: "web_asset"; title: qsTr("Title bar")
                    trailing: "switch"; isOn: appCard.o.hidden !== true; lit: isOn
                    onSwitched: root._setPerApp(appCard.modelData, "hidden", appCard.o.hidden === true ? undefined : true)
                }
                ColumnLayout {
                    visible: appCard.o.hidden !== true
                    Layout.fillWidth: true; Layout.margins: 10; Layout.topMargin: 0; spacing: 6
                    StyledText { text: qsTr("Colour"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer1 }
                    SegmentedButtons {
                        Layout.fillWidth: true; showCheck: false; segmentHeight: 30
                        colIndicator: Appearance.colors.colPrimary; colActiveText: Appearance.colors.colOnPrimary
                        currentId: appCard.colorId
                        onSelected: id => root._setPerApp(appCard.modelData, "color",
                            id === "auto" ? undefined : id === "shade" ? (root.cfg.decor.barRole ?? "container") : id)
                        model: [{ id: "auto", label: qsTr("Auto") }, { id: "app", label: qsTr("App") },
                                { id: "kde", label: qsTr("KDE") }, { id: "shell", label: qsTr("Shell") },
                                { id: "shade", label: qsTr("Shade") }]
                    }
                    SegmentedButtons {
                        visible: appCard.colorId === "shade"
                        Layout.fillWidth: true; showCheck: false; segmentHeight: 28; model: root.roleModel
                        colIndicator: Appearance.colors.colPrimary; colActiveText: Appearance.colors.colOnPrimary
                        currentId: appCard.o.color ?? ""
                        onSelected: id => root._setPerApp(appCard.modelData, "color", id)
                    }
                }
                PaletteSlider {
                    visible: appCard.o.hidden !== true
                    title: qsTr("Opacity")
                    valueText: typeof appCard.o.alpha === "number"
                        ? Math.round(appCard.o.alpha * 100) + " %" : qsTr("Auto")
                    from: 0; to: 100; stepSize: 1
                    value: typeof appCard.o.alpha === "number" ? appCard.o.alpha * 100 : 60
                    onMoved: v => root._setPerApp(appCard.modelData, "alpha", Math.round(v) / 100)
                }
                PaletteRow {
                    visible: appCard.o.hidden !== true
                    glyph: "title"; title: qsTr("Window title")
                    subtitle: appCard.o.title === undefined ? qsTr("Follows the global setting") : ""
                    trailing: "switch"
                    isOn: appCard.o.title === undefined ? root.cfg.decor.title : appCard.o.title
                    lit: isOn
                    onSwitched: root._setPerApp(appCard.modelData, "title", !(appCard.o.title === undefined ? root.cfg.decor.title : appCard.o.title))
                }
                Item { implicitHeight: 4 }
            }
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: qsTr("Lists the apps that are open now. Auto takes the app's own toolbar colour and transparency.")
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
    }
}
