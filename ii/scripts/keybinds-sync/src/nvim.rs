//! Neovim: asks a headless nvim, with your config loaded, for every mapping
//! that has a description — the ones you (or a plugin) meant to be found.
//! Leader mappings are grouped by their first key ("Space b…" = buffers),
//! each group named after what most of its mappings do.

use crate::model::{push, run, App, Bind, Section};
use std::collections::HashMap;

const LUA: &str = r#"lua local out = {}
for _, m in ipairs({ "n", "v", "i" }) do
  for _, k in ipairs(vim.api.nvim_get_keymap(m)) do
    if k.desc and k.desc ~= "" then
      table.insert(out, m .. "\t" .. k.lhs .. "\t" .. k.desc:gsub("[\t\n]", " "))
    end
  end
end
local leader = vim.g.mapleader or "\\"
io.stdout:write("LEADER\t" .. leader .. "\n" .. table.concat(out, "\n") .. "\n")"#;

/// "<C-w>" → (["Ctrl"], "W"); " " → "Space"
fn key_name(k: &str) -> (Vec<String>, String) {
    if let Some(inner) = k.strip_prefix('<').and_then(|s| s.strip_suffix('>')) {
        let mut mods = Vec::new();
        let mut rest = inner;
        loop {
            let lower = rest.to_lowercase();
            if lower.starts_with("c-") { mods.push("Ctrl".to_string()); rest = &rest[2..]; }
            else if lower.starts_with("m-") || lower.starts_with("a-") { mods.push("Alt".to_string()); rest = &rest[2..]; }
            else if lower.starts_with("s-") { mods.push("Shift".to_string()); rest = &rest[2..]; }
            else if lower.starts_with("d-") { mods.push("Super".to_string()); rest = &rest[2..]; }
            else { break; }
        }
        let key = match rest.to_lowercase().as_str() {
            "cr" => "Enter".into(), "esc" => "Escape".into(), "bs" => "Backspace".into(), "tab" => "Tab".into(),
            "space" => "Space".into(), "leader" => "Leader".into(), "lt" => "<".into(), "bar" => "|".into(), "bslash" => "\\".into(), _ => rest.to_string(),
        };
        return (mods, key);
    }
    (Vec::new(), if k == " " { "Space".into() } else { k.to_string() })
}

/// Split a mapping's keys into readable tokens: "<C-w>v" → ["<C-w>", "v"]
fn tokens(lhs: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut chars = lhs.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '<' {
            let mut t = String::from("<");
            for d in chars.by_ref() {
                t.push(d);
                if d == '>' { break; }
            }
            out.push(t);
        } else {
            out.push(c.to_string());
        }
    }
    out
}

pub fn extract() -> Option<App> {
    let text = run("nvim", &["--headless", "-c", LUA, "-c", "qa!"])?;
    let mut leader = String::from("\\");
    let mut rows: Vec<(String, String, String)> = Vec::new();
    for line in text.lines() {
        let mut f = line.splitn(3, '\t');
        let (a, b, c) = (f.next()?, f.next().unwrap_or(""), f.next().unwrap_or(""));
        if a == "LEADER" { leader = b.to_string(); continue; }
        if !b.is_empty() && !c.is_empty() { rows.push((a.to_string(), b.to_string(), c.trim().to_string())); }
    }
    let leader_name = if leader == " " { "Space".to_string() } else { leader.clone() };

    // name each leader group after the most common first word of its mappings
    let mut words: HashMap<String, HashMap<String, usize>> = HashMap::new();
    for (mode, lhs, desc) in &rows {
        if mode == "n" && lhs.starts_with(&leader) {
            let g = tokens(&lhs[leader.len()..]).first().cloned().unwrap_or_default();
            let w = desc.split_whitespace().next().unwrap_or("").to_lowercase();
            *words.entry(g).or_default().entry(w).or_default() += 1;
        }
    }
    // A group of one or two mappings is not worth a heading: those go together
    // under "Space … more". Real groups are named by the key and the word most
    // of their mappings start with ("Space b · Delete" → buffers).
    let group_name = |g: &str| -> String {
        let counts = words.get(g);
        let total: usize = counts.map(|m| m.values().sum()).unwrap_or(0);
        if total < 3 || g.trim().is_empty() {
            return format!("{leader_name} … more");
        }
        let top = counts.and_then(|m| m.iter().max_by_key(|(_, n)| **n).map(|(w, _)| w.clone())).unwrap_or_default();
        let top: String = top.trim_matches(|c: char| !c.is_alphanumeric()).to_string();
        let mut t = top.chars();
        let top = match t.next() { Some(f) => f.to_uppercase().collect::<String>() + t.as_str(), None => String::new() };
        let shown = if g == "<lt>" { "<".to_string() } else { g.to_string() };
        format!("{leader_name} {shown} · {top}")
    };

    let mut sections: Vec<Section> = Vec::new();
    let mut order: Vec<String> = Vec::new();
    for (mode, lhs, desc) in &rows {
        let (section, keys) = if mode == "n" && lhs.starts_with(&leader) {
            let rest = &lhs[leader.len()..];
            let toks = tokens(rest);
            let g = toks.first().cloned().unwrap_or_default();
            (group_name(&g), toks)
        } else {
            (match mode.as_str() { "v" => "Visual mode".to_string(), "i" => "Insert mode".to_string(), _ => "Other".to_string() }, tokens(lhs))
        };
        if keys.is_empty() { continue; }
        // first token's modifiers become the bind's; the rest is the key sequence
        let (mut mods, first) = key_name(&keys[0]);
        let mut seq = vec![first];
        seq.extend(keys[1..].iter().map(|t| { let (m, k) = key_name(t); if m.is_empty() { k } else { format!("{}+{}", m.join("+"), k) } }));
        if mode == "n" && lhs.starts_with(&leader) { mods.insert(0, "Leader".into()); }
        if !order.contains(&section) { order.push(section.clone()); }
        push(&mut sections, &section, Bind { mods, key: seq.join(" "), comment: desc.clone() });
    }
    // leader groups by key, then Visual / Insert / Other at the end
    let mut leader_groups: Vec<String> = order.iter().filter(|s| s.starts_with(&leader_name)).cloned().collect();
    leader_groups.sort();
    // "… more" sorts after the real groups
    leader_groups.retain(|s| !s.ends_with("… more"));
    let more = format!("{leader_name} … more");
    let mut ord: Vec<&str> = leader_groups.iter().map(String::as_str).collect();
    ord.push(&more);
    ord.extend(["Other", "Visual mode", "Insert mode"]);
    Some(App::new("nvim", "Neovim", "code", format!("Leader = {leader_name}"), sections, &ord))
}
