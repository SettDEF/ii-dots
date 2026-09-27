-- Window and layer rules.
--
-- hl.layer_rule / hl.window_rule, each taking one table: a name, a `match`
-- table of patterns, and the rule itself as a key. There is no hl.layerrule
-- taking a rule string and a selector -- that shape does not exist.

-- The shell draws its own rounded screen corners over the top; without this
-- the compositor's corner and the shell's corner are both visible, slightly
-- apart, which reads as a rendering bug.
hl.layer_rule({
    name  = "shell-corners-noanim",
    match = { namespace = "quickshell:screenCorners" },
    no_anim = true,
})

-- The bar and dock are translucent surfaces over the wallpaper.
hl.layer_rule({
    name  = "shell-bar-blur",
    match = { namespace = "quickshell:bar" },
    blur = true,
    -- ignore_alpha 0, not "ignorezero": fully transparent pixels are excluded
    -- from the blur so the gaps between islands do not smear.
    ignore_alpha = 0,
})
hl.layer_rule({
    name  = "shell-dock-blur",
    match = { namespace = "quickshell:dock" },
    blur = true,
    ignore_alpha = 0,
})

hl.window_rule({
    name  = "polkit-float",
    match = { class = "^(org.kde.polkit-kde-authentication-agent-1)$" },
    float = true,
})

-- The shell's own windows: settings, welcome, dialogs.
hl.window_rule({
    name  = "shell-windows-float",
    match = { class = "^(qs)$" },
    float = true,
})
hl.window_rule({
    name  = "shell-windows-center",
    match = { class = "^(qs)$" },
    center = true,
})
hl.window_rule({
    name  = "shell-settings-size",
    match = { class = "^(qs)$", title = "^(illogical-impulse Settings)$" },
    size = "1100 750",
})

-- XWayland windows that ask to be 0x0 make Hyprland pick something arbitrary.
hl.window_rule({
    name  = "xwayland-zero-size-nofocus",
    match = { class = "^$", title = "^$", xwayland = true, floating = true },
    no_initial_focus = true,
})
