-- Keybinds.
--
-- Two kinds live here:
--
--   hl.dsp.global("quickshell:<name>")  reaches a GlobalShortcut the shell
--       registers. The name must match exactly; the shell declares about 84 of
--       them and this file binds the ones worth a key. The rest are reachable
--       over IPC (`qs -c ii ipc call <target> <fn>`) — `qs -c ii ipc show`
--       lists every one.
--
--   hl.dsp.*                            ordinary Hyprland dispatchers.
--
-- If you add or change a SUPER binding here, add the matching line to
-- super_interrupts.lua as well, or a bare Super tap will still open the
-- launcher when you let go. That file explains why. gen-super-interrupts.sh
-- does it for you.
--
-- The cheatsheet (Super+/) builds itself from `hyprctl binds -j`, so it shows
-- what is REALLY bound and there is no second copy of this file to keep in
-- step. What it cannot see is what a bind does — on a Lua config every one of
-- them reports `dispatcher: "__lua"` with an opaque id — so the description
-- is what it prints. "Section/Label": the part before the slash groups the
-- bind, the rest is the text. A bind with NO description is treated as
-- plumbing and left out, which is how the interrupts stay hidden.

-- ── The launcher: tap Super ─────────────────────────────────────────────
-- Fires on RELEASE, so that holding Super for a combination does not open it.
hl.bind("SUPER + Super_L", hl.dsp.global("quickshell:searchToggleRelease"), { ignore_mods = true, description = "Shell/Search and launch" })
hl.bind("SUPER + Super_R", hl.dsp.global("quickshell:searchToggleRelease"), { ignore_mods = true, description = "Shell/Search and launch" })
hl.bind("CTRL + Super_L", hl.dsp.global("quickshell:searchToggleReleaseInterrupt"))
hl.bind("CTRL + Super_R", hl.dsp.global("quickshell:searchToggleReleaseInterrupt"))
-- Hold Super to label the workspaces.
hl.bind("Super_L", hl.dsp.global("quickshell:workspaceNumber"), { ignore_mods = true, transparent = true })
hl.bind("Super_R", hl.dsp.global("quickshell:workspaceNumber"), { ignore_mods = true, transparent = true })

-- ── The shell ───────────────────────────────────────────────────────────
hl.bind("SUPER + Tab",       hl.dsp.global("quickshell:overviewWorkspacesToggle"), { description = "Shell/Overview" })
hl.bind("SUPER + A",         hl.dsp.global("quickshell:sidebarLeftToggle"),  { description = "Shell/Left sidebar" })
hl.bind("SUPER + N",         hl.dsp.global("quickshell:sidebarRightToggle"), { description = "Shell/Right sidebar" })
hl.bind("SUPER + M",         hl.dsp.global("quickshell:mediaControlsToggle"), { description = "Shell/Media controls" })
hl.bind("SUPER + Slash",     hl.dsp.global("quickshell:cheatsheetToggle"),   { description = "Shell/Keybind cheatsheet" })
hl.bind("SUPER + V",         hl.dsp.global("quickshell:overviewClipboardToggle"), { description = "Shell/Clipboard history" })
hl.bind("SUPER + Period",    hl.dsp.global("quickshell:overviewEmojiToggle"), { description = "Shell/Emoji picker" })
hl.bind("SUPER + Backspace", hl.dsp.global("quickshell:shelfToggle"),        { description = "Shell/Shelf" })
hl.bind("SUPER + J",         hl.dsp.global("quickshell:barToggle"),          { description = "Shell/Toggle the bar" })
hl.bind("SUPER + K",         hl.dsp.global("quickshell:oskToggle"),          { description = "Shell/On-screen keyboard" })
hl.bind("SUPER + G",         hl.dsp.global("quickshell:overlayToggle"),      { description = "Shell/Overlay" })
hl.bind("SUPER + Y",         hl.dsp.global("quickshell:panelFamilyCycle"),   { description = "Shell/Cycle layout" })
hl.bind("CTRL + ALT + Delete", hl.dsp.global("quickshell:sessionToggle"),    { description = "Shell/Session menu" })
hl.bind("CTRL + SUPER + T",  hl.dsp.global("quickshell:wallpaperSelectorToggle"), { description = "Shell/Wallpapers" })
hl.bind("CTRL + SUPER + ALT + T", hl.dsp.global("quickshell:wallpaperSelectorRandom"), { description = "Shell/Random wallpaper" })
hl.bind("SUPER + I",         hl.dsp.exec_cmd("qs -p ~/.config/quickshell/@SHELL_NAME@/settings.qml"), { description = "Shell/Settings" })
hl.bind("SHIFT + SUPER + ALT + Slash", hl.dsp.exec_cmd("qs -p ~/.config/quickshell/@SHELL_NAME@/welcome.qml"), { description = "Shell/Welcome app" })

-- ── Screenshots and recording ───────────────────────────────────────────
hl.bind("SUPER + SHIFT + S", hl.dsp.global("quickshell:regionScreenshot"), { description = "Screen/Screenshot a region" })
hl.bind("SUPER + SHIFT + T", hl.dsp.global("quickshell:regionOcr"),        { description = "Screen/Copy text from screen" })
hl.bind("SUPER + ALT + R",   hl.dsp.global("quickshell:regionRecord"),     { description = "Screen/Record a region" })

