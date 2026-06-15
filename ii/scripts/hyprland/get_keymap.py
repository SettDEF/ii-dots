#!/usr/bin/env python3
"""
get_keymap.py — resolve evdev/X keycodes to key labels for an XKB layout.

Compiles the requested layout with `xkbcli compile-keymap`, then joins the
`xkb_keycodes` and `xkb_symbols` sections into a { keycode : keysym } map.
Output is JSON on stdout. Hyprland's `bind = ..., code:NN` uses these same
keycode numbers, so the cheatsheet can turn `code:24` into a real, layout-
correct key ("Q" on us, "A" on azerty, ...).

Usage:  get_keymap.py --layout de --variant ''
"""
import argparse
import json
import re
import subprocess
import sys

# `<AE01>  = 10;` in xkb_keycodes (skip `alias ... = <NAME>;`).
KEYCODE_RE = re.compile(r"<(\w+)>\s*=\s*(\d+)\s*;")
# `key <AE01> { [ 1, exclam ] };` — grab the first (level-1) keysym.
SYMBOL_RE = re.compile(r"key\s+<(\w+)>\s*\{[^\[]*\[\s*([^,\]]+)")


def compile_keymap(layout: str, variant: str, model: str, options: str) -> str:
    cmd = ["xkbcli", "compile-keymap", "--layout", layout]
    if variant:
        cmd += ["--variant", variant]
    if model:
        cmd += ["--model", model]
    if options:
        cmd += ["--options", options]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout


def parse(keymap: str) -> dict:
    name_to_code: dict = {}
    name_to_sym: dict = {}
    section = None
    for raw in keymap.splitlines():
        line = raw.strip()
        if line.startswith("xkb_keycodes"):
            section = "keycodes"
            continue
        if line.startswith("xkb_symbols"):
            section = "symbols"
            continue
        if line.startswith("xkb_"):
            section = "other"
            continue
        if section == "keycodes" and not line.startswith("alias"):
            m = KEYCODE_RE.search(line)
            if m:
                name_to_code[m.group(1)] = int(m.group(2))
        elif section == "symbols":
            m = SYMBOL_RE.search(line)
            if m:
                name_to_sym[m.group(1)] = m.group(2).strip()

    code_to_key: dict = {}
    for name, code in name_to_code.items():
        sym = name_to_sym.get(name)
        if sym:
            code_to_key[str(code)] = sym
    return code_to_key


def main() -> None:
    ap = argparse.ArgumentParser(description="XKB keycode -> key label resolver")
    ap.add_argument("--layout", default="us")
    ap.add_argument("--variant", default="")
    ap.add_argument("--model", default="")
    ap.add_argument("--options", default="")
    args = ap.parse_args()

    try:
        keymap = compile_keymap(args.layout, args.variant, args.model, args.options)
        if not keymap.strip():
            print(json.dumps({"ok": False, "error": "empty keymap"}))
            return
        print(json.dumps({
            "ok": True,
            "layout": args.layout,
            "variant": args.variant,
            "codeToKey": parse(keymap),
        }))
    except FileNotFoundError:
        print(json.dumps({"ok": False, "error": "xkbcli not found"}))
    except Exception as e:  # noqa: BLE001 — never crash the caller
        print(json.dumps({"ok": False, "error": str(e)}))


if __name__ == "__main__":
    main()
