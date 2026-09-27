#!/usr/bin/env bash
# Give keyboard focus back to the window under the cursor.
#
# The shell runs this 500ms after every (re)load (ii/shell.qml:80). Creating
# and destroying layer surfaces can leave Hyprland with no focused window, and
# then typing goes nowhere until you click something — which looks like the
# shell has hung.
hyprctl dispatch focuswindow "address:$(hyprctl activewindow -j | jq -r '.address // empty')" >/dev/null 2>&1 \
    || hyprctl dispatch cyclenext >/dev/null 2>&1
