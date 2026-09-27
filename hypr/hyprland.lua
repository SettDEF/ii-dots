-- Hyprland configuration for the `ii` quickshell config.
--
-- Lua rather than hyprlang, and not by preference: the shell writes settings
-- back to Hyprland through `hyprctl eval 'hl.config{...}'` because
-- `hyprctl keyword` answers `unknown request` once a Lua config is loaded
-- (see ii/services/HyprDispatch.qml). On a hyprlang config the shell starts
-- and looks right, and then the shader picker, the monitor editor, the
-- keyboard settings, game mode, touchpad acceleration and layout switching
-- all silently do nothing. So: Lua, and Hyprland 0.56 or newer.
--
-- Everything here is meant to be edited. If you would rather keep your
-- changes separate, put them in lua/local.lua — it is loaded last, so it
-- wins, and nothing in this repo will ever overwrite it.

-- exec-once equivalent.
--
-- `hl.on("hyprland.start")` only fires on the compositor's first frame, so
-- anything loaded later — a reload, or a config written after the session
-- began — would never start. Running at parse time always works, and the
-- pgrep guard is what keeps a reload from starting second copies of
-- everything.
function autostart(guard, cmd, exact)
    -- `pgrep -x` by preference: matching whole command lines with -f also
    -- matches any unrelated process that merely MENTIONS the command — including
    -- the shell running the check itself — and then the program never starts.
    -- Where -f cannot be avoided, [b]racket the first character so the pattern
    -- cannot match its own `sh -c`.
    local check
    if exact then
        check = "pgrep -x " .. guard
    else
        check = "pgrep -f \"[" .. guard:sub(1, 1) .. "]" .. guard:sub(2) .. "\""
    end
    hl.exec_cmd(check .. " >/dev/null 2>&1 || { " .. cmd .. " ; } &")
end

require("lua.env")
require("lua.general")
require("lua.rules")
require("lua.keybinds")
require("lua.super_interrupts")
require("lua.monitors")
require("lua.execs")

-- Written BY the shell, not by you:
--   shellOverrides/main.lua      keyboard layout picked in the settings app
--   shellOverrides/keyboard.lua  key repeat rate and delay
-- They do not exist until the first time you change one of those, hence
-- pcall — a missing file here is the normal state, not an error.
pcall(require, "lua.shellOverrides.main")
pcall(require, "lua.shellOverrides.keyboard")

-- Your own overrides, loaded last so they beat everything above.
pcall(require, "lua.local")
