-- Monitors.
--
-- "preferred / auto / 1" is the answer that works on an unknown machine. The
-- shell's display settings write their own monitor lines through
-- `hyprctl eval`, so anything you set there at runtime wins over this.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "1" })
