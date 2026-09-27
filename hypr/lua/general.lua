-- Look and feel.

hl.config({
    general = {
        gaps_in = 4,
        -- 5 is NOT a taste decision. ii/modules/common/Appearance.qml:434 hard
        -- codes `hyprlandGapsOut: 5` and the bar, the dock and every panel
        -- position themselves against it. Any other value and the rounded
        -- corners where the bar meets the screen edge stop lining up.
        gaps_out = 5,
        border_size = 1,
        col = {
            active_border = "rgba(0DB7D455)",
            inactive_border = "rgba(31313600)",
        },
        resize_on_border = true,
        allow_tearing = true,
    },
})

hl.config({
    decoration = {
        rounding = 18,
        rounding_power = 2,
        dim_inactive = true,
        dim_strength = 0.05,
        -- Blur is the first thing to turn off on integrated graphics. The
        -- shell's own effects have a preset for this in Settings -> Performance;
        -- this is the compositor's half of the same decision.
        blur = {
            enabled = true,
            size = 8,
            passes = 2,
            ignore_opacity = true,
            new_optimizations = true,
        },
        shadow = { enabled = false },
    },
})

hl.config({
    animations = { enabled = true },
    input = {
        kb_layout = "us",
        follow_mouse = 1,
        touchpad = { natural_scroll = true, disable_while_typing = true },
    },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        focus_on_activate = true,
        -- No vfr here: Hyprland 0.55 removed misc:vfr and made it always on.
        -- It survives as debug:vfr, which is not where a default belongs.
    },
    dwindle = { preserve_split = true },
    xwayland = { force_zero_scaling = true },
})

-- Named curves the shell's own animation timings are matched to.
hl.curve("expressiveDefaultSpatial", { type = "bezier", points = { {0.38, 1.21}, {0.22, 1.00} } })
hl.curve("emphasizedDecel", { type = "bezier", points = { {0.05, 0.7}, {0.1, 1} } })
hl.curve("emphasizedAccel", { type = "bezier", points = { {0.3, 0}, {0.8, 0.15} } })
hl.curve("standardDecel", { type = "bezier", points = { {0, 0}, {0, 1} } })
hl.curve("menu_decel", { type = "bezier", points = { {0.1, 1}, {0, 1} } })
hl.curve("menu_accel", { type = "bezier", points = { {0.52, 0.03}, {0.72, 0.08} } })
hl.curve("stall", { type = "bezier", points = { {1, -0.1}, {0.7, 0.85} } })

-- The name goes in the table as `leaf`, and the curve key is `bezier`. A
-- positional name or a `curve` key is rejected, and every leaf below is a real
-- one: there is no "windows" or "fade", only the In/Out/Move halves.
hl.animation({ leaf = "windowsIn",           enabled = true, speed = 3,   bezier = "emphasizedDecel", style = "popin 80%" })
hl.animation({ leaf = "windowsOut",          enabled = true, speed = 2,   bezier = "emphasizedDecel", style = "popin 90%" })
hl.animation({ leaf = "windowsMove",         enabled = true, speed = 3,   bezier = "emphasizedDecel", style = "slide" })
hl.animation({ leaf = "fadeIn",              enabled = true, speed = 3,   bezier = "emphasizedDecel" })
hl.animation({ leaf = "fadeOut",             enabled = true, speed = 2,   bezier = "emphasizedDecel" })
hl.animation({ leaf = "border",              enabled = true, speed = 10,  bezier = "emphasizedDecel" })
hl.animation({ leaf = "layersIn",            enabled = true, speed = 2.7, bezier = "emphasizedDecel", style = "popin 93%" })
hl.animation({ leaf = "layersOut",           enabled = true, speed = 2.4, bezier = "menu_accel", style = "popin 94%" })
hl.animation({ leaf = "fadeLayersIn",        enabled = true, speed = 0.5, bezier = "menu_decel" })
hl.animation({ leaf = "fadeLayersOut",       enabled = true, speed = 2.7, bezier = "stall" })
hl.animation({ leaf = "workspaces",          enabled = true, speed = 7,   bezier = "menu_decel", style = "slide" })
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = 2.8, bezier = "emphasizedDecel", style = "slidevert" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 1.2, bezier = "emphasizedAccel", style = "slidevert" })
hl.animation({ leaf = "zoomFactor",          enabled = true, speed = 3,   bezier = "standardDecel" })

-- Three and four finger gestures, including the two the shell answers.
hl.gesture({ fingers = 3, direction = "swipe", action = "move" })
hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 4, direction = "up",
    action = function() hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesToggle")) end })
hl.gesture({ fingers = 4, direction = "down",
    action = function() hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesClose")) end })
