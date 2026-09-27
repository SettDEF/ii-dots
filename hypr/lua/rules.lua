-- Window and layer rules.

-- The shell draws its own rounded screen corners over the top; without this
-- the compositor's corner and the shell's corner are both visible, slightly
-- apart, which reads as a rendering bug.
hl.layerrule("noanim", "quickshell:screenCorners")
hl.layerrule("blur", "quickshell:bar")
hl.layerrule("blur", "quickshell:dock")
hl.layerrule("ignorezero", "quickshell:bar")
hl.layerrule("ignorezero", "quickshell:dock")

hl.windowrule("float", "class:^(org.kde.polkit-kde-authentication-agent-1)$")
hl.windowrule("float", "class:^(qs)$")
hl.windowrule("size 1100 750", "class:^(qs)$, title:^(illogical-impulse Settings)$")
hl.windowrule("center", "class:^(qs)$")
hl.windowrule("suppressevent maximize", "class:.*")
-- XWayland windows that ask to be 0x0 make Hyprland pick something arbitrary.
hl.windowrule("nofocus", "class:^$, title:^$, xwayland:1, floating:1, fullscreen:0, pinned:0")
