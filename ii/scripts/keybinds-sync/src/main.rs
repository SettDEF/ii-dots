//! keybinds-sync — the keybinds of your apps, for the shell's cheatsheet.
//!
//! One extractor per app, each in its own file (tmux.rs, wezterm.rs, …).
//! Every extractor asks the app ITSELF what is bound — not a parse of its
//! config — so plugins, defaults and includes are all accounted for, and the
//! list cannot drift from what the keys really do. An app that is not
//! installed is skipped.
//!
//! Writes $XDG_STATE_HOME/quickshell/keybinds/apps.json:
//!   { "updated": <unix s>, "apps": [ { id, name, icon, note, sections: [ { name, keybinds: [ { mods, key, comment } ] } ] } ] }
//! The shell's AppKeybinds service watches that file.
//!
//! To add an app: a new file with `pub fn extract() -> Option<App>`, then one
//! line in EXTRACTORS below.
//!
//!   keybinds-sync            write the file
//!   keybinds-sync --print    print the JSON instead

mod model;
mod nvim;
mod reel;
mod tmux;
mod wezterm;
mod zsh;

use model::App;
use std::io::Write;

const EXTRACTORS: &[fn() -> Option<App>] = &[tmux::extract, wezterm::extract, nvim::extract, zsh::extract, reel::extract];

fn main() {
    let apps: Vec<App> = EXTRACTORS.iter().filter_map(|f| f()).filter(|a| !a.sections.is_empty()).collect();
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    let json = serde_json::json!({ "updated": now, "apps": apps });
    let text = serde_json::to_string_pretty(&json).expect("serialise");

    if std::env::args().any(|a| a == "--print") {
        println!("{text}");
        return;
    }
    let state = std::env::var("XDG_STATE_HOME").unwrap_or_else(|_| format!("{}/.local/state", std::env::var("HOME").unwrap_or_default()));
    let dir = std::path::Path::new(&state).join("quickshell/keybinds");
    std::fs::create_dir_all(&dir).expect("state dir");
    // temp + rename: the shell watches the file and must never read half of it
    let tmp = dir.join("apps.json.tmp");
    std::fs::File::create(&tmp).and_then(|mut f| f.write_all(text.as_bytes())).expect("write");
    std::fs::rename(&tmp, dir.join("apps.json")).expect("rename");
    let n: usize = apps.iter().map(|a| a.sections.iter().map(|s| s.keybinds.len()).sum::<usize>()).sum();
    eprintln!("keybinds-sync: {} apps, {} binds", apps.len(), n);
}
