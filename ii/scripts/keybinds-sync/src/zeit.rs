//! zeit (the multiplexer): `zeit list-keys`, the binds it really has (init.lua, else tmux.conf),
//! in its own sections: after the prefix, without it, in copy mode.

use crate::model::{push, App, Bind, Section};

/// "M-S-c" → (["Alt", "Shift"], "c"); "C-Space" → (["Ctrl"], "Space")
fn split(k: &str) -> (Vec<String>, String) {
    let mut mods = Vec::new();
    let mut rest = k;
    loop {
        let m = match rest.get(..2) {
            Some("C-") => "Ctrl",
            Some("M-") => "Alt",
            Some("S-") => "Shift",
            _ => break,
        };
        // a lone "C-" or "-" is a key, not a modifier
        if rest.len() <= 2 { break; }
        mods.push(m.to_string());
        rest = &rest[2..];
    }
    (mods, rest.to_string())
}

pub fn extract() -> Option<App> {
    let out = std::process::Command::new("zeit").arg("list-keys").output().ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    let mut sections: Vec<Section> = Vec::new();
    let mut section = String::new();
    let mut prefix = false;
    let mut note = String::new();
    for line in text.lines() {
        if line.trim().is_empty() { continue; }
        if !line.starts_with("  ") {
            // a heading: "After the prefix (C-Space)", "Without the prefix", "In copy mode", or the footer
            if line.contains(" · ") { continue; }
            prefix = line.starts_with("After the prefix");
            if let (true, Some(p)) = (prefix, line.split_once('(')) {
                note = format!("Prefix = {}", p.1.trim_end_matches(')'));
            }
            section = line.split(" (").next().unwrap_or(line).to_string();
            continue;
        }
        let l = line.trim_start();
        let Some((key, cmd)) = l.split_once(char::is_whitespace) else { continue };
        let (mut mods, key) = split(key);
        if prefix { mods.insert(0, "Prefix".into()); }
        let cmd = cmd.trim();
        // long chains (new-window … \; send-keys …) shortened to their first verb and its target
        let comment = if cmd.chars().count() > 70 { format!("{}…", cmd.chars().take(68).collect::<String>()) } else { cmd.to_string() };
        push(&mut sections, &section, Bind { mods, key, comment });
    }
    (!sections.is_empty()).then(|| App { id: "zeit", name: "zeit", icon: "view_quilt", note, sections })
}
