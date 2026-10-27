//! reel (the video player): its action table, with the keys you changed in
//! reel's Settings applied — the same "the override, else the default" rule
//! reel itself uses.
//!
//!   defaults  the `actions` table in reel/Settings.qml
//!   yours     ~/.config/reel/settings.json  "keys": { "<action id>": ["Key", …] }

use crate::model::{push, App, Bind, Section};

const SOURCE: &str = "/mnt/storage/dev/projects/reel/reel/Settings.qml";

/// "Shift+Left" → (["Shift"], "Left")
fn split(k: &str) -> (Vec<String>, String) {
    let mut parts: Vec<String> = k.split('+').map(String::from).collect();
    let key = parts.pop().unwrap_or_default();
    (parts, key)
}

pub fn extract() -> Option<App> {
    let qml = std::fs::read_to_string(std::env::var("REEL_SETTINGS_QML").unwrap_or_else(|_| SOURCE.into())).ok()?;
    let home = std::env::var("HOME").unwrap_or_default();
    let cfg = std::env::var("XDG_CONFIG_HOME").unwrap_or_else(|_| format!("{home}/.config"));
    let user: serde_json::Value = std::fs::read_to_string(format!("{cfg}/reel/settings.json"))
        .ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or(serde_json::Value::Null);

    let mut sections: Vec<Section> = Vec::new();
    let mut order: Vec<String> = Vec::new();
    // one action per line: { "id": "toggle", "group": "Playback", "label": "Play / pause", "keys": ["Space", "K"] },
    for line in qml.lines() {
        let l = line.trim();
        if !l.starts_with("{ \"id\":") { continue; }
        let Ok(a) = serde_json::from_str::<serde_json::Value>(l.trim_end_matches(',')) else { continue };
        let id = a["id"].as_str().unwrap_or("");
        let group = a["group"].as_str().unwrap_or("Other").to_string();
        let label = a["label"].as_str().unwrap_or(id).to_string();
        let keys = user["keys"][id].as_array().or(a["keys"].as_array()).cloned().unwrap_or_default();
        if !order.contains(&group) { order.push(group.clone()); }
        for k in keys.iter().filter_map(|k| k.as_str()) {
            let (mods, key) = split(k);
            push(&mut sections, &group, Bind { mods, key, comment: label.clone() });
        }
    }
    let ord: Vec<&str> = order.iter().map(String::as_str).collect();
    Some(App::new("reel", "reel", "movie", "Click the video for these to work".into(), sections, &ord))
}
