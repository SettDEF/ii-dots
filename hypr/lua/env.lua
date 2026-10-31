-- Environment.

hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Several of the shell's helper scripts have a venv shebang, and the one that
-- reads your keybinds for the cheatsheet is among them. Without this the
-- cheatsheet opens EMPTY and nothing explains why, so it is not optional.
hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", "~/.local/state/quickshell/.venv")

-- quarry (install.sh installs and starts quarryd): the shell reaches it only when this names its
-- socket (services/Quarry.qml). Without it the wallpaper hub's online tabs never connect.
hl.env("QUARRY_SOCK", (os.getenv("XDG_RUNTIME_DIR") or ("/run/user/" .. (os.getenv("UID") or "1000"))) .. "/quarry/sock")
