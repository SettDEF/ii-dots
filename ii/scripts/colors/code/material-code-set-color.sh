#!/usr/bin/env python3
# Updates VSCode settings.json dynamically with the new material color palette when the wallpaper changes.

import os
import sys
import json

log_file = '/tmp/vscode-theme-apply.log'

def log(msg):
    with open(log_file, 'a') as lf:
        lf.write(f"[INFO] {msg}\n")

log("Starting VSCode theme color set script...")

colors_file = os.path.expanduser('~/.local/state/quickshell/user/generated/colors.json')
log(f"Checking colors file path: {colors_file}")
if not os.path.exists(colors_file):
    log(f"colors_file does not exist, checking cache...")
    colors_file = os.path.expanduser('~/.cache/quickshell/user/generated/colors.json')
    log(f"Checking cache path: {colors_file}")

if not os.path.exists(colors_file):
    log("No colors file found. Exiting.")
    sys.exit(0)

try:
    with open(colors_file, 'r') as f:
        colors_data = json.load(f)
    new_color = colors_data.get('primary', '').strip()
    log(f"Read primary color: {new_color}")
except Exception as e:
    log(f"Exception reading colors file: {e}")
    sys.exit(1)

if not new_color:
    log("Primary color is empty. Exiting.")
    sys.exit(0)

settings_paths = [
    os.path.expanduser('~/.config/Code/User/settings.json'),
    os.path.expanduser('~/.config/VSCodium/User/settings.json'),
    os.path.expanduser('~/.config/Code - OSS/User/settings.json'),
    os.path.expanduser('~/.config/Code - Insiders/User/settings.json'),
    os.path.expanduser('~/.config/Cursor/User/settings.json'),
]

for path in settings_paths:
    log(f"Checking VSCode settings path: {path}")
    if os.path.exists(path):
        log(f"VSCode settings path exists: {path}")
        # Ensure parent directory exists (just in case)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        
        try:
            with open(path, 'r') as f:
                data = json.load(f)
            log(f"Successfully loaded settings JSON from {path}")
        except Exception as e:
            log(f"Error reading settings JSON from {path}: {e}")
            data = {}
        
        # Initialize the colors dict if not present
        if 'material-code.colors' not in data or not isinstance(data['material-code.colors'], dict):
            data['material-code.colors'] = {}
            
        data['material-code.colors']['primary'] = new_color
        
        # Clean up deprecated key
        data.pop('material-code.primaryColor', None)
        
        try:
            with open(path, 'w') as f:
                json.dump(data, f, indent=4)
            log(f"Successfully wrote primary color {new_color} to {path}")
        except Exception as e:
            log(f"Error writing settings JSON to {path}: {e}")
            pass

