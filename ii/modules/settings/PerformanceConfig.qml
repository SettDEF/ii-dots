import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Ordered by cost, not category. The tooltip numbers are what the code does
// at 1366x768 — arithmetic, not benchmarks.
ContentPage {
    id: page
    forceWidth: true

    // The same keys install.sh --low-end writes.
    function applyLowEnd() {
        Config.options.lock.blur.enable = false;
        Config.options.background.effect = "";
        Config.options.background.parallax.enableWorkspace = false;
        Config.options.background.parallax.enableSidebar = false;
        Config.options.appearance.transparency.enable = false;
        Config.options.appearance.extraBackgroundTint = false;
        Config.options.appearance.fakeScreenRounding = 0;
        Config.options.sidebar.keepRightSidebarLoaded = false;
        Config.options.dock.livePreviews = false;
        Config.options.bar.showVisualizer = false;
        Config.options.bar.workspaces.switchFlash = false;
        Config.options.overview.scale = 0.13;
        Config.options.resources.updateInterval = 5000;
        Config.options.resources.historyLength = 30;
        Config.options.search.nonAppResultDelay = 120;
    }

    function applyDefaults() {
        Config.options.lock.blur.enable = true;
        Config.options.background.parallax.enableWorkspace = true;
        Config.options.background.parallax.enableSidebar = true;
        Config.options.appearance.extraBackgroundTint = true;
        Config.options.appearance.fakeScreenRounding = 2;
        Config.options.sidebar.keepRightSidebarLoaded = true;
        Config.options.dock.livePreviews = true;
        Config.options.bar.showVisualizer = true;
        Config.options.bar.workspaces.switchFlash = true;
        Config.options.overview.scale = 0.18;
        Config.options.resources.updateInterval = 3000;
        Config.options.resources.historyLength = 60;
        Config.options.search.nonAppResultDelay = 30;
        // The wallpaper effect is a path; this page cannot guess which.
    }

    ContentSection {
        icon: "speed"
        title: Translation.tr("Presets")

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.bottomMargin: 4
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("These set every switch below at once. Nothing here is one-way — change any of them back individually.")
        }

        ConfigRow {
            uniform: true
            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "battery_saver"
                mainText: Translation.tr("Turn the effects off")
                onClicked: page.applyLowEnd()
                StyledToolTip {
                    text: Translation.tr("For integrated graphics or 4GB of RAM. Keeps every feature; stops the expensive drawing.")
                }
            }
            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "restart_alt"
                mainText: Translation.tr("Back to the defaults")
                onClicked: page.applyDefaults()
                StyledToolTip {
                    text: Translation.tr("Leaves the wallpaper effect alone — this page cannot know which one you picked.")
                }
            }
        }
    }

    ContentSection {
        icon: "blur_on"
        title: Translation.tr("Drawing")

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.bottomMargin: 4
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("Roughly in order of what they cost a weak GPU. The first one dominates the rest put together.")
        }

        ConfigSwitch {
            buttonIcon: "lock"
            text: Translation.tr("Lock screen blur")
            checked: Config.options.lock.blur.enable
            onCheckedChanged: Config.options.lock.blur.enable = checked
            StyledToolTip {
                text: Translation.tr("The most expensive thing the shell draws. A blur radius of 100 means 201 samples per pixel of the whole screen — about 211 million texture fetches a frame at 1366x768.")
            }
        }
        ConfigSpinBox {
            icon: "deblur"
            text: Translation.tr("Blur radius")
            value: Config.options.lock.blur.radius
            from: 4
            to: 100
            stepSize: 4
            enabled: Config.options.lock.blur.enable
            onValueChanged: Config.options.lock.blur.radius = value
            StyledToolTip {
                text: Translation.tr("Cost rises with the radius: samples = radius x 2 + 1. Halving the radius halves the work. 24 still reads as a blur.")
            }
        }
        ConfigSwitch {
            buttonIcon: "landscape"
            text: Translation.tr("Wallpaper parallax")
            checked: Config.options.background.parallax.enableWorkspace
            onCheckedChanged: Config.options.background.parallax.enableWorkspace = checked
            StyledToolTip {
                text: Translation.tr("Rescales the whole wallpaper on every workspace switch.")
            }
        }
        ConfigSwitch {
            buttonIcon: "dock_to_left"
            text: Translation.tr("Parallax when a sidebar opens")
            checked: Config.options.background.parallax.enableSidebar
            onCheckedChanged: Config.options.background.parallax.enableSidebar = checked
        }
        ConfigSwitch {
            buttonIcon: "opacity"
            text: Translation.tr("Transparency")
            checked: Config.options.appearance.transparency.enable
            onCheckedChanged: Config.options.appearance.transparency.enable = checked
            StyledToolTip {
                text: Translation.tr("Forces blended layers the compositor cannot skip redrawing.")
            }
        }
        ConfigSwitch {
            buttonIcon: "gradient"
            text: Translation.tr("Background tint")
            checked: Config.options.appearance.extraBackgroundTint
            onCheckedChanged: Config.options.appearance.extraBackgroundTint = checked
            StyledToolTip {
                text: Translation.tr("Another full-screen blend on top of the wallpaper.")
            }
        }
        ConfigSwitch {
            buttonIcon: "graphic_eq"
            text: Translation.tr("Bar visualizer")
            checked: Config.options.bar.showVisualizer
            onCheckedChanged: Config.options.bar.showVisualizer = checked
            StyledToolTip {
                text: Translation.tr("Runs cava and repaints a spectrum the whole time audio plays.")
            }
        }
        ConfigSwitch {
            buttonIcon: "rounded_corner"
            text: Translation.tr("Fake screen rounding")
            checked: Config.options.appearance.fakeScreenRounding !== 0
            onCheckedChanged: Config.options.appearance.fakeScreenRounding = checked ? 2 : 0
            StyledToolTip {
                text: Translation.tr("A masked overlay per screen, composited every frame. Off, the corners are square.")
            }
        }
        ConfigSwitch {
            buttonIcon: "animation"
            text: Translation.tr("Workspace switch flash")
            checked: Config.options.bar.workspaces.switchFlash
            onCheckedChanged: Config.options.bar.workspaces.switchFlash = checked
        }
    }

    ContentSection {
        icon: "memory"
        title: Translation.tr("Memory")

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.bottomMargin: 4
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("The shell's resident size is roughly one graphics context per surface it has mapped, so the cost here is in how many stay alive rather than in what they draw.")
        }

        ConfigSwitch {
            buttonIcon: "dock_to_right"
            text: Translation.tr("Keep the right sidebar loaded")
            checked: Config.options.sidebar.keepRightSidebarLoaded
            onCheckedChanged: Config.options.sidebar.keepRightSidebarLoaded = checked
            StyledToolTip {
                text: Translation.tr("On, it opens instantly and holds a surface the whole session. Off, it costs a moment on the first open and nothing in between.")
            }
        }
        ConfigSwitch {
            buttonIcon: "preview"
            text: Translation.tr("Live window previews in the dock")
            checked: Config.options.dock.livePreviews
            onCheckedChanged: Config.options.dock.livePreviews = checked
            StyledToolTip {
                text: Translation.tr("On, every previewed window is copied off the GPU every frame the popup is up. Off, the preview is a single frame grabbed when the hover starts.")
            }
        }
        ContentSubsection {
            title: Translation.tr("Dock preview animation")
            tooltip: Translation.tr("All four are transforms on a surface allocated once, so none of them resizes the window while it opens.")
            ConfigSelectionArray {
                currentValue: Config.options.dock.previewAnimation
                onSelected: newValue => Config.options.dock.previewAnimation = newValue
                options: [
                    { value: "grow", displayName: Translation.tr("Grow"),  icon: "zoom_out_map" },
                    { value: "rise", displayName: Translation.tr("Rise"),  icon: "arrow_upward" },
                    { value: "fade", displayName: Translation.tr("Fade"),  icon: "opacity" },
                    { value: "none", displayName: Translation.tr("None"),  icon: "block" }
                ]
            }
        }

        ConfigSpinBox {
            icon: "grid_view"
            text: Translation.tr("Overview thumbnail size (%)")
            value: Math.round(Config.options.overview.scale * 100)
            from: 8
            to: 30
            stepSize: 1
            onValueChanged: Config.options.overview.scale = value / 100
            StyledToolTip {
                text: Translation.tr("Each tile is a live copy of a window. Smaller tiles copy fewer pixels.")
            }
        }
    }

    ContentSection {
        icon: "timer"
        title: Translation.tr("Polling")

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.bottomMargin: 4
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("What the shell does when nothing is happening. Cheap on a fast machine, and the thing you notice on a slow one.")
        }

        ConfigSpinBox {
            icon: "monitor_heart"
            text: Translation.tr("Resource update interval (ms)")
            value: Config.options.resources.updateInterval
            from: 1000
            to: 10000
            stepSize: 500
            onValueChanged: Config.options.resources.updateInterval = value
            StyledToolTip {
                text: Translation.tr("How often CPU, memory and swap are read for the bar and the widgets.")
            }
        }
        ConfigSpinBox {
            icon: "ssid_chart"
            text: Translation.tr("Resource history length")
            value: Config.options.resources.historyLength
            from: 10
            to: 120
            stepSize: 10
            onValueChanged: Config.options.resources.historyLength = value
            StyledToolTip {
                text: Translation.tr("How many samples the graphs keep, and therefore how many points they redraw.")
            }
        }
        ConfigSpinBox {
            icon: "search"
            text: Translation.tr("Search result delay (ms)")
            value: Config.options.search.nonAppResultDelay
            from: 0
            to: 400
            stepSize: 10
            onValueChanged: Config.options.search.nonAppResultDelay = value
            StyledToolTip {
                text: Translation.tr("How long the launcher waits after a keystroke before running the slower searches. Higher means less work while you are still typing.")
            }
        }
    }
}
