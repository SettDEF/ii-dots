//! zash (the terminal): the "Keys:" part of `zash --help`, two binds per line
//! ("Ctrl+Shift+C / V      copy / paste             Ctrl+Shift+F    search").

use crate::model::{push, App, Bind};

/// "Ctrl+Shift+T / W" → (["Ctrl", "Shift"], "T / W")
fn split(k: &str) -> (Vec<String>, String) {
    let (keys, alt) = k.split_once(" / ").map(|(a, b)| (a, Some(b))).unwrap_or((k, None));
    let mut parts: Vec<String> = keys.split('+').map(String::from).collect();
    let mut key = parts.pop().unwrap_or_default();
    if let Some(b) = alt { key = format!("{key} / {b}"); }
    (parts, key)
}

pub fn extract() -> Option<App> {
    let out = std::process::Command::new("zash").arg("--help").output().ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    let mut sections = Vec::new();
    let mut inside = false;
    for line in text.lines() {
        if line.starts_with("Keys:") { inside = true; continue; }
        if !inside { continue; }
        if line.trim().is_empty() { break; }
        // columns are separated by runs of 2+ spaces: key, what, key, what
        let cols: Vec<&str> = line.split("  ").map(str::trim).filter(|c| !c.is_empty()).collect();
        for pair in cols.chunks(2) {
            if let [k, what] = pair {
                let (mods, key) = split(k);
                push(&mut sections, "Terminal", Bind { mods, key, comment: what.to_string() });
            }
        }
    }
    (!sections.is_empty()).then(|| App { id: "zash", name: "zash", icon: "terminal", note: String::new(), sections })
}
