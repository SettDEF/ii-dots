//! zett (the editor): `zett keys MODE`, its mappings as it has them (defaults + ~/.config/zett),
//! one line each: "<A-,>            Move buffer left".

use crate::model::{push, App, Bind, Section};

const MODES: &[(&str, &str)] = &[("n", "Normal"), ("i", "Insert"), ("v", "Visual")];

/// "<A-,>" → (["Alt"], ","); "<leader>ff" → (["Leader"], "ff"); "<C-S-p>" → (["Ctrl", "Shift"], "p")
fn split(k: &str) -> (Vec<String>, String) {
    let lower = k.to_lowercase();
    if lower.starts_with("<leader>") {
        return (vec!["Leader".into()], k[8..].to_string());
    }
    let Some(inner) = k.strip_prefix('<').and_then(|s| s.strip_suffix('>')) else { return (vec![], k.to_string()) };
    let mut parts: Vec<&str> = inner.split('-').collect();
    // "<A-->" ends in an empty part: the key is "-"
    let key = match parts.pop() { Some("") => "-".to_string(), Some(p) => p.to_string(), None => String::new() };
    let mods = parts
        .iter()
        .filter_map(|m| match m.to_ascii_uppercase().as_str() {
            "C" => Some("Ctrl"),
            "A" | "M" => Some("Alt"),
            "S" => Some("Shift"),
            "D" => Some("Super"),
            _ => None,
        })
        .map(String::from)
        .collect();
    (mods, key)
}

pub fn extract() -> Option<App> {
    let mut sections: Vec<Section> = Vec::new();
    for (mode, name) in MODES {
        let Ok(out) = std::process::Command::new("zett").args(["keys", mode]).output() else { continue };
        for line in String::from_utf8_lossy(&out.stdout).lines() {
            // key, then 2+ spaces, then what it does
            let Some((key, what)) = line.split_once("  ") else { continue };
            let (key, what) = (key.trim(), what.trim());
            if key.is_empty() || what.is_empty() { continue; }
            let (mods, key) = split(key);
            push(&mut sections, name, Bind { mods, key, comment: what.to_string() });
        }
    }
    (!sections.is_empty()).then(|| App { id: "zett", name: "zett", icon: "edit_note", note: "Leader = Space".into(), sections })
}
