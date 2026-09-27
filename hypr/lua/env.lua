-- Environment.

hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Several of the shell's helper scripts have a venv shebang, and the one that
-- reads your keybinds for the cheatsheet is among them. Without this the
-- cheatsheet opens EMPTY and nothing explains why, so it is not optional.
hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", "~/.local/state/quickshell/.venv")
