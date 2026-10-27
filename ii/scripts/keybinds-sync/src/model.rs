//! What every extractor produces, and what the cheatsheet reads.

use serde::Serialize;

#[derive(Debug, Serialize, Clone)]
pub struct Bind {
    /// Modifiers in reading order ("Prefix", "Ctrl", "Alt", "Shift", "Super").
    pub mods: Vec<String>,
    pub key: String,
    /// What it does, in words.
    pub comment: String,
}

#[derive(Debug, Serialize, Default)]
pub struct Section {
    pub name: String,
    pub keybinds: Vec<Bind>,
}

#[derive(Debug, Serialize)]
pub struct App {
    pub id: &'static str,
    pub name: &'static str,
    /// Material symbol for the cheatsheet's sub-category chip.
    pub icon: &'static str,
    /// A line shown above the app's binds, e.g. "Prefix = Ctrl+Space".
    pub note: String,
    pub sections: Vec<Section>,
}

impl App {
    /// Sections in a fixed order, empty ones dropped.
    pub fn new(id: &'static str, name: &'static str, icon: &'static str, note: String, mut sections: Vec<Section>, order: &[&str]) -> Self {
        for s in &mut sections {
            s.keybinds = collapse_digit_runs(std::mem::take(&mut s.keybinds));
        }
        sections.retain(|s| !s.keybinds.is_empty());
        sections.sort_by_key(|s| order.iter().position(|o| *o == s.name).unwrap_or(order.len()));
        App { id, name, icon, note, sections }
    }
}

/// Add a bind to the named section, creating it in order of first use.
pub fn push(sections: &mut Vec<Section>, section: &str, bind: Bind) {
    if let Some(s) = sections.iter_mut().find(|s| s.name == section) {
        s.keybinds.push(bind);
    } else {
        sections.push(Section { name: section.to_string(), keybinds: vec![bind] });
    }
}

/// "split-window -h" → "Split window -h"; "toggle-tab-bar" → "Toggle tab bar".
pub fn humanize(s: &str) -> String {
    let t = s.trim().replace(['-', '_'], " ");
    let mut c = t.chars();
    match c.next() {
        Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
        None => String::new(),
    }
}

pub fn run(cmd: &str, args: &[&str]) -> Option<String> {
    let out = std::process::Command::new(cmd).args(args).output().ok()?;
    out.status.success().then(|| String::from_utf8_lossy(&out.stdout).into_owned())
}

/// "Select window 0" … "Select window 9" (keys 0–9, same modifiers) become one
/// row: key "0–9", comment "Select window N". Ten rows of the same thing are
/// what made the long lists hard to scan.
pub fn collapse_digit_runs(binds: Vec<Bind>) -> Vec<Bind> {
    use std::collections::HashMap;
    // pattern → (mods, comment with N, digits seen, first index)
    let mut groups: HashMap<(String, String), (Vec<u32>, usize)> = HashMap::new();
    for (i, b) in binds.iter().enumerate() {
        let Some(d) = digit_key(&b.key) else { continue };
        let Some(pattern) = with_n(&b.comment, d) else { continue };
        let e = groups.entry((b.mods.join("+"), pattern)).or_insert((Vec::new(), i));
        e.0.push(d);
    }
    let mut out = Vec::new();
    let mut emitted = std::collections::HashSet::new();
    for (i, b) in binds.into_iter().enumerate() {
        let group = digit_key(&b.key).and_then(|d| with_n(&b.comment, d)).map(|p| (b.mods.join("+"), p));
        match group.as_ref().and_then(|g| groups.get(g).map(|v| (g, v))) {
            Some((g, (digits, first))) if digits.len() >= 3 => {
                if emitted.insert(g.clone()) && *first <= i {
                    let lo = digits.iter().min().unwrap();
                    let hi = digits.iter().max().unwrap();
                    out.push(Bind { mods: b.mods.clone(), key: format!("{lo}–{hi}"), comment: g.1.clone() });
                }
            }
            _ => out.push(b),
        }
    }
    out
}

fn digit_key(k: &str) -> Option<u32> {
    (k.len() == 1).then(|| k.chars().next().and_then(|c| c.to_digit(10))).flatten()
}

/// The comment with the bind's own number replaced by N (only when it has
/// that number, so "Select window 3" on key 3 groups and "Zoom" does not).
/// Tab numbers counted from 1 ("Go to tab 4" on key 3) count too.
fn with_n(comment: &str, d: u32) -> Option<String> {
    for n in [d, d + 1] {
        let s = n.to_string();
        let words: Vec<&str> = comment.split(' ').collect();
        if let Some(pos) = words.iter().position(|w| *w == s) {
            let mut w: Vec<String> = words.iter().map(|x| x.to_string()).collect();
            w[pos] = "N".into();
            return Some(w.join(" "));
        }
    }
    None
}

/// A program by name, also when systemd's PATH lacks ~/.local/bin (zeit, zash, zett live there).
pub fn program(name: &str) -> std::process::Command {
    let home = std::env::var("HOME").unwrap_or_default();
    let local = format!("{home}/.local/bin/{name}");
    std::process::Command::new(if std::path::Path::new(&local).exists() { local } else { name.to_string() })
}
