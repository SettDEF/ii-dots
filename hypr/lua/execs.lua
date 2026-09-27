-- What starts with the session.

-- The shell itself. Everything else here exists so that it has something to
-- talk to.
autostart("qs", "qs -c @SHELL_NAME@", true)

autostart("gnome-keyring-d", "gnome-keyring-daemon --start --components=secrets", true)
autostart("polkit-gnome-au", "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1", true)
autostart("hypridle", "hypridle", true)

-- Portals need the session's environment or file pickers and screen sharing
-- open with no permissions and no explanation.
hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP &")