-- ── Media ───────────────────────────────────────────────────────────────
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd("playerctl play-pause"), { description = "Media/Play or pause" })
hl.bind("SUPER + SHIFT + N", hl.dsp.global("quickshell:playerSkipNext"), { description = "Media/Next track" })
hl.bind("SUPER + SHIFT + B", hl.dsp.global("quickshell:playerSkipPrev"), { description = "Media/Previous track" })
hl.bind("SUPER + BracketRight", hl.dsp.global("quickshell:playerNext"), { description = "Media/Next player" })
hl.bind("SUPER + BracketLeft",  hl.dsp.global("quickshell:playerPrev"), { description = "Media/Previous player" })

-- ── Hardware keys ───────────────────────────────────────────────────────
-- `locked` so they still work on the lock screen; `repeating` so holding them
-- ramps. The `||` fallbacks keep the keys working when the shell is not up.
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+ -l 1.5"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SOURCE@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("qs -c @SHELL_NAME@ ipc call brightness increment || brightnessctl s 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("qs -c @SHELL_NAME@ ipc call brightness decrement || brightnessctl s 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- ── Windows ─────────────────────────────────────────────────────────────
-- The Lua dispatchers take a table, not positional arguments: it is
-- hl.dsp.focus({ direction = "l" }), never hl.dsp.focus("l"). A positional
-- call is not a syntax error, it just does nothing.
hl.bind("SUPER + Q",         hl.dsp.window.close(),                        { description = "Windows/Close window" })
hl.bind("SUPER + T",         hl.dsp.exec_cmd("foot"),                      { description = "Windows/Terminal" })
hl.bind("SUPER + E",         hl.dsp.exec_cmd("xdg-open ~"),                { description = "Windows/Files" })
hl.bind("SUPER + F",         hl.dsp.window.fullscreen({ mode = "fullscreen" }), { description = "Windows/Fullscreen" })
hl.bind("SUPER + D",         hl.dsp.window.fullscreen({ mode = "maximized" }),  { description = "Windows/Maximize" })
hl.bind("SUPER + SHIFT + F", hl.dsp.window.float({ action = "toggle" }),   { description = "Windows/Float" })
hl.bind("SUPER + P",         hl.dsp.window.pin(),                          { description = "Windows/Pin" })
hl.bind("SUPER + L",         hl.dsp.global("quickshell:lock"),             { description = "Windows/Lock" })

hl.bind("SUPER + Left",  hl.dsp.focus({ direction = "l" }))
hl.bind("SUPER + Right", hl.dsp.focus({ direction = "r" }))
hl.bind("SUPER + Up",    hl.dsp.focus({ direction = "u" }))
hl.bind("SUPER + Down",  hl.dsp.focus({ direction = "d" }))
hl.bind("SUPER + SHIFT + Left",  hl.dsp.window.move({ direction = "l" }))
hl.bind("SUPER + SHIFT + Right", hl.dsp.window.move({ direction = "r" }))
hl.bind("SUPER + SHIFT + Up",    hl.dsp.window.move({ direction = "u" }))
hl.bind("SUPER + SHIFT + Down",  hl.dsp.window.move({ direction = "d" }))

hl.bind("SUPER + Semicolon",  hl.dsp.layout("splitratio -0.1"), { repeating = true })
hl.bind("SUPER + Apostrophe", hl.dsp.layout("splitratio +0.1"), { repeating = true })

-- Drag and resize with the mouse. `hl.bind` with a mouse button, not a
-- separate bindm — the Lua API has no bindm.
hl.bind("SUPER + mouse:272", hl.dsp.window.drag())
hl.bind("SUPER + mouse:273", hl.dsp.window.resize())

-- ── Workspaces ──────────────────────────────────────────────────────────
for i = 1, 10 do
    local key = tostring(i % 10)
    -- Only the first of the ten carries a description. Ten identical rows
    -- would push everything else off the cheatsheet to say one thing.
    local go   = i == 1 and { description = "Workspaces/Go to workspace 1-10" } or nil
    local move = i == 1 and { description = "Workspaces/Move window to workspace 1-10" } or nil
    hl.bind("SUPER + " .. key,         hl.dsp.focus({ workspace = i }), go)
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), move)
end
-- Strings for the relative forms: "+1" is the next workspace, -1 as a NUMBER
-- is workspace 1 counted backwards. They are not interchangeable.
hl.bind("SUPER + Page_Down", hl.dsp.focus({ workspace = "+1" }), { description = "Workspaces/Next workspace" })
hl.bind("SUPER + Page_Up",   hl.dsp.focus({ workspace = -1 }),   { description = "Workspaces/Previous workspace" })
hl.bind("SUPER + Grave",     hl.dsp.workspace.toggle_special(),  { description = "Workspaces/Scratchpad" })
hl.bind("SUPER + SHIFT + Grave", hl.dsp.window.move({ workspace = "special", follow = false }), { description = "Workspaces/Send to the scratchpad" })
